import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/telemetry.dart';

List<int> bytes(Map<String, Object?> data) => utf8.encode(jsonEncode(data));

void main() {
  test(
    'model configuration is optional and does not replace measured storage',
    () {
      final h = DeviceHardware.fromBytes(
        bytes({
          'model': 'AYN_Thor',
          'device_name': 'My custom Thor',
          'variant': 'Max',
          'soc_model': 'QCS8550',
          'storage_capacity_bytes': 1000000000000,
          'data_total_bytes': 1011194642432,
        }),
      );
      expect(h.displayModel, 'AYN Thor Max');
      expect(h.deviceName, 'My custom Thor');
      expect(h.socModel, 'QCS8550');
      expect(h.storageConfiguration, '1 TB');
      expect(h.dataBytes, 1011194642432);
      final legacy = DeviceHardware.fromBytes(bytes({'model': 'AYN Thor'}));
      expect(legacy.displayModel, 'AYN Thor');
      expect(legacy.storageConfiguration, isNull);
      expect(
        DeviceHardware.fromBytes(bytes({'variant': 'Ultra'})).variant,
        isNull,
      );
    },
  );
  test(
    'performance and microSD readings are independent of internal storage',
    () {
      final s = DeviceStats.fromBytes(
        bytes({
          'seq': 1,
          'ts_ms': 1000,
          'cpu_pct': 12.5,
          'cpu_window_ms': 30000,
          'gpu_pct': 87,
          'ram_free_bytes': 6,
          'free_bytes': 75,
          'sd_state': 'mounted',
          'sd_total_bytes': 200,
          'sd_free_bytes': 50,
        }),
      );
      expect(s.cpuPercent, 12.5);
      expect(s.cpuWindowMs, 30000);
      expect(s.gpuPercent, 87);
      expect(s.ramUsedFraction(10), 0.4);
      expect(s.sdUsedFraction, 0.75);
      expect(s.freeBytes, 75);
    },
  );
  test('unsupported or invalid utilization never becomes zero usage', () {
    final s = DeviceStats.fromBytes(
      bytes({
        'seq': 1,
        'ts_ms': 1000,
        'cpu_pct': 101,
        'gpu_pct': -1,
        'ram_free_bytes': 11,
        'sd_state': 'mounted',
        'sd_total_bytes': 100,
        'sd_free_bytes': 101,
      }),
    );
    expect(s.cpuPercent, isNull);
    expect(s.gpuPercent, isNull);
    expect(s.ramUsedFraction(10), isNull);
    expect(s.sdUsedFraction, isNull);
    final old = DeviceStats.fromBytes(bytes({'seq': 1, 'ts_ms': 1000}));
    expect(old.sdState, isNull);
    expect(old.ramAvailableBytes, isNull);
    expect(old.sdUsedFraction, isNull);
  });
  test('card removal and unmount do not display leftover capacities', () {
    for (final state in [
      'not_present',
      'not_mounted',
      'unavailable',
      'unexpected',
    ]) {
      final s = DeviceStats.fromBytes(
        bytes({
          'seq': 1,
          'ts_ms': 1000,
          'sd_state': state,
          'sd_total_bytes': 100,
          'sd_free_bytes': 25,
        }),
      );
      expect(s.sdUsedFraction, isNull);
    }
    final readOnly = DeviceStats.fromBytes(
      bytes({
        'seq': 1,
        'ts_ms': 1000,
        'sd_state': 'read_only',
        'sd_total_bytes': 100,
        'sd_free_bytes': 100,
      }),
    );
    expect(readOnly.sdState, SdCardState.readOnly);
    expect(readOnly.sdUsedFraction, 0);
  });
  test('reads the Thor protocol and preserves raw current sign', () {
    final s = DeviceStats.fromBytes(
      bytes({
        'seq': 24,
        'ts_ms': 1793815386000,
        'battery_pct': 69,
        'temp_c': 30,
        'voltage_mv': 3890,
        'current_ua_raw': -185000,
        'status_code': 3,
        'plugged_code': 0,
        'interactive': false,
      }),
    );
    expect(s.battery, 69);
    expect(s.currentUa, -185000);
    expect(s.interactive, false);
    expect(s.chargingLabel, 'On battery');
    expect(s.powerSource, 'Unplugged');
  });
  test('missing and malformed readings remain unavailable, not zero', () {
    final s = DeviceStats.fromBytes(
      bytes({
        'seq': 2,
        'ts_ms': 1000,
        'battery_pct': 999,
        'temp_c': '30',
        'voltage_mv': -1,
        'interactive': 'false',
      }),
    );
    expect(s.battery, isNull);
    expect(s.temperature, isNull);
    expect(s.voltageMv, isNull);
    expect(s.interactive, isNull);
    expect(s.currentUa, isNull);
  });
  test('malformed packets cannot be marked as fresh samples', () {
    for (final text in ['[]', '{}', 'not json', '{"seq":1}']) {
      expect(
        () => DeviceStats.fromBytes(utf8.encode(text)),
        throwsFormatException,
      );
    }
  });
  test('heartbeat accepts only the expected sequence and battery format', () {
    final h = Heartbeat.fromBytes(utf8.encode('n=35 b=69'));
    expect(h.sequence, 35);
    expect(h.battery, 69);
    for (final value in ['n=-1 b=69', 'n=35 b=101', 'n=35', 'n=3.5 b=69']) {
      expect(
        () => Heartbeat.fromBytes(utf8.encode(value)),
        throwsFormatException,
      );
    }
  });
  test(
    'unknown storage stays unknown and inconsistent capacity has no progress',
    () {
      final h = DeviceHardware.fromBytes(
        bytes({
          'model': 'AYN Thor',
          'ufs_version': 'unknown',
          'storage_model': 'unavailable',
          'data_total_bytes': 100,
        }),
      );
      expect(h.ufsVersion, isNull);
      expect(h.storageModel, isNull);
      expect(h.usedFraction(101), isNull);
      expect(h.usedFraction(null), isNull);
      expect(h.usedFraction(75), 0.25);
    },
  );
  test('freshness uses local reception time and tolerates clock reversal', () {
    final now = DateTime(2026, 11, 4, 13);
    expect(
      ageLabel(now.subtract(const Duration(seconds: 96)), now),
      'Updated 1m ago',
    );
    expect(
      ageLabel(now.add(const Duration(seconds: 10)), now),
      'Updated just now',
    );
    expect(ageLabel(null, now), 'No readings yet');
  });
  test('USB watts are optional, finite and absent while unplugged', () {
    DeviceStats read(dynamic power, int plugged) => DeviceStats.fromBytes(
      utf8.encode(
        jsonEncode({
          'seq': 1,
          'ts_ms': 1,
          'plugged_code': plugged,
          'input_w': power,
        }),
      ),
    );
    expect(read(6.25, 2).inputWatts, 6.25);
    expect(read(6.25, 0).inputWatts, isNull);
    expect(read(-1, 2).inputWatts, isNull);
    expect(read(null, 2).inputWatts, isNull);
  });
}
