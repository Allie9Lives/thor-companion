import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble_transport.dart';
import 'file_transfer.dart';
import 'adaptive_network.dart';
import 'link_policy.dart';
import 'diagnostics.dart';
import 'network_endpoint.dart';

/// One logical Thor session, with a retained BLE link and a verified network path.
/// Explicit cancellation ends both paths. Network polling is foreground-only.
class AdaptiveTransport extends ChangeNotifier
    implements BleTransport, ControlTransport {
  AdaptiveTransport(
    this.ble, {
    this.persist = true,
    this.interval = const Duration(seconds: 5),
    ControlNetwork Function(FileConnection, String)? networkFactory,
    this.savedConnection,
  }) : networkFactory = networkFactory ?? PinnedControlNetwork.new {
    _radioSub = ble.radio.listen((s) {
      _actualRadio = s;
      _emitRadio();
    });
    if (persist) unawaited(_loadPreference());
  }
  final BleTransport ble;
  final bool persist;
  final Duration interval;
  final ControlNetwork Function(FileConnection, String) networkFactory;

  /// Replaces the persisted Wi-Fi/VPN credentials lookup (tests).
  final Future<FileConnection?> Function(String id)? savedConnection;
  LinkPolicy policy = LinkPolicy();
  bool automatic = true, foreground = true, bleConnected = false;
  bool sleeping = false;
  Timer? _restTimer;
  DateTime? _restAt;
  void setSleeping(bool value, {DateTime? resumeAt}) {
    final changed = sleeping != value;
    sleeping = value;
    if (!value) {
      _restTimer?.cancel();
      _restTimer = null;
      _restAt = null;
      if (changed) unawaited(_tick());
    } else if (resumeAt != null && resumeAt != _restAt) {
      _restAt = resumeAt;
      _restTimer?.cancel();
      final delay =
          resumeAt.difference(DateTime.now()) + const Duration(seconds: 10);
      _restTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
        setSleeping(false);
      });
    }
    if (changed) _changed();
  }

  bool _disposed = false,
      _logical = false,
      _tickBusy = false,
      _discovered = false;
  int _epoch = 0;
  bool _initialReadingReady = false, _firstStatsRead = false;
  DateTime? _networkSearchAt;
  String? _device;
  FileConnection? _credentials;
  List<String> get knownNetworkHosts =>
      List.unmodifiable(_credentials?.candidateHosts ?? const <String>[]);
  Future<void>? _networkSearch;
  ControlNetwork? _network;
  String? networkHost;
  DateTime? _bootstrapAt;
  String networkStatus = 'Linking network access when available';
  String? lastBluetoothError;
  DateTime? lastBluetoothErrorAt;
  void _recordBluetoothError(String stage, Object error) {
    lastBluetoothError = redactConnectionDiagnostic('$stage: $error');
    lastBluetoothErrorAt = DateTime.now();
    logBle('Thor BLE $lastBluetoothError');
  }

  List<int>? _reply;
  StreamController<LinkState>? _connection;
  final _live = StreamController<List<int>>.broadcast();
  final _radios = StreamController<RadioState>.broadcast();
  RadioState _actualRadio = RadioState.starting;
  StreamSubscription<RadioState>? _radioSub;
  StreamSubscription<LinkState>? _bleSub;
  StreamSubscription<List<int>>? _bleLive;
  Timer? _timer, _retry;
  Future<void> _bleTail = Future.value();
  bool _bleBusy = false;
  bool _serviceRecoveryAttempted = false, _serviceRecoveryBlocked = false;
  bool get networkReady =>
      automatic &&
      foreground &&
      _network != null &&
      policy.ready(DateTime.now());
  ControlRoute get route =>
      policy.choose(DateTime.now(), bleAvailable: bleConnected);
  String get routeLabel =>
      route == ControlRoute.network ? 'Wi-Fi / VPN' : 'Bluetooth';
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _emitRadio() {
    if (!_disposed) _radios.add(networkReady ? RadioState.ready : _actualRadio);
  }

  RadioState get bluetoothRadio => _actualRadio;
  @override
  Stream<RadioState> get radio async* {
    yield networkReady ? RadioState.ready : _actualRadio;
    yield* _radios.stream;
  }

  @override
  Future<void> requestAccess() => ble.requestAccess();
  @override
  Stream<NearbyThor> scan() => ble.scan();
  @override
  bool supportsControls(String id) =>
      id == _device &&
      (networkReady ||
          (ble is ControlTransport &&
              (ble as ControlTransport).supportsControls(id)));
  Future<void> _loadPreference() async {
    try {
      automatic =
          await SharedPreferencesAsync().getBool('adaptive_connection') ?? true;
      _changed();
    } catch (_) {}
  }

  Future<void> setAutomatic(bool value) async {
    automatic = value;
    if (!value) {
      _dropNetwork('Automatic network switching is off');
      if (!bleConnected) _lost();
    } else {
      unawaited(_tick());
    }
    if (persist) {
      await SharedPreferencesAsync().setBool('adaptive_connection', value);
    }
    _changed();
  }

  void setForeground(bool value) {
    foreground = value;
    if (value &&
        sleeping &&
        _restAt != null &&
        !DateTime.now().isBefore(_restAt!)) {
      setSleeping(false);
    }
    if (!value) {
      // Network polling is foreground-only. A Wi-Fi session stays logically
      // connected; the next foreground tick re-verifies it or reports the loss.
      _dropNetwork('Bluetooth handles background monitoring');
    } else {
      unawaited(_tick());
    }
    _changed();
  }

  Future<T> _bleOperation<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    final epoch = _epoch;
    _bleTail = _bleTail.then((_) async {
      if (epoch != _epoch || _disposed) {
        result.completeError(StateError('Connection changed'));
        return;
      }
      _bleBusy = true;
      try {
        result.complete(await operation());
      } catch (e, st) {
        result.completeError(e, st);
      } finally {
        _bleBusy = false;
      }
    });
    return result.future;
  }

  @override
  Stream<LinkState> connect(String id, {bool background = false}) {
    late StreamController<LinkState> output;
    var cancelled = false;
    output = StreamController<LinkState>(
      onListen: () {
        unawaited(_start(id, output, background, () => cancelled));
      },
      onCancel: () async {
        cancelled = true;
        if (identical(_connection, output)) await _stop();
      },
    );
    return output.stream;
  }

  Future<void> _start(
    String id,
    StreamController<LinkState> output,
    bool background,
    bool Function() cancelled,
  ) async {
    await _stop();
    if (_disposed || cancelled()) return;
    final epoch = ++_epoch;
    _device = id;
    _connection = output;
    policy = LinkPolicy();
    _logical = false;
    // Credentials first: a Bluetooth failure (radio off, Thor away) must find
    // the saved Wi-Fi/VPN path before it can end the session.
    final saved = await _saved(id);
    if (epoch != _epoch) return;
    _credentials = saved ?? _credentials;
    _openBle(epoch, background);
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  Future<FileConnection?> _saved(String id) async {
    if (savedConnection != null) return savedConnection!(id);
    if (!persist) return null;
    try {
      final marker = await SharedPreferencesAsync().getString('adaptive_owner');
      final saved = await fileBridge.invokeMapMethod<String, dynamic>(
        'loadConnection',
      );
      if (marker == null || saved == null) return null;
      final m = jsonDecode(marker) as Map;
      final c = FileConnection.fromMap(saved);
      return m['id'] == id && m['pin'] == c.pin ? c : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether this Thor has a saved Wi-Fi/VPN path, so Bluetooth is optional.
  Future<bool> hasSavedNetwork(String id) async =>
      automatic && (await _saved(id))?.candidateHosts.isNotEmpty == true;

  void _connected() {
    if (!_logical) {
      _logical = true;
      _connection?.add(LinkState.connected);
    }
    _emitRadio();
    _changed();
  }

  void _lost() {
    if (_logical) {
      _logical = false;
      _connection?.add(LinkState.disconnected);
    } else {
      _connection?.add(LinkState.disconnected);
    }
    _changed();
  }

  void _openBle(int epoch, bool background) {
    if (epoch != _epoch || _disposed) return;
    _bleSub = ble
        .connect(_device!, background: background)
        .listen(
          (event) {
            if (epoch != _epoch) return;
            if (event == LinkState.connected) {
              bleConnected = true;
              _retry?.cancel();
              _changed();
              if (!_logical) {
                _connected();
              } else {
                unawaited(
                  discover(_device!).catchError((Object _) {
                    if (epoch == _epoch) _bleDown(epoch);
                  }),
                );
              }
            } else if (event == LinkState.disconnected) {
              _bleDown(epoch);
            } else if (!_logical) {
              _connection?.add(LinkState.connecting);
            }
          },
          onError: (Object error) {
            if (epoch != _epoch) return;
            _recordBluetoothError('connection', error);
            if (error is StaleServiceCache ||
                error.toString().toLowerCase().contains(
                  'peer removed pairing information',
                )) {
              _serviceRecoveryBlocked = true;
              bleConnected = false;
              _discovered = false;
              // In the background network polling pauses, so a session already
              // on a saved Wi-Fi/VPN path stays up; the next foreground tick
              // re-verifies it instead of ending it with a re-pair error.
              if (networkReady ||
                  (!foreground && _logical && _credentials != null)) {
                networkStatus =
                    'Network connected · Bluetooth needs re-pairing';
                _connected();
              } else {
                _connection?.addError(StaleServiceCache());
              }
              _changed();
            } else {
              _bleDown(epoch);
            }
          },
          onDone: () {
            if (epoch == _epoch) _bleDown(epoch);
          },
        );
  }

  void _bleDown(int epoch) {
    bleConnected = false;
    _discovered = false;
    // A re-attached link may need fresh encryption before its first read.
    _firstStatsRead = false;
    unawaited(_bleLive?.cancel());
    _bleLive = null;
    policy.bluetooth(failed: true);
    if (sleeping && _network != null) {
      _connected();
      return;
    }
    if (networkReady) {
      policy.choose(DateTime.now(), bleAvailable: false);
      _connected();
      _scheduleBle(epoch);
    } else {
      unawaited(_tryBeforeLoss(epoch));
    }
    _changed();
  }

  Future<void> _tryBeforeLoss(int epoch) async {
    if (_tickBusy) {
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (_tickBusy && epoch == _epoch && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } else {
      await _tick();
    }
    if (epoch != _epoch || bleConnected) return;
    if (networkReady) {
      _connected();
      _scheduleBle(epoch);
    } else if (!foreground && _logical && _credentials != null) {
      // Wi-Fi/VPN session in background: the next foreground tick decides.
    } else {
      _lost();
    }
  }

  void _scheduleBle(int epoch) {
    if (sleeping || _serviceRecoveryBlocked) return;
    if (_retry?.isActive ?? false) return;
    _retry = Timer(const Duration(seconds: 5), () async {
      await _bleSub?.cancel();
      _bleSub = null;
      if (epoch == _epoch && _logical && !bleConnected) _openBle(epoch, false);
    });
  }

  @override
  Future<void> discover(String id) async {
    if (id != _device) throw StateError('Connection changed');
    if (bleConnected) {
      try {
        await _bleOperation(
          () => ble.discover(id).timeout(const Duration(seconds: 12)),
        );
        _serviceRecoveryAttempted = _serviceRecoveryBlocked = false;
      } on StaleServiceCache catch (error) {
        _recordBluetoothError('service discovery', error);
        // A broken Bluetooth cache must not take down a verified Wi-Fi path.
        if (!networkReady) rethrow;
        logBle('Thor BLE cache stale; preserving verified network connection');
        _serviceRecoveryBlocked = _serviceRecoveryAttempted;
        _serviceRecoveryAttempted = true;
        _bleDown(_epoch);
        return;
      } catch (error) {
        _recordBluetoothError('service discovery', error);
        rethrow;
      }
      _discovered = true;
      await _attachLive();
    } else if (!networkReady) {
      throw StateError('No reachable device connection');
    }
  }

  Future<void> _attachLive() async {
    if (!_discovered || !bleConnected || _bleLive != null) return;
    final epoch = _epoch;
    _bleLive = ble
        .subscribe(_device!, liveId)
        .listen(
          (bytes) {
            if (epoch == _epoch && !_disposed) _live.add(bytes);
          },
          onError: (Object e) {
            if (epoch == _epoch) _recordBluetoothError('live subscription', e);
            if (epoch == _epoch && !networkReady) _live.addError(e);
          },
          onDone: () {
            if (epoch == _epoch) _bleLive = null;
          },
        );
  }

  @override
  Stream<List<int>> subscribe(String id, String characteristic) {
    if (id != _device || characteristic != liveId) {
      return ble.subscribe(id, characteristic);
    }
    unawaited(_attachLive());
    return _live.stream;
  }

  Future<void> _bootstrap() async {
    if (!automatic ||
        !foreground ||
        !bleConnected ||
        ble is! ControlTransport ||
        !(ble as ControlTransport).supportsControls(_device!)) {
      return;
    }
    _bootstrapAt = DateTime.now();
    final epoch = _epoch;
    try {
      final reply = await _bleOperation(() async {
        final id =
            '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_net';
        await (ble as ControlTransport)
            .writeControl(
              _device!,
              utf8.encode(
                jsonEncode({'id': id, 'set': 'network_session', 'value': 1}),
              ),
            )
            .timeout(const Duration(seconds: 2));
        final j =
            jsonDecode(
                  utf8.decode(
                    await ble
                        .read(_device!, controlId)
                        .timeout(const Duration(seconds: 2)),
                  ),
                )
                as Map<String, dynamic>;
        if (j['ack'] != id || j['error'] != '') {
          throw StateError('Network access not enabled on host');
        }
        return FileConnection.fromMap(j);
      });
      if (epoch != _epoch) return;
      // Preserve a user-selected VPN/hostname only for this same pinned Thor.
      final prior = _credentials;
      _credentials = prior?.pin == reply.pin
          ? reply.withManualHost(prior?.manualHost).retainingAddresses(prior)
          : reply;
      if (persist) {
        await fileBridge.invokeMethod('saveConnection', _credentials!.toMap());
        await SharedPreferencesAsync().setString(
          'adaptive_owner',
          jsonEncode({'id': _device, 'pin': reply.pin}),
        );
      }
    } catch (_) {
      if (_credentials == null) {
        networkStatus = 'Enable Wi-Fi access in the device’s Host settings';
      }
    }
  }

  /// Called after a deliberate Files/network link, preserving device association.
  Future<void> configure(FileConnection connection) async {
    if (_credentials?.token != connection.token ||
        _credentials?.pin != connection.pin ||
        _credentials?.manualHost != connection.manualHost) {
      _dropNetwork('Checking network addresses');
      _networkSearchAt = null;
    }
    _credentials = connection.retainingAddresses(_credentials);
    if (persist && _device != null) {
      await fileBridge.invokeMethod('saveConnection', _credentials!.toMap());
      await SharedPreferencesAsync().setString(
        'adaptive_owner',
        jsonEncode({'id': _device, 'pin': connection.pin}),
      );
    }
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_tickBusy ||
        sleeping ||
        _device == null ||
        _disposed ||
        !foreground ||
        !automatic) {
      return;
    }
    _tickBusy = true;
    final epoch = _epoch;
    try {
      if (_initialReadingReady && bleConnected && _discovered && !_bleBusy) {
        try {
          final watch = Stopwatch()..start();
          final signal = await _bleOperation(() async {
            int? value;
            if (ble is SignalTransport) {
              try {
                final signal = await (ble as SignalTransport)
                    .readSignal(_device!)
                    .timeout(const Duration(seconds: 1));
                if (signal < 0 && signal > -127) value = signal;
              } catch (_) {
                /* RSSI is advisory; an unavailable signal reading is not a link failure. */
              }
            }
            await ble
                .read(_device!, liveId)
                .timeout(const Duration(seconds: 2));
            return value;
          });
          if (epoch != _epoch) return;
          policy.bluetooth(elapsed: watch.elapsed, signal: signal);
        } catch (_) {
          if (epoch == _epoch) policy.bluetooth(failed: true);
        }
      }
      if (epoch != _epoch) return;
      if (_initialReadingReady &&
          bleConnected &&
          _discovered &&
          !_bleBusy &&
          (_bootstrapAt == null ||
              DateTime.now().difference(_bootstrapAt!) >=
                  const Duration(seconds: 30))) {
        await _bootstrap();
      }
      if (epoch != _epoch) return;
      if (_credentials == null) return;
      if (_network != null) {
        try {
          final watch = Stopwatch()..start();
          await _network!.probe();
          if (epoch != _epoch) return;
          policy.network(watch.elapsed, DateTime.now());
        } catch (_) {
          if (epoch == _epoch) {
            _dropNetwork('Network unreachable · checking alternate address');
            await _findNetwork(epoch);
          }
        }
      } else {
        await _findNetwork(epoch);
      }
      // A VPN may become available after a local connection. Verify it before
      // replacing the working route; do not flap between local addresses.
      if (_network != null &&
          _credentials?.manualHost == null &&
          networkHost != null &&
          !isVpnAddress(networkHost!) &&
          _credentials!.hosts.any(isVpnAddress) &&
          (_networkSearchAt == null ||
              DateTime.now().difference(_networkSearchAt!) >=
                  const Duration(seconds: 30))) {
        await _findNetwork(epoch);
      }
      if (epoch != _epoch) return;
      policy.choose(DateTime.now(), bleAvailable: bleConnected);
      if (networkReady && !bleConnected) {
        _connected();
        _scheduleBle(epoch);
      }
      if (route == ControlRoute.network && networkReady) {
        try {
          final bytes = await _network!.read('live');
          if (epoch == _epoch) _live.add(bytes);
        } catch (_) {
          if (epoch == _epoch) {
            _dropNetwork('Network interrupted · using Bluetooth');
            if (!bleConnected && foreground) _lost();
          }
        }
      }
      // A tick that straddles going to background must not report a loss.
      if (_logical &&
          !bleConnected &&
          !networkReady &&
          !sleeping &&
          foreground) {
        _lost();
      }
      _emitRadio();
      _changed();
    } finally {
      _tickBusy = false;
    }
  }

  Future<void> _findNetwork(int epoch) {
    if (_networkSearch != null) return _networkSearch!;
    late Future<void> task;
    task = _selectNetwork(epoch).whenComplete(() {
      if (identical(_networkSearch, task)) _networkSearch = null;
    });
    _networkSearch = task;
    return task;
  }

  Future<bool> _restoreNetwork(int epoch) async {
    if (_credentials == null ||
        sleeping ||
        !foreground ||
        !automatic ||
        epoch != _epoch) {
      return false;
    }
    await _findNetwork(epoch);
    return epoch == _epoch && networkReady;
  }

  Future<void> _selectNetwork(int epoch) async {
    final c = _credentials!;
    _networkSearchAt = DateTime.now();
    final clients = <ControlNetwork>[];
    try {
      final winner = await selectNetworkEndpoint<ControlNetwork>(
        c,
        cancelled: () =>
            epoch != _epoch ||
            !identical(_credentials, c) ||
            !foreground ||
            !automatic ||
            _disposed,
        probe: (host) async {
          final n = networkFactory(c, host);
          clients.add(n);
          try {
            await n.probe().timeout(const Duration(milliseconds: 2400));
            return n;
          } catch (_) {
            n.close();
            rethrow;
          }
        },
        close: (n) => n.close(),
      );
      final old = _network;
      if (old != null &&
          networkHost != null &&
          !isVpnAddress(winner.host) &&
          c.manualHost == null) {
        winner.value.close();
        return;
      }
      _network = winner.value;
      networkHost = winner.host;
      old?.close();
      policy.network(winner.elapsed, DateTime.now());
      final bluetooth = _serviceRecoveryBlocked
          ? 'Bluetooth needs re-pairing'
          : 'Bluetooth retained';
      networkStatus = isVpnAddress(winner.host)
          ? 'VPN connected · $bluetooth'
          : 'Local network connected · $bluetooth';
    } catch (_) {
      if (_network == null && epoch == _epoch) {
        networkStatus = 'Network unavailable · Bluetooth retained';
      }
    } finally {
      for (final n in clients) {
        if (!identical(n, _network)) n.close();
      }
    }
  }

  /// One stats read over the saved Wi-Fi/VPN path while the app is in the
  /// background, for alerts away from Bluetooth. Null when nothing answers.
  Future<List<int>?> backgroundRead(String characteristic) async {
    final c = _credentials;
    if (c == null || !automatic || sleeping || _disposed || foreground) {
      return null;
    }
    final epoch = _epoch;
    ControlNetwork? n;
    try {
      n = (await selectNetworkEndpoint<ControlNetwork>(
        c,
        cancelled: () => epoch != _epoch || _disposed || foreground,
        probe: (host) async {
          final client = networkFactory(c, host);
          try {
            await client.probe().timeout(const Duration(milliseconds: 2400));
            return client;
          } catch (_) {
            client.close();
            rethrow;
          }
        },
        close: (client) => client.close(),
      )).value;
      return await n
          .read(_kind(characteristic))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    } finally {
      n?.close();
    }
  }

  void _dropNetwork(String reason) {
    _network?.close();
    _network = null;
    networkHost = null;
    policy.networkFailed();
    policy.choose(DateTime.now(), bleAvailable: bleConnected);
    networkStatus = reason;
    _emitRadio();
  }

  String _kind(String id) => id == statsId
      ? 'stats'
      : id == hardwareId
      ? 'hardware'
      : id == liveId
      ? 'live'
      : id == controlId
      ? 'control'
      : throw ArgumentError('Unsupported device reading');
  Future<List<int>> _bleRead(String id) async {
    if (!bleConnected) throw StateError('Bluetooth is unavailable');
    final watch = Stopwatch()..start();
    final timeout = id == statsId && !_firstStatsRead
        ? const Duration(seconds: 45)
        : const Duration(seconds: 2);
    try {
      final bytes = await _bleOperation(() async {
        try {
          return await ble.read(_device!, id).timeout(timeout);
        } catch (error) {
          if (!error.toString().contains(
            'Characteristic not found or discovered',
          )) {
            rethrow;
          }
          // CoreBluetooth can invalidate its characteristic objects while
          // backgrounded without ending the physical connection.
          logBle(
            'Thor BLE restoring characteristic lookup before retrying read',
          );
          await ble.discover(_device!).timeout(const Duration(seconds: 12));
          _discovered = true;
          await _bleLive?.cancel();
          _bleLive = null;
          await _attachLive();
          return ble.read(_device!, id).timeout(timeout);
        }
      });
      if (id == statsId) _firstStatsRead = true;
      policy.bluetooth(elapsed: watch.elapsed);
      if (id == controlId && !_initialReadingReady) {
        _initialReadingReady = true;
        unawaited(_tick());
      } else if (id == statsId && !_initialReadingReady) {
        final epoch = _epoch;
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (epoch == _epoch && !_initialReadingReady) {
            _initialReadingReady = true;
            unawaited(_tick());
          }
        });
      }
      return bytes;
    } catch (error) {
      _recordBluetoothError('read ${_kind(id)}', error);
      policy.bluetooth(failed: true);
      rethrow;
    }
  }

  @override
  Future<List<int>> read(String device, String characteristic) async {
    if (device != _device) throw StateError('Connection changed');
    if (characteristic == controlId && _reply != null) {
      final bytes = _reply!;
      _reply = null;
      return bytes;
    }
    final epoch = _epoch;
    if (route == ControlRoute.network && networkReady) {
      try {
        return await (characteristic == controlId
            ? _bleOperation(() => _network!.read('control'))
            : _network!.read(_kind(characteristic)));
      } catch (_) {
        if (epoch != _epoch) rethrow;
        _dropNetwork('Network interrupted · using Bluetooth');
      }
    }
    try {
      return await _bleRead(characteristic);
    } catch (_) {
      if (epoch != _epoch) rethrow;
      if (!networkReady) await _restoreNetwork(epoch);
      if (epoch == _epoch && networkReady) {
        return characteristic == controlId
            ? _bleOperation(() => _network!.read('control'))
            : _network!.read(_kind(characteristic));
      }
      rethrow;
    }
  }

  Future<List<int>> _bleCommand(List<int> bytes) => _bleOperation(() async {
    if (!bleConnected) throw StateError('Bluetooth is unavailable');
    await (ble as ControlTransport)
        .writeControl(_device!, bytes)
        .timeout(const Duration(seconds: 2));
    return ble.read(_device!, controlId).timeout(const Duration(seconds: 2));
  });
  @override
  Future<void> writeControl(String device, List<int> bytes) async {
    if (device != _device || bytes.length > 180) {
      throw StateError('Invalid device command');
    }
    final epoch = _epoch;
    if (sleeping) {
      sleeping = false;
      await _tick();
    }
    final useNetwork = route == ControlRoute.network && networkReady;
    _reply = null;
    try {
      _reply = await (useNetwork
          ? _bleOperation(() => _network!.command(bytes))
          : _bleCommand(bytes));
    } catch (_) {
      if (epoch != _epoch) rethrow;
      if (useNetwork) {
        _dropNetwork('Network interrupted · using Bluetooth');
        if (bleConnected) {
          _reply = await _bleCommand(bytes);
        } else if (await _restoreNetwork(epoch)) {
          _reply = await _bleOperation(() => _network!.command(bytes));
        } else {
          rethrow;
        }
      } else {
        policy.bluetooth(failed: true);
        if (!networkReady) await _restoreNetwork(epoch);
        if (epoch != _epoch || !networkReady) rethrow;
        _reply = await _bleOperation(() => _network!.command(bytes));
      }
    }
    if (epoch != _epoch) {
      _reply = null;
      throw StateError('Connection changed');
    }
    _changed();
  }

  Future<void> writeBluetoothControl(String device, List<int> bytes) async {
    if (device != _device || bytes.length > 180 || !bleConnected) {
      throw StateError('Keep this phone in Bluetooth range to change Wi-Fi.');
    }
    final epoch = _epoch;
    _reply = null;
    final reply = await _bleCommand(bytes);
    if (epoch != _epoch) throw StateError('Connection changed');
    _reply = reply;
  }

  /// After the active credential slot changes hands, point the owner marker at [id].
  Future<void> claimSaved(String id) async {
    if (!persist) return;
    final saved = await fileBridge.invokeMapMethod<String, dynamic>(
      'loadConnection',
    );
    final store = SharedPreferencesAsync();
    if (saved == null) {
      await store.remove('adaptive_owner');
    } else {
      await store.setString(
        'adaptive_owner',
        jsonEncode({'id': id, 'pin': FileConnection.fromMap(saved).pin}),
      );
    }
  }

  Future<void> forgetNetwork() async {
    _credentials = null;
    _dropNetwork('Network link forgotten');
    if (persist) await SharedPreferencesAsync().remove('adaptive_owner');
  }

  Future<void> _stop() async {
    ++_epoch;
    _timer?.cancel();
    _restTimer?.cancel();
    _restTimer = null;
    _restAt = null;
    _retry?.cancel();
    _timer = _retry = null;
    _connection = null;
    _device = null;
    sleeping = false;
    _logical = false;
    bleConnected = false;
    _discovered = false;
    _reply = null;
    _credentials = null;
    _networkSearch = null;
    _bootstrapAt = null;
    _initialReadingReady = _firstStatsRead = false;
    _networkSearchAt = null;
    _serviceRecoveryAttempted = _serviceRecoveryBlocked = false;
    _dropNetwork('Disconnected');
    await _bleLive?.cancel();
    _bleLive = null;
    await _bleSub?.cancel();
    _bleSub = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_stop());
    unawaited(_radioSub?.cancel());
    unawaited(_live.close());
    unawaited(_radios.close());
    super.dispose();
  }
}
