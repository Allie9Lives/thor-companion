import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'diagnostics.dart';
import 'battery_widget.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'ble_transport.dart';
import 'adaptive_transport.dart';
import 'telemetry.dart';
import 'controls.dart';
import 'keyboard_input.dart';
import 'screenshot_transfer.dart';
import 'battery_history.dart';
import 'battery_alerts.dart';
import 'file_transfer.dart';

enum CompanionPhase { idle, scanning, connecting, connected }

class _SettingRequest {
  _SettingRequest(this.key, this.value, this.target, this.session);
  final String key, target;
  final int value, session;
  final done = Completer<void>();
}

class CompanionController extends ChangeNotifier {
  CompanionController({
    required BleTransport transport,
    bool rememberDevice = true,
    this.backgroundReconnect = false,
    Duration Function(int)? retryDelay,
    Future<void> Function(BatteryWidgetSnapshot?)? batteryPublisher,
  }) : _transport = transport,
       _rememberDevice = rememberDevice,
       _retryDelay = retryDelay,
       _batteryPublisher = batteryPublisher ?? publishBatteryWidget,
       isDemo = false {
    if (transport is AdaptiveTransport) transport.addListener(_notify);
    _radioSubscription = transport.radio.listen(
      (value) {
        final previous = radioState;
        radioState = value;
        if (value == RadioState.ready && previous != RadioState.ready) {
          _backgroundAttempted = false;
        }
        if (value == RadioState.off ||
            value == RadioState.unauthorized ||
            value == RadioState.unavailable) {
          error = radioMessage;
          unawaited(_radioUnavailable());
        }
        if (value == RadioState.ready) _scheduleReconnect(immediate: true);
        _notify();
      },
      onError: (Object e) {
        error =
            'Bluetooth is unavailable. Check your phone’s Bluetooth settings.';
        _notify();
      },
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkForMissedUpdates();
      if (_foreground && !keepAlivePaused) unawaited(refreshActivity());
      if (controlsVisible &&
          !keepAlivePaused &&
          !powerBusy &&
          _foreground &&
          connected &&
          !reading &&
          !initializing &&
          !controlBusy &&
          !_settingsDraining) {
        unawaited(refreshControls());
      }
      _notify();
    });
    if (rememberDevice) unawaited(_restore());
  }

  CompanionController.demo()
    : backgroundReconnect = false,
      _retryDelay = null,
      _batteryPublisher = null,
      _transport = null,
      _rememberDevice = false,
      isDemo = true {
    phase = CompanionPhase.connected;
    radioState = RadioState.ready;
    selected = const NearbyThor('demo', 'AYN Thor', -53);
    stats = DeviceStats.fromBytes(
      utf8.encode(
        jsonEncode({
          'seq': 35,
          'ts_ms': DateTime.now().millisecondsSinceEpoch,
          'battery_pct': 69,
          'temp_c': 30.0,
          'voltage_mv': 3890,
          'current_ua_raw': 1085000,
          'charge_uah': 4082000,
          'status_code': 2,
          'plugged_code': 2,
          'interactive': false,
          'free_bytes': 773718495232,
          'cpu_pct': 14.6,
          'cpu_window_ms': 30000,
          'gpu_pct': 8,
          'input_w': 6.4,
          'ram_free_bytes': 9673871360,
          'sd_state': 'mounted',
          'sd_total_bytes': 511801556992,
          'sd_free_bytes': 260961730560,
        }),
      ),
    );
    hardware = const DeviceHardware(
      model: 'AYN Thor',
      android: '13',
      build: 'Thor_V1.0.0.377_20260206_165408_user',
      ramBytes: 15996096512,
      dataBytes: 1011194642432,
      storageModel: 'KLUGGARHHD-B0G1',
      ufsVersion: '4.0',
      cpuName: 'Qualcomm Snapdragon 8 Gen 2',
      socModel: 'QCS8550',
      variant: 'Max',
      deviceName: 'My Thor',
      storageCapacityBytes: 1000000000000,
      gpuName: 'Adreno 740',
    );
    controls = ThorControlState.fromBytes(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'settings': true,
          'bt': 39,
          'bb': 39,
          'vt': 80,
          'vb': 80,
          'hz': 60,
          'fan': 4,
          'performance': 0,
          'bypass': 0,
          'focus': 0,
          'vibration': 1,
          'led': 1,
          'style': 1,
          'ack': '',
          'error': '',
        }),
      ),
    );
    receivedAt = DateTime.now();
    heartbeatAt = receivedAt;
    receivedCount = 13;
    notificationsRequested = true;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
  }

  final bool backgroundReconnect;
  bool _backgroundAttempted = false, _backgroundPending = false;
  final Duration Function(int)? _retryDelay;
  final Future<void> Function(BatteryWidgetSnapshot?)? _batteryPublisher;
  bool automaticReconnect = true;
  bool _wantsConnection = false, _foreground = true;
  bool _manualRecoveryRequired = false;
  int retryAttempt = 0;
  int _intentEpoch = 0;
  DateTime? retryAt;
  String? widgetError;
  Timer? _retryTimer;
  Future<void> _cleanup = Future<void>.value();
  final BleTransport? _transport;
  AdaptiveTransport? get adaptive =>
      _transport is AdaptiveTransport ? _transport : null;
  final bool _rememberDevice;
  final bool isDemo;
  CompanionPhase phase = CompanionPhase.idle;
  RadioState radioState = RadioState.starting;
  final Map<String, NearbyThor> nearby = {};
  ThorControlState? controls;
  String? controlError;
  bool get keepAlivePaused => controls?.values['sleep_suspended'] is bool
      ? controls!.values['sleep_suspended'] == true
      : stats?.keepAlivePaused == true;
  void _syncSaving() {
    final value = controls?.values['sleep_restore_at'];
    adaptive?.setSleeping(
      keepAlivePaused,
      resumeAt: value is int && value > 0
          ? DateTime.fromMillisecondsSinceEpoch(value)
          : null,
    );
  }

  bool controlBusy = false;
  bool brightnessLinked = false, volumeLinked = false;
  Future<void> setControlLink({bool? brightness, bool? volume}) async {
    brightnessLinked = brightness ?? brightnessLinked;
    volumeLinked = volume ?? volumeLinked;
    _notify();
    if (_rememberDevice) {
      final store = SharedPreferencesAsync();
      await store.setBool('brightness_linked', brightnessLinked);
      await store.setBool('volume_linked', volumeLinked);
    }
  }

  Future<void> refreshControls() async {
    if (_transport is! ControlTransport ||
        !connected ||
        selected == null ||
        controlBusy) {
      return;
    }
    final session = _session, id = selected!.id;
    controlBusy = true;
    _notify();
    try {
      final bytes = await _transport!
          .read(id, controlId)
          .timeout(const Duration(seconds: 10));
      if (session != _session || !connected) return;
      controls = ThorControlState.fromBytes(bytes);
      _syncSaving();
      controlError = null;
    } catch (e) {
      if (session == _session) {
        controlError =
            'Controls unavailable. Check that Thor Monitor is updated and running.';
      }
    } finally {
      controlBusy = false;
      _flushRefreshAfterControl();
      _notify();
    }
  }

  String get deviceDisplayName =>
      hardware?.deviceName ?? selected?.name ?? 'AYN Thor';
  Map<String, dynamic>? activity;
  DateTime? _activityAttempt;
  String? _activityDevice;
  int _seenActivityWarning = 0;
  bool _detailsPending = false;
  Future<Map<String, dynamic>> _requestDetails(String command) async {
    if (_transport is! ControlTransport ||
        !connected ||
        selected == null ||
        isDemo ||
        _detailsPending) {
      throw StateError('Connect to the Thor over Bluetooth first.');
    }
    _detailsPending = true;
    final session = _session, device = selected!.id;
    var owns = false;
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (reading ||
          initializing ||
          controlBusy ||
          _settingsDraining ||
          powerBusy) {
        if (_disposed ||
            session != _session ||
            !connected ||
            DateTime.now().isAfter(deadline)) {
          throw StateError('The Thor is busy. Try again.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (session != _session || !connected || _disposed) {
        throw StateError('Connection changed.');
      }
      owns = controlBusy = true;
      final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_d';
      await (_transport as ControlTransport)
          .writeControl(
            device,
            utf8.encode(
              jsonEncode({
                'id': id,
                'set': command,
                'value': command == 'files_session' ? 1 : 0,
              }),
            ),
          )
          .timeout(const Duration(seconds: 10));
      final j = decodeObject(
        await _transport!
            .read(device, controlId)
            .timeout(const Duration(seconds: 10)),
      );
      if (session != _session || j['ack'] != id || j['error'] != '') {
        throw StateError(
          j['error'] is String && (j['error'] as String).isNotEmpty
              ? j['error'] as String
              : 'Could not read this Thor feature.',
        );
      }
      return j;
    } finally {
      if (owns) controlBusy = false;
      _detailsPending = false;
      _flushRefreshAfterControl();
      _notify();
    }
  }

  Future<Map<String, dynamic>> pairFiles() async {
    final j = await _requestDetails('files_session');
    final result = {...j, 'name': deviceDisplayName};
    await adaptive?.configure(FileConnection.fromMap(result));
    return result;
  }

  Future<void> refreshActivity() async {
    if (!connected ||
        reading ||
        initializing ||
        controlBusy ||
        _detailsPending ||
        isDemo ||
        controls?.values['activity'] != true ||
        (_activityAttempt != null &&
            DateTime.now().difference(_activityAttempt!) <
                const Duration(seconds: 25))) {
      return;
    }
    _activityAttempt = DateTime.now();
    try {
      final device = selected!.id, j = await _requestDetails('activity');
      if (!connected || selected?.id != device) return;
      activity = j;
      if (_activityDevice != device) {
        _activityDevice = device;
        _seenActivityWarning = _rememberDevice
            ? await SharedPreferencesAsync().getInt('activity_seen:$device') ??
                  0
            : 0;
      }
      final warning = (j['warning'] as num?)?.toInt() ?? 0;
      if (warning > _seenActivityWarning) {
        _seenActivityWarning = warning;
        if (_rememberDevice) {
          await SharedPreferencesAsync().setInt(
            'activity_seen:$device',
            warning,
          );
        }
        if (batteryAlertOptions.enabled &&
            batteryAlertOptions.closedLid &&
            (j['at'] is num &&
                (j['at'] as num) - warning >= 0 &&
                (j['at'] as num) - warning < 90000) &&
            j['lid'] == true) {
          final apps = (j['apps'] as List?) ?? [];
          final names = apps.map((a) => a['name'] ?? a['p']).join(', ');
          await showBatteryAlert(
            BatteryAlert(
              'closedLid',
              deviceDisplayName,
              '${j['reason']}. Lid closed for ${(j['closed_s'] as num).toInt() ~/ 60} minutes. ${names.isEmpty ? '' : 'Focused: $names.'} GPU activity is device-wide.',
            ),
          );
        }
      }
      _notify();
    } catch (_) {
      /* Optional diagnostics never break the telemetry connection. */
    }
  }

  bool controlsVisible = false;
  final batteryLedger = BatteryLedger();
  BatteryAlertOptions batteryAlertOptions = BatteryAlertOptions();
  BatteryAlertTracker _batteryAlertTracker = BatteryAlertTracker();
  String? _batteryDevice, batteryHistoryError, batteryAlertError;
  bool batteryHistoryBusy = false, _batteryOptionsLoaded = false;

  Future<void> _observeBattery(DeviceStats sample, String device) async {
    try {
      final store = SharedPreferencesAsync();
      if (!_batteryOptionsLoaded) {
        _batteryOptionsLoaded = true;
        if (_rememberDevice) {
          final options = await store.getString('battery_alert_options');
          if (options != null) {
            batteryAlertOptions = BatteryAlertOptions.fromMap(
              jsonDecode(options) as Map<String, dynamic>,
            );
          }
        }
      }
      if (_batteryDevice != device) {
        _batteryDevice = device;
        batteryLedger.points.clear();
        batteryLedger.sleepEvents.clear();
        _batteryAlertTracker = BatteryAlertTracker();
        if (_rememberDevice) {
          try {
            final cached = await store.getString('battery_history:$device');
            if (cached != null) batteryLedger.load(cached);
            final rest = await store.getString('battery_sleep:$device');
            if (rest != null) batteryLedger.loadSleep(rest);
          } catch (_) {}
          try {
            final cached = await store.getString('battery_alert_state:$device');
            if (cached != null) {
              _batteryAlertTracker.load(
                jsonDecode(cached) as Map<String, dynamic>,
              );
            }
          } catch (_) {}
        }
      }
      final changed = batteryLedger.observe(sample);
      if (sample.battery != null &&
          sample.pluggedCode != null &&
          sample.sourceTimeMs != null) {
        final alerts = _batteryAlertTracker.observe(
          sample.battery!,
          sample.pluggedCode != 0,
          sample.sourceTimeMs!,
          batteryAlertOptions,
        );
        for (final alert in alerts) {
          try {
            await showBatteryAlert(alert.forDevice(deviceDisplayName));
            batteryAlertError = null;
          } catch (_) {
            batteryAlertError =
                'Could not deliver a battery alert. Check notification permission.';
          }
        }
      }
      if (_rememberDevice) {
        if (changed) {
          await store.setString(
            'battery_history:$device',
            batteryLedger.encode(),
          );
        }
        await store.setString(
          'battery_alert_state:$device',
          jsonEncode(_batteryAlertTracker.toMap()),
        );
      }
    } catch (_) {
      /* Cached history or alerts must not interrupt live readings. */
    }
  }

  Future<bool> enableBatteryAlerts(bool enabled) async {
    batteryAlertError = null;
    if (enabled) {
      try {
        if (!await requestBatteryAlertPermission()) {
          batteryAlertError =
              'Allow notifications for Thor Companion in system settings.';
          _notify();
          return false;
        }
      } catch (_) {
        batteryAlertError = 'Could not request notification permission.';
        _notify();
        return false;
      }
    }
    batteryAlertOptions.enabled = enabled;
    await saveBatteryAlertOptions();
    return true;
  }

  Future<void> saveBatteryAlertOptions() async {
    _batteryOptionsLoaded = true;
    if (_rememberDevice) {
      await SharedPreferencesAsync().setString(
        'battery_alert_options',
        jsonEncode(batteryAlertOptions.toMap()),
      );
    }
    _notify();
  }

  Future<void> testBatteryAlert() async {
    try {
      await showBatteryAlert(
        BatteryAlert(
          'test',
          deviceDisplayName,
          'Battery alerts are ready on this device.',
        ),
      );
      batteryAlertError = null;
    } catch (_) {
      batteryAlertError =
          'Could not send the test alert. Check system notification settings.';
    }
    _notify();
  }

  Future<void> loadBatteryHistory() async {
    if (_transport is! ControlTransport ||
        !connected ||
        selected == null ||
        reading ||
        initializing ||
        controlBusy ||
        _settingsDraining ||
        isDemo) {
      return;
    }
    if (controls?.values['history'] != true) {
      batteryHistoryError = 'Update Thor Monitor to load recorded history.';
      _notify();
      return;
    }
    final session = _session, device = selected!.id;
    batteryHistoryBusy = controlBusy = true;
    batteryHistoryError = null;
    _notify();
    try {
      var cursor = 0;
      final samples = <BatteryPoint>[];
      for (var page = 0; page < 3000; page++) {
        if (_disposed || session != _session || !connected || !_foreground) {
          throw StateError('History sync interrupted. Reconnect and refresh.');
        }
        final id =
            '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_h';
        await (_transport as ControlTransport)
            .writeControl(
              device,
              utf8.encode(
                jsonEncode({
                  'id': id,
                  'set': 'battery_history',
                  'value': cursor,
                  'target': '7d',
                }),
              ),
            )
            .timeout(const Duration(seconds: 10));
        final reply = decodeObject(
          await _transport!
              .read(device, controlId)
              .timeout(const Duration(seconds: 10)),
        );
        if (session != _session || !connected) {
          throw StateError('History sync interrupted.');
        }
        if (reply['ack'] != id ||
            reply['error'] != '' ||
            reply['history'] is! List) {
          throw StateError('Could not read battery history.');
        }
        final rows = reply['history'] as List;
        if (rows.length > 4) {
          throw const FormatException('Invalid battery history page.');
        }
        samples.addAll(rows.map((row) => BatteryPoint.fromList(row as List)));
        if (samples.length > 10000) {
          throw const FormatException('Battery history exceeded its limit.');
        }
        if (reply['more'] != true) {
          batteryLedger.merge(samples);
          if (controls?.values['sleep_policy'] == true) {
            await _loadSleepEvents(session, device);
          }

          logBle(
            'Thor battery history synced: ${samples.length} recorded samples',
          );
          if (_rememberDevice) {
            await SharedPreferencesAsync().setString(
              'battery_sleep:$device',
              batteryLedger.encodeSleep(),
            );
            await SharedPreferencesAsync().setString(
              'battery_history:$device',
              batteryLedger.encode(),
            );
          }
          return;
        }
        final next = reply['next'];
        if (next is! int || next <= cursor) {
          throw const FormatException('Invalid history cursor.');
        }
        cursor = next;
      }
      throw StateError('Battery history exceeded its limit.');
    } catch (e) {
      batteryHistoryError = e is StateError
          ? e.message
          : 'Could not sync battery history. Try again.';
    } finally {
      batteryHistoryBusy = controlBusy = false;
      _refreshAfterControl = true;
      _flushRefreshAfterControl();
      _notify();
    }
  }

  Future<void> _loadSleepEvents(int session, String device) async {
    final events = <SleepEvent>[];
    var cursor = 0;
    for (var page = 0; page < 300; page++) {
      if (_disposed || session != _session || !connected || !_foreground) {
        throw StateError('History sync interrupted.');
      }
      final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_s';
      await (_transport as ControlTransport)
          .writeControl(
            device,
            utf8.encode(
              jsonEncode({'id': id, 'set': 'battery_sleep', 'value': cursor}),
            ),
          )
          .timeout(const Duration(seconds: 10));
      final j = decodeObject(
        await _transport!
            .read(device, controlId)
            .timeout(const Duration(seconds: 10)),
      );
      if (j['ack'] != id || j['error'] != '' || j['sleep_events'] is! List) {
        throw StateError('Could not read battery-saving history.');
      }
      final rows = j['sleep_events'] as List;
      if (rows.length > 8) {
        throw const FormatException('Invalid sleep history page');
      }
      events.addAll(rows.map((r) => SleepEvent.fromList(r as List)));
      if (j['more'] != true) {
        batteryLedger.mergeSleep(events);
        return;
      }
      final next = j['next'];
      if (next is! int || next <= cursor) {
        throw const FormatException('Invalid sleep cursor');
      }
      cursor = next;
    }
    throw StateError('Sleep history exceeded its limit.');
  }

  Timer? _powerRefreshTimer;
  bool powerBusy = false;
  Future<bool> devicePower(int action) async {
    if (!const {0, 1, 2, 3, 4}.contains(action) ||
        _transport is! ControlTransport ||
        !connected ||
        (stale && !(action == 3 && keepAlivePaused)) ||
        selected == null ||
        isDemo ||
        powerBusy) {
      throw StateError('Wait for the Thor connection, then try again.');
    }
    final session = _session, device = selected!.id;
    var ownsTransaction = false;
    powerBusy = true;
    _notify();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controlBusy || reading || initializing || _settingsDraining) {
        if (_disposed ||
            session != _session ||
            !connected ||
            DateTime.now().isAfter(deadline)) {
          throw StateError('The Thor is busy or disconnected. Try again.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (_disposed ||
          session != _session ||
          !connected ||
          (stale && !(action == 3 && keepAlivePaused))) {
        throw StateError(
          'The Thor connection changed. Check it before trying again.',
        );
      }
      ownsTransaction = controlBusy = true;
      final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_p';
      await (_transport as ControlTransport)
          .writeControl(
            device,
            utf8.encode(
              jsonEncode({'id': id, 'set': 'power', 'value': action}),
            ),
          )
          .timeout(const Duration(seconds: 10));
      final reply = decodeObject(
        await _transport!
            .read(device, controlId)
            .timeout(const Duration(seconds: 3)),
      );
      if (session != _session || reply['ack'] != id || reply['error'] != '') {
        throw StateError(
          'Could not confirm the power command. Check the Thor before retrying.',
        );
      }
      if (reply['sleep_suspended'] is bool) {
        controls?.values['sleep_suspended'] = reply['sleep_suspended'];
        _syncSaving();
      }
      if (action == 3) {
        controls?.values['sleep_suspended'] = false;
        adaptive?.setSleeping(false);
      }
      if (action == 0 || action == 3 || action == 4) {
        controls?.values['screens_awake'] = action == 3;
      }
      if (action == 0 || action == 3) {
        _powerRefreshTimer?.cancel();
        _powerRefreshTimer = Timer(const Duration(milliseconds: 1300), () {
          if (!_disposed && connected) unawaited(refresh());
        });
      }
      return true;
    } finally {
      if (ownsTransaction) controlBusy = false;
      powerBusy = false;
      _flushRefreshAfterControl();
      _notify();
    }
  }

  ScreenshotReceiver? _screenshotReceiver;
  int _screenshotGeneration = 0;
  bool screenshotBusy = false;
  double screenshotProgress = 0;

  Future<Uint8List> captureScreens(int mode) async {
    if (!const {0, 1, 2}.contains(mode) ||
        _transport is! ControlTransport ||
        !connected ||
        stale ||
        reading ||
        initializing ||
        controlBusy ||
        _settingsDraining ||
        selected == null ||
        isDemo ||
        !notificationsRequested) {
      throw StateError('Wait for the Thor connection, then try again.');
    }
    if (controls?.values['screenshots'] != true) {
      throw StateError('Update Thor Monitor to capture screenshots.');
    }
    final session = _session, device = selected!.id;
    String? token;
    final generation = ++_screenshotGeneration;
    controlBusy = screenshotBusy = true;
    screenshotProgress = 0;
    _notify();
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      Future<void> command(
        String key,
        int value,
        String requestId, [
        String target = '',
      ]) async {
        if (_disposed ||
            session != _session ||
            !connected ||
            !_foreground ||
            generation != _screenshotGeneration) {
          throw StateError('Screenshot cancelled.');
        }
        await (_transport as ControlTransport)
            .writeControl(
              device,
              utf8.encode(
                jsonEncode({
                  'id': requestId,
                  'set': key,
                  'value': value,
                  'target': target,
                }),
              ),
            )
            .timeout(const Duration(seconds: 25));
      }

      await command('screenshot', mode, id);
      if (_disposed || session != _session || !connected) {
        throw StateError('Connection ended during capture.');
      }
      final reply = ThorControlState.fromBytes(
        await _transport!
            .read(device, controlId)
            .timeout(const Duration(seconds: 10)),
      );
      if (reply.values['ack'] != id || reply.values['error'] != '') {
        throw StateError(
          reply.values['error'] as String? ??
              'The Thor did not confirm the capture.',
        );
      }
      token = reply.values['shot_token'] as String?;
      final length = reply.number('shot_bytes'), crc = reply.number('shot_crc');
      final number = int.tryParse(token ?? '');
      if (number == null ||
          number < 0 ||
          number > 0xffffffff ||
          length == null ||
          crc == null) {
        throw StateError(
          'Screenshot unavailable. Check Automatic recovery on the Thor.',
        );
      }
      final receiver = ScreenshotReceiver(number, length, crc, (progress) {
        final changed =
            (progress * 100).floor() != (screenshotProgress * 100).floor();
        screenshotProgress = progress;
        if (changed || progress == 1) _notify();
      });
      _screenshotReceiver = receiver;
      // Attach error handling before any native operation can end the stream.
      final received = receiver.done.future;
      unawaited(received.then<void>((_) {}, onError: (Object _) {}));
      receiver.start();
      await command('screenshot_stream', 1, '${id}_stream', token!);
      final image = await received.timeout(const Duration(seconds: 300));
      logBle('Screenshot received: mode=$mode bytes=${image.length}');
      return image;
    } finally {
      final receiver = _screenshotReceiver;
      _screenshotReceiver = null;
      receiver?.fail('Screenshot capture ended.');
      if (token != null && session == _session && connected) {
        try {
          await (_transport as ControlTransport)
              .writeControl(
                device,
                utf8.encode(
                  jsonEncode({
                    'id':
                        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_clear',
                    'set': 'screenshot_clear',
                    'value': 0,
                    'target': token,
                  }),
                ),
              )
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          /* Host expiry/disconnect also releases the memory. */
        }
      }
      screenshotBusy = controlBusy = false;
      _refreshAfterControl = true;
      _flushRefreshAfterControl();
      _notify();
    }
  }

  void cancelScreenshot() {
    _screenshotGeneration++;
    _screenshotReceiver?.fail('Screenshot cancelled.');
  }

  String? keyboardError;
  bool keyboardBusy = false;
  int _keyboardRequest = 0;

  Future<bool> sendKeyboardText(String text) async {
    try {
      return await _sendKeyboard(
        splitKeyboardText(text).map((s) => ('text', s)).toList(),
      );
    } on FormatException catch (e) {
      keyboardError = e.message;
      _notify();
      return false;
    }
  }

  Future<bool> sendKeyboardKey(String key) async {
    if (!const {
      'backspace',
      'enter',
      'tab',
      'left',
      'right',
      'up',
      'down',
    }.contains(key)) {
      return false;
    }
    return _sendKeyboard([('key', key)]);
  }

  Future<bool> _sendKeyboard(List<(String, String)> commands) async {
    if (_transport is! ControlTransport ||
        !connected ||
        stale ||
        reading ||
        initializing ||
        controlBusy ||
        selected == null ||
        isDemo) {
      keyboardError = 'Wait for the Thor connection, then try again.';
      _notify();
      return false;
    }
    if (controls?.values['keyboard'] != true) {
      keyboardError = 'Update Thor Monitor to use the phone keyboard.';
      _notify();
      return false;
    }
    final session = _session, device = selected!.id;
    controlBusy = keyboardBusy = true;
    keyboardError = null;
    _notify();
    var sent = 0;
    try {
      for (final (command, value) in commands) {
        if (_disposed || session != _session || !connected || !_foreground) {
          throw StateError(
            'Typing stopped because the connection or app changed.',
          );
        }
        final id =
            '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${(_keyboardRequest++).toRadixString(36)}';
        final bytes = utf8.encode(
          jsonEncode({'id': id, 'set': command, 'value': value}),
        );
        await (_transport as ControlTransport)
            .writeControl(device, bytes)
            .timeout(const Duration(seconds: 10));
        if (_disposed || session != _session || !connected) {
          throw StateError('Connection ended.');
        }
        final response = await _transport!
            .read(device, controlId)
            .timeout(const Duration(seconds: 10));
        if (_disposed || session != _session || !connected) {
          throw StateError('Connection ended.');
        }
        final result = ThorControlState.fromBytes(response);
        controls = result;
        if (result.values['ack'] != id) {
          throw StateError('The Thor did not confirm the input.');
        }
        if (result.values['error'] != '') {
          throw StateError(
            result.values['error'] as String? ?? 'The Thor rejected the input.',
          );
        }
        sent++;
      }
      return true;
    } catch (e) {
      // Never log text or retry non-idempotent input after an uncertain result.
      keyboardError =
          '${e is StateError ? e.message : "Could not confirm the input."} '
          '${sent > 0 ? "Part of the text was sent. " : ""}Check the Thor before sending again.';
      return false;
    } finally {
      controlBusy = keyboardBusy = false;
      _flushRefreshAfterControl();
      _notify();
    }
  }

  final _pendingSettings = <String, _SettingRequest>{};
  _SettingRequest? _activeSetting;
  bool _settingsDraining = false;
  bool get applyingControls =>
      _activeSetting != null || _pendingSettings.isNotEmpty;

  List<String> _settingFields(String key, String target) => switch (key) {
    'brightness' =>
      target == 'both' ? ['bt', 'bb'] : [target == 'top' ? 'bt' : 'bb'],
    'volume' =>
      target == 'both' ? ['vt', 'vb'] : [target == 'top' ? 'vt' : 'vb'],
    'clean' => [],
    _ => [key],
  };

  int? controlNumber(String field) {
    var value = controls?.number(field);
    for (final request in [?_activeSetting, ..._pendingSettings.values]) {
      if (request.session == _session &&
          _settingFields(request.key, request.target).contains(field)) {
        value = request.value;
      }
    }
    return value;
  }

  Future<void> setControl(String key, int value, {String target = ''}) {
    if (_disposed ||
        isDemo ||
        _transport is! ControlTransport ||
        !connected ||
        stale ||
        selected == null) {
      return Future.value();
    }
    if (!const {
          'brightness',
          'volume',
          'hz',
          'fan',
          'performance',
          'focus',
          'bypass',
          'vibration',
          'style',
          'clean',
          'led',
          'find',
          'sleep_end',
        }.contains(key) ||
        ((key == 'brightness' || key == 'volume') &&
            !const {'top', 'bottom', 'both'}.contains(target))) {
      return Future.value();
    }
    final request = _SettingRequest(key, value, target, _session);
    // Only unsent settings coalesce. Move replacements to the end so ordering
    // remains correct when linked and individual screen targets are mixed.
    _pendingSettings.remove('$key:$target')?.done.complete();
    _pendingSettings['$key:$target'] = request;
    controlError = null;
    _notify();
    unawaited(_drainSettings());
    return request.done.future;
  }

  void _cancelPendingSettings() {
    for (final request in _pendingSettings.values) {
      request.done.complete();
    }
    _pendingSettings.clear();
  }

  Future<void> _drainSettings() async {
    if (_disposed ||
        _settingsDraining ||
        controlBusy ||
        reading ||
        initializing) {
      return;
    }
    _settingsDraining = true;
    try {
      while (_pendingSettings.isNotEmpty) {
        if (_disposed || !connected || stale || !_foreground) {
          _cancelPendingSettings();
          break;
        }
        final request = _pendingSettings.remove(_pendingSettings.keys.first)!;
        if (request.session != _session) {
          request.done.complete();
          continue;
        }
        _activeSetting = request;
        try {
          await _applyControl(
            request.key,
            request.value,
            target: request.target,
          );
        } finally {
          _activeSetting = null;
          request.done.complete();
          _notify();
        }
      }
    } finally {
      _settingsDraining = false;
      _flushRefreshAfterControl();
    }
  }

  Future<void> _applyControl(
    String key,
    int value, {
    String target = '',
  }) async {
    if (_transport is! ControlTransport ||
        !connected ||
        stale ||
        reading ||
        initializing ||
        controlBusy ||
        selected == null) {
      return;
    }
    final session = _session, device = selected!.id;
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    controlBusy = true;
    _notify();
    try {
      await (_transport as ControlTransport)
          .writeControl(
            device,
            utf8.encode(
              jsonEncode({
                'id': id,
                'set': key,
                'value': value,
                'target': target,
              }),
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (session != _session || !connected) return;
      var bytes = await _transport!
          .read(device, controlId)
          .timeout(const Duration(seconds: 10));
      if (session != _session || !connected) return;
      var result = ThorControlState.fromBytes(bytes);
      final tolerance = key == 'volume'
          ? 4
          : key == 'brightness'
          ? 2
          : 0;
      bool matches(ThorControlState state) => _settingFields(key, target).every(
        (field) =>
            state.number(field) != null &&
            (state.number(field)! - value).abs() <= tolerance,
      );
      for (
        var attempt = 0;
        attempt < 3 &&
            result.values['ack'] == id &&
            result.values['error'] == '' &&
            !matches(result);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (session != _session || !connected) return;
        bytes = await _transport
            .read(device, controlId)
            .timeout(const Duration(seconds: 10));
        if (session != _session || !connected) return;
        result = ThorControlState.fromBytes(bytes);
      }
      controls = result;
      if (result.values['ack'] != id) {
        controlError =
            'Could not confirm the change. Refresh controls before trying again.';
      } else if (result.values['error'] != '') {
        controlError = result.values['error'] as String;
      } else {
        if (!matches(result)) {
          controlError =
              'The Thor reported a different value. Its current settings are shown.';
        }
      }
    } catch (e) {
      if (session == _session) {
        controlError =
            'Could not confirm the change. Refresh controls before trying again.';
      }
    } finally {
      controlBusy = false;
      _flushRefreshAfterControl();
      _notify();
    }
  }

  NearbyThor? selected, remembered;
  DeviceStats? stats;
  DeviceHardware? hardware;
  Heartbeat? heartbeat;
  DateTime? receivedAt, heartbeatAt;
  String? error;
  bool notificationsRequested = false, reading = false, initializing = false;
  Object? lastFailure;
  int receivedCount = 0;
  int _session = 0;
  int _scanEpoch = 0;
  bool _disposed = false;
  bool _freshThisConnection = false;
  StreamSubscription<RadioState>? _radioSubscription;
  StreamSubscription<NearbyThor>? _scanSubscription;
  StreamSubscription<LinkState>? _connectionSubscription;
  StreamSubscription<List<int>>? _liveSubscription;
  Timer? _clock, _scanTimeout;

  bool get connected => phase == CompanionPhase.connected;
  bool get busy => phase == CompanionPhase.connecting || initializing;
  bool get stale =>
      !connected ||
      (!isDemo && !_freshThisConnection) ||
      receivedAt == null ||
      DateTime.now().difference(receivedAt!) > const Duration(seconds: 90);
  String get freshness => ageLabel(receivedAt, DateTime.now());
  String get radioMessage => switch (radioState) {
    RadioState.off => 'Turn on Bluetooth on your phone to find your Thor.',
    RadioState.unauthorized =>
      'Allow Bluetooth access in your phone’s app settings.',
    RadioState.unavailable => 'Bluetooth is unavailable on this device.',
    _ => 'Start monitoring on your Thor, then scan nearby.',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _restore() async {
    final intent = _intentEpoch;
    try {
      final store = SharedPreferencesAsync();
      final id = await store.getString('thor_device_id');
      final name = await store.getString('thor_device_name');
      brightnessLinked = await store.getBool('brightness_linked') ?? false;
      volumeLinked = await store.getBool('volume_linked') ?? false;
      final automatic = await store.getBool('automatic_reconnect');
      final wanted = await store.getBool('connection_wanted');
      if (_disposed || intent != _intentEpoch) return;
      automaticReconnect = automatic ?? true;
      _wantsConnection = wanted ?? true;
      if (!_disposed && id != null) {
        remembered = NearbyThor(id, name ?? 'AYN Thor', 0);
        _scheduleReconnect(immediate: true);
        _notify();
      }
    } catch (_) {
      /* A failed preference load must not prevent BLE use. */
    }
  }

  Future<void> _remember(NearbyThor device) async {
    remembered = device;
    if (!_rememberDevice) return;
    try {
      final store = SharedPreferencesAsync();
      await store.setString('thor_device_id', device.id);
      await store.setString('thor_device_name', device.name);
    } catch (_) {
      /* The connection remains usable without persistence. */
    }
  }

  Future<void> _saveConnectionIntent() async {
    if (!_rememberDevice) return;
    try {
      await SharedPreferencesAsync().setBool(
        'connection_wanted',
        _wantsConnection,
      );
    } catch (_) {}
  }

  Future<void> setAutomaticReconnect(bool enabled) async {
    ++_intentEpoch;
    automaticReconnect = enabled;
    if (!enabled) _cancelRetry();
    if (_rememberDevice) {
      try {
        await SharedPreferencesAsync().setBool('automatic_reconnect', enabled);
      } catch (_) {}
    }
    if (enabled) {
      _wantsConnection = true;
      await _saveConnectionIntent();
      _scheduleReconnect(immediate: true);
    }
    _notify();
  }

  DateTime? _lastRecoveryAttempt, _hardwareReadAt;
  bool _refreshAfterControl = false;

  // A physical BLE connection can outlive the Thor's GATT service. Streams
  // may also remain open without notifications. Repair a missed 30s update
  // before the 90s stale limit, without background polling or control overlap.
  void _checkForMissedUpdates() {
    if (_disposed ||
        isDemo ||
        !_foreground ||
        !connected ||
        busy ||
        reading ||
        controlBusy ||
        _manualRecoveryRequired ||
        keepAlivePaused) {
      return;
    }
    final now = DateTime.now();
    if (_lastRecoveryAttempt != null &&
        now.difference(_lastRecoveryAttempt!) < const Duration(seconds: 15)) {
      return;
    }
    if (stale || !notificationsRequested) {
      _lastRecoveryAttempt = now;
      unawaited(_recoverLink());
    } else if (now.difference(receivedAt!) >= const Duration(seconds: 45)) {
      _lastRecoveryAttempt = now;
      logBle('Thor missed live update; refreshing and restoring subscription');
      unawaited(_initialize(_session));
    }
  }

  void _flushRefreshAfterControl() {
    if (_settingsDraining) return;
    if (_pendingSettings.isNotEmpty) {
      unawaited(_drainSettings());
      return;
    }
    if (_disposed ||
        !_refreshAfterControl ||
        !connected ||
        reading ||
        initializing ||
        controlBusy) {
      return;
    }
    _refreshAfterControl = false;
    unawaited(refresh());
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    adaptive?.setForeground(foreground);
    logBle('Thor app lifecycle: ${foreground ? "foreground" : "background"}');
    if (!foreground) {
      cancelScreenshot();
      _cancelRetry();
      _scheduleReconnect();
    } else if (_backgroundPending && phase == CompanionPhase.connecting) {
      unawaited(_resumePendingConnection());
    } else if (connected) {
      if (stale || !notificationsRequested) {
        unawaited(_recoverLink());
      } else {
        unawaited(refresh());
      }
    } else {
      _scheduleReconnect(immediate: true);
    }
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    retryAt = null;
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_disposed ||
        isDemo ||
        !automaticReconnect ||
        !_wantsConnection ||
        _manualRecoveryRequired ||
        radioState != RadioState.ready ||
        connected ||
        busy ||
        phase == CompanionPhase.scanning ||
        (selected ?? remembered) == null ||
        _retryTimer != null) {
      return;
    }
    if (!_foreground) {
      if (backgroundReconnect && !_backgroundAttempted) {
        _backgroundAttempted = true;
        retryAttempt++;
        logBle('Thor BLE background native reconnect requested');
        unawaited(
          connect((selected ?? remembered)!, automatic: true, background: true),
        );
      }
      return;
    }
    const seconds = [1, 2, 4, 8, 15, 30, 60];
    final delay = immediate
        ? Duration.zero
        : _retryDelay?.call(retryAttempt) ??
              Duration(
                milliseconds:
                    seconds[math.min(retryAttempt, seconds.length - 1)] * 1000 +
                    math.Random().nextInt(250),
              );
    retryAt = DateTime.now().add(delay);
    logBle(
      'Thor BLE retry scheduled: attempt=${retryAttempt + 1} delay_ms=${delay.inMilliseconds}',
    );
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      retryAt = null;
      if (_disposed ||
          !_foreground ||
          !_wantsConnection ||
          !automaticReconnect ||
          connected ||
          busy ||
          radioState != RadioState.ready) {
        return;
      }
      final device = selected ?? remembered;
      if (device == null) return;
      retryAttempt++;
      unawaited(connect(device, automatic: true));
    });
    _notify();
  }

  Future<void> _resumePendingConnection() async {
    ++_session;
    _backgroundPending = false;
    _backgroundAttempted = false;
    phase = CompanionPhase.idle;
    notificationsRequested = false;
    initializing = reading = false;
    await _cancelLink();
    _scheduleReconnect(immediate: true);
  }

  Future<void> _radioUnavailable() async {
    _cancelRetry();
    ++_session;
    phase = CompanionPhase.idle;
    notificationsRequested = false;
    initializing = reading = false;
    _freshThisConnection = false;
    await _cancelLink();
    unawaited(_publishWidget());
    _notify();
  }

  Future<void> _recoverLink() async {
    if (_disposed ||
        !connected ||
        busy ||
        reading ||
        _manualRecoveryRequired ||
        keepAlivePaused) {
      return;
    }
    if (automaticReconnect && _wantsConnection) {
      _linkLost(_session, 'Connection interrupted. Reconnecting to your Thor…');
    } else {
      await refresh();
    }
  }

  Future<void> _publishWidget({bool clear = false}) async {
    if (isDemo || _batteryPublisher == null) return;
    final sample = stats, at = receivedAt;
    if (!clear && (sample?.battery == null || at == null)) return;
    try {
      await _batteryPublisher(
        clear
            ? null
            : BatteryWidgetSnapshot(
                percent: sample!.battery!,
                updatedAt: at!,
                charging: sample.statusCode == 2,
                connected: connected && _freshThisConnection,
              ),
      );
      widgetError = null;
      logBle(
        clear ? 'Thor widget cache cleared' : 'Thor widget snapshot saved',
      );
    } catch (e) {
      widgetError = 'Could not update the battery widget.';
      logBle('Thor widget update failed: $e');
    }
  }

  Future<void> _access() async {
    await _transport!.requestAccess();
    if (radioState == RadioState.starting) {
      radioState = await _transport.radio
          .firstWhere((s) => s != RadioState.starting)
          .timeout(const Duration(seconds: 15));
    }
    if (radioState != RadioState.ready) throw StateError(radioMessage);
  }

  Future<void> startScan() async {
    if (isDemo || busy || connected) return;
    _cancelRetry();
    await stopScan();
    final epoch = ++_scanEpoch;
    error = null;
    nearby.clear();
    phase = CompanionPhase.scanning;
    _notify();
    try {
      await _access();
      if (_disposed || epoch != _scanEpoch) return;
      _scanSubscription = _transport!.scan().listen(
        (device) {
          if (_disposed || epoch != _scanEpoch) return;
          nearby[device.id] = device;
          _notify();
        },
        onError: (Object e) {
          if (_disposed || epoch != _scanEpoch) return;
          error = 'Could not scan. Check Bluetooth and Nearby devices access.';
          unawaited(stopScan());
        },
      );
      _scanTimeout = Timer(
        const Duration(seconds: 12),
        () => unawaited(stopScan()),
      );
    } catch (e) {
      if (_disposed || epoch != _scanEpoch) return;
      error = _message(e, 'Could not start Bluetooth scanning.');
      phase = CompanionPhase.idle;
      _notify();
    }
  }

  Future<void> stopScan() async {
    ++_scanEpoch;
    _scanTimeout?.cancel();
    final scan = _scanSubscription;
    _scanSubscription = null;
    if (phase == CompanionPhase.scanning) phase = CompanionPhase.idle;
    _notify();
    await scan?.cancel();
  }

  Future<void> connect(
    NearbyThor device, {
    bool automatic = false,
    bool background = false,
  }) async {
    if (isDemo || busy) return;
    _cancelRetry();
    _wantsConnection = true;
    if (!automatic) {
      ++_intentEpoch;
      retryAttempt = 0;
      _manualRecoveryRequired = false;
    }
    unawaited(_saveConnectionIntent());
    if (connected && selected?.id == device.id) {
      await refresh();
      return;
    }
    final session = ++_session;
    _backgroundPending = background;
    phase = CompanionPhase.connecting;
    _notify();
    logBle('Thor BLE connect requested: session=$session phase=$phase');
    try {
      await stopScan();
      await _cancelLink();
    } catch (e) {
      _linkLost(session, 'Could not reset the Bluetooth connection. Retrying…');
      return;
    }
    if (_disposed || session != _session) return;
    if (selected?.id != device.id) {
      if ((selected ?? remembered)?.id != device.id) {
        unawaited(_publishWidget(clear: true));
      }
      stats = null;
      hardware = null;
      activity = null;
      _activityAttempt = null;
      controls = null;
      controlError = null;
      receivedAt = null;
      heartbeatAt = null;
      receivedCount = 0;
    }
    selected = device;
    _freshThisConnection = false;
    phase = CompanionPhase.connecting;
    error = null;
    notificationsRequested = false;
    reading = false;
    initializing = false;
    _notify();
    try {
      await _access();
      if (_disposed || session != _session) return;
      _connectionSubscription = _transport!
          .connect(device.id, background: background)
          .listen(
            (event) {
              if (_disposed || session != _session) return;
              if (event == LinkState.connected) {
                if (phase == CompanionPhase.connected) return;
                phase = CompanionPhase.connected;
                unawaited(_remember(device));
                unawaited(_initialize(session));
              } else if (event == LinkState.disconnected) {
                _linkLost(
                  session,
                  'Connection ended. Check that monitoring is running on the Thor.',
                );
              }
              _notify();
            },
            onError: (Object e) {
              if (_disposed || session != _session) return;
              lastFailure = e;
              logBle('Thor BLE connection error: $e');
              _linkLost(
                session,
                'Could not connect to the Thor. Check that monitoring is running and try again.',
              );
            },
            onDone: () {
              if (!_disposed && session == _session) {
                _linkLost(
                  session,
                  'Connection ended. Reconnecting to your Thor…',
                );
              }
            },
          );
    } catch (e) {
      _linkLost(session, _message(e, 'Could not connect to the Thor.'));
    }
  }

  Future<void> _initialize(int session) async {
    if (initializing || session != _session || !connected) return;
    initializing = true;
    notificationsRequested = false;
    error = null;
    _notify();
    try {
      await _liveSubscription?.cancel();
      _liveSubscription = null;
      await _transport!
          .discover(selected!.id)
          .timeout(const Duration(seconds: 20));
      if (_disposed || session != _session || !connected) return;
      logBle('Thor BLE service discovery complete');
      _hardwareReadAt = null; // A reconnect also picks up device renames.
      final success = await _readStats(session);
      logBle('Thor BLE initial stats read: success=$success');
      // Do not hide a read/pairing error behind a failed subscription.
      if (!success || _disposed || session != _session || !connected) return;
      notificationsRequested = true;
      _liveSubscription = _transport
          .subscribe(selected!.id, liveId)
          .listen(
            (bytes) {
              if (_disposed || session != _session) return;
              if (isScreenshotPacket(bytes)) {
                _screenshotReceiver?.add(bytes);
                return;
              }
              try {
                heartbeat = Heartbeat.fromBytes(bytes);
                heartbeatAt = DateTime.now();
                unawaited(refresh());
                _notify();
              } catch (e) {
                lastFailure = e;
                error = 'Received an unreadable update. Tap Refresh to retry.';
                _notify();
              }
            },
            onError: (Object e) {
              if (_disposed || session != _session) return;
              lastFailure = e;
              logBle('Thor BLE subscription: $e');
              notificationsRequested = false;
              error = 'Live updates stopped. Tap Refresh to restore them.';
              _notify();
            },
            onDone: () {
              if (_disposed || session != _session || !notificationsRequested) {
                return;
              }
              notificationsRequested = false;
              error = 'Live updates ended. Tap Refresh to restore them.';
              _notify();
            },
            cancelOnError: true,
          );
    } catch (e) {
      if (session == _session) {
        lastFailure = e;
        logBle('Thor BLE setup: $e');
        _manualRecoveryRequired = e is StaleServiceCache;
        notificationsRequested = false;
        error = _message(
          e,
          'Could not prepare the Thor connection. Tap Refresh to try again.',
        );
      }
    } finally {
      if (session == _session) {
        initializing = false;
        _flushRefreshAfterControl();
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    if (isDemo || !connected || reading || initializing || selected == null) {
      return;
    }
    if (controlBusy) {
      _refreshAfterControl = true;
      return;
    }
    _refreshAfterControl = false;
    if (!notificationsRequested) {
      await _initialize(_session);
    } else {
      await _readStats(_session);
    }
  }

  Future<bool> _readStats(int session) async {
    if (reading ||
        controlBusy ||
        session != _session ||
        !connected ||
        selected == null) {
      return false;
    }
    final deviceId = selected!.id;
    reading = true;
    error = null;
    _notify();
    try {
      final bytes = await _transport!
          .read(deviceId, statsId)
          .timeout(const Duration(seconds: 45));
      final next = DeviceStats.fromBytes(bytes);
      if (_disposed || session != _session) return false;
      stats = next;
      if (next.keepAlivePaused != null) {
        controls?.values['sleep_suspended'] = next.keepAlivePaused;
        adaptive?.setSleeping(next.keepAlivePaused!);
      }
      if (next.locatorActive != null && controls != null) {
        controls!.values['find'] = next.locatorActive! ? 1 : 0;
      }
      await _observeBattery(next, deviceId);
      if (_disposed || session != _session) return false;
      _freshThisConnection = true;
      receivedAt = DateTime.now();
      receivedCount++;
      retryAttempt = 0;
      _backgroundAttempted = _backgroundPending = false;
      _cancelRetry();
      unawaited(_publishWidget());
      lastFailure = null;
      _notify();
      if (hardware == null ||
          _hardwareReadAt == null ||
          DateTime.now().difference(_hardwareReadAt!) >=
              const Duration(minutes: 5)) {
        try {
          final bytes = await _transport
              .read(deviceId, hardwareId)
              .timeout(const Duration(seconds: 20));
          if (!_disposed && session == _session) {
            hardware = DeviceHardware.fromBytes(bytes);
            _hardwareReadAt = DateTime.now();
            logBle(
              'Thor hardware received: variant=${hardware?.variant}, storage=${hardware?.storageConfiguration}, configuredName=${hardware?.deviceName != null}',
            );
            final name = hardware?.deviceName;
            if (name != null) {
              selected = NearbyThor(deviceId, name, selected!.rssi);
              await _remember(selected!);
            }
          }
        } catch (e) {
          if (session == _session) {
            lastFailure = e;
            error =
                'Readings received. Tap Refresh to retry the device details.';
          }
        }
      }
      if (_foreground &&
          !controlBusy &&
          _transport is ControlTransport &&
          (_transport as ControlTransport).supportsControls(deviceId)) {
        await refreshControls();
      }
      return session == _session;
    } catch (e) {
      if (session == _session) {
        lastFailure = e;
        logBle('Thor BLE read: $e');
        error = e is FormatException
            ? 'Received an incomplete device reading. Tap Refresh to retry.'
            : 'Could not read the Thor. Keep it open, check pairing on both devices, then tap Refresh.';
      }
      return false;
    } finally {
      if (session == _session) {
        reading = false;
        unawaited(refreshActivity());
        _flushRefreshAfterControl();
        _notify();
      }
    }
  }

  void _linkLost(int session, String message) {
    logBle(
      'Thor BLE link ended: session=$session current=$_session phase=$phase message=$message',
    );
    if (_disposed || session != _session) return;
    ++_session;
    phase = CompanionPhase.idle;
    notificationsRequested = false;
    reading = false;
    initializing = false;
    error = message;
    _freshThisConnection = false;
    unawaited(_publishWidget());
    unawaited(_cancelLink());
    _scheduleReconnect();
    _notify();
  }

  Future<void> _cancelLink() async {
    cancelScreenshot();
    _cancelPendingSettings();
    _refreshAfterControl = false;
    _lastRecoveryAttempt = null;
    final live = _liveSubscription;
    final connection = _connectionSubscription;
    _liveSubscription = null;
    _connectionSubscription = null;
    _cleanup = _cleanup.catchError((Object _) {}).then((_) async {
      await live?.cancel();
      await connection?.cancel();
    });
    await _cleanup;
  }

  Future<void> disconnect() async {
    ++_intentEpoch;
    _backgroundPending = _backgroundAttempted = false;
    _wantsConnection = false;
    _cancelRetry();
    unawaited(_saveConnectionIntent());
    ++_session;
    phase = CompanionPhase.idle;
    notificationsRequested = false;
    reading = false;
    initializing = false;
    await stopScan();
    await _cancelLink();
    _freshThisConnection = false;
    unawaited(_publishWidget());
    _notify();
  }

  Future<void> forget() async {
    await adaptive?.forgetNetwork();
    try {
      await fileBridge.invokeMethod('forgetConnection');
    } catch (_) {}

    await disconnect();
    await _publishWidget(clear: true);
    selected = null;
    remembered = null;
    stats = null;
    hardware = null;
    activity = null;
    _activityAttempt = null;
    controls = null;
    controlError = null;
    receivedAt = null;
    heartbeatAt = null;
    heartbeat = null;
    receivedCount = 0;
    error = null;
    if (_rememberDevice) {
      try {
        final store = SharedPreferencesAsync();
        await store.remove('thor_device_id');
        await store.remove('thor_device_name');
      } catch (_) {}
    }
    _notify();
  }

  String _message(Object e, String fallback) =>
      e is StateError ? e.message : fallback;

  @override
  void dispose() {
    adaptive?.removeListener(_notify);
    _disposed = true;
    _cancelRetry();
    ++_session;
    _clock?.cancel();
    _powerRefreshTimer?.cancel();
    _scanTimeout?.cancel();
    unawaited(_radioSubscription?.cancel());
    unawaited(_scanSubscription?.cancel());
    unawaited(_cancelLink().whenComplete(() => adaptive?.dispose()));
    super.dispose();
  }
}
