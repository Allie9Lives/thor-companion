import 'dart:async';
import 'package:flutter/foundation.dart';
import 'diagnostics.dart';
import 'connection_lifecycle.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

const thorServiceId = 'a7b31000-8427-4c35-9d6a-9af7b6729e01';
const statsId = 'a7b31001-8427-4c35-9d6a-9af7b6729e01';
const liveId = 'a7b31002-8427-4c35-9d6a-9af7b6729e01';
const controlServiceId = 'a7b32000-8427-4c35-9d6a-9af7b6729e01';
const controlId = 'a7b32001-8427-4c35-9d6a-9af7b6729e01';

const hardwareId = 'a7b31003-8427-4c35-9d6a-9af7b6729e01';

class NearbyThor {
  const NearbyThor(this.id, this.name, this.rssi);
  final String id, name;
  final int rssi;
}

enum RadioState { ready, off, unauthorized, unavailable, starting }

enum LinkState { connecting, connected, disconnected }

class StaleServiceCache extends StateError {
  StaleServiceCache()
    : super(
        'Bluetooth service information is out of date. In iPhone Settings → Bluetooth, forget Thor. Then scan here and pair again.',
      );
}

abstract class BleTransport {
  Stream<RadioState> get radio;
  Future<void> requestAccess();
  Stream<NearbyThor> scan();
  Stream<LinkState> connect(String deviceId, {bool background = false});
  Future<void> discover(String deviceId);
  Future<List<int>> read(String deviceId, String characteristicId);
  Stream<List<int>> subscribe(String deviceId, String characteristicId);
}

abstract class ControlTransport {
  bool supportsControls(String deviceId);
  Future<void> writeControl(String deviceId, List<int> bytes);
}

abstract class SignalTransport {
  Future<int> readSignal(String deviceId);
}

class ReactiveBleTransport
    implements BleTransport, ControlTransport, SignalTransport {
  @override
  Future<int> readSignal(String deviceId) => _ble.readRssi(deviceId);
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final _controlDevices = <String>{};
  bool _resetOnConnect = false;
  final _radio = StreamController<RadioState>.broadcast();
  StreamSubscription<BleStatus>? _statusSubscription;
  void _watchRadio() {
    _statusSubscription ??= _ble.statusStream.listen((status) {
      _radio.add(_radioState(status));
    }, onError: _radio.addError);
  }

  @override
  bool supportsControls(String deviceId) => _controlDevices.contains(deviceId);

  @override
  Stream<RadioState> get radio async* {
    _watchRadio();
    yield _radioState(_ble.status);
    yield* _radio.stream;
  }

  RadioState _radioState(BleStatus status) => switch (status) {
    BleStatus.ready => RadioState.ready,
    BleStatus.poweredOff => RadioState.off,
    BleStatus.unauthorized => RadioState.unauthorized,
    BleStatus.unsupported => RadioState.unavailable,
    BleStatus.locationServicesDisabled => RadioState.unavailable,
    _ => RadioState.starting,
  };

  @override
  Future<void> requestAccess() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final permissions = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (permissions.values.any((p) => !p.isGranted)) {
        throw StateError(
          'Allow Nearby devices access in your phone’s app settings.',
        );
      }
    }
    // CoreBluetooth presents iOS's Bluetooth permission prompt automatically.
  }

  @override
  Stream<NearbyThor> scan() => _ble
      .scanForDevices(
        withServices: [Uuid.parse(thorServiceId)],
        scanMode: ScanMode.lowLatency,
      )
      .map(
        (d) => NearbyThor(d.id, d.name.isEmpty ? 'AYN Thor' : d.name, d.rssi),
      );

  @override
  Stream<LinkState> connect(String deviceId, {bool background = false}) async* {
    if (_resetOnConnect) {
      _resetOnConnect = false;
      logBle('Thor BLE rebuilding native service discovery state');
      await _statusSubscription?.cancel();
      _statusSubscription = null;
      await _ble.deinitialize();
      await _ble.initialize();
      _controlDevices.clear();
      _watchRadio();
    }
    final services = {
      Uuid.parse(thorServiceId): [
        Uuid.parse(statsId),
        Uuid.parse(liveId),
        Uuid.parse(hardwareId),
      ],
      Uuid.parse(controlServiceId): [Uuid.parse(controlId)],
    };
    // A known CoreBluetooth peripheral may already have a system-level link.
    // Requiring another advertisement can reject a perfectly usable iOS link.
    final updates = defaultTargetPlatform == TargetPlatform.iOS
        ? _ble.connectToDevice(
            id: deviceId,
            connectionTimeout: background ? null : const Duration(seconds: 20),
            servicesWithCharacteristicsToDiscover: services,
          )
        : _ble.connectToAdvertisingDevice(
            id: deviceId,
            withServices: [Uuid.parse(thorServiceId)],
            prescanDuration: const Duration(seconds: 5),
            connectionTimeout: const Duration(seconds: 20),
            servicesWithCharacteristicsToDiscover: services,
          );
    yield* settleConnection(
      source: updates,
      lifecycle: _ble.connectedDeviceStream.where(
        (event) => event.deviceId == deviceId,
      ),
      isDisconnected: (event) =>
          event.connectionState == DeviceConnectionState.disconnected,
      onTimeout: () => logBle('Thor BLE disconnect acknowledgement timed out'),
    ).map((event) {
      logBle(
        'Thor BLE link: ${event.connectionState}; failure=${event.failure}',
      );
      if (event.connectionState == DeviceConnectionState.disconnected &&
          event.failure != null) {
        throw StateError('Bluetooth connection failed: ${event.failure}');
      }
      return switch (event.connectionState) {
        DeviceConnectionState.connected => LinkState.connected,
        DeviceConnectionState.disconnected => LinkState.disconnected,
        _ => LinkState.connecting,
      };
    });
  }

  @override
  Future<void> discover(String deviceId) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _ble.requestMtu(deviceId: deviceId, mtu: 185);
    }
    // iOS has already discovered the requested Thor services before emitting
    // connected. Reuse those objects instead of rediscovering every audio
    // service on each refresh. Android still needs explicit discovery.
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      await _ble.discoverAllServices(deviceId);
    }
    var services = await _ble.getDiscoveredServices(deviceId);
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !services.any(
          (s) =>
              s.id == Uuid.parse(thorServiceId) &&
              s.characteristics.any((c) => c.id == Uuid.parse(statsId)),
        )) {
      await _ble.discoverAllServices(deviceId);
      services = await _ble.getDiscoveredServices(deviceId);
    }
    _controlDevices.remove(deviceId);
    if (services.any(
      (s) =>
          s.id == Uuid.parse(controlServiceId) &&
          s.characteristics.any((c) => c.id == Uuid.parse(controlId)),
    )) {
      _controlDevices.add(deviceId);
    }
    for (final service in services) {
      logBle(
        'Thor BLE discovered service ${service.id}: ${service.characteristics.map((c) => c.id).join(", ")}',
      );
    }
    if (!services.any(
      (s) =>
          s.id == Uuid.parse(thorServiceId) &&
          s.characteristics.any((c) => c.id == Uuid.parse(statsId)),
    )) {
      final misplacedStats = services.any(
        (s) =>
            s.id != Uuid.parse(thorServiceId) &&
            s.characteristics.any((c) => c.id == Uuid.parse(statsId)),
      );
      if (misplacedStats && defaultTargetPlatform == TargetPlatform.iOS) {
        _resetOnConnect = true;
        throw StaleServiceCache();
      }
      throw StateError(
        'The Thor’s monitoring service is unavailable. Restart monitoring on the Thor, then reconnect.',
      );
    }
  }

  QualifiedCharacteristic _characteristic(String deviceId, String id) =>
      QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(
          id == controlId ? controlServiceId : thorServiceId,
        ),
        characteristicId: Uuid.parse(id),
      );
  @override
  Future<List<int>> read(String deviceId, String characteristicId) =>
      _ble.readCharacteristic(_characteristic(deviceId, characteristicId));
  @override
  Future<void> writeControl(String deviceId, List<int> bytes) =>
      _ble.writeCharacteristicWithResponse(
        _characteristic(deviceId, controlId),
        value: bytes,
      );

  @override
  Stream<List<int>> subscribe(String deviceId, String characteristicId) => _ble
      .subscribeToCharacteristic(_characteristic(deviceId, characteristicId));
}
