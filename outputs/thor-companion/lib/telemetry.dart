import 'dart:convert';

Map<String, dynamic> decodeObject(List<int> bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a device reading');
  }
  return value;
}

double? _number(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;
int? _integer(dynamic value) =>
    value is num && value.isFinite && value == value.roundToDouble()
    ? value.toInt()
    : null;
double? _range(dynamic value, double min, double max) {
  final number = _number(value);
  return number != null && number >= min && number <= max ? number : null;
}

int? _nonnegative(dynamic value) {
  final n = _integer(value);
  return n != null && n >= 0 ? n : null;
}

String? _text(dynamic value) =>
    value is String &&
        value.isNotEmpty &&
        value != 'unavailable' &&
        value != 'unknown'
    ? value
    : null;

double? _usedFraction(int? total, int? available) {
  if (total == null ||
      total <= 0 ||
      available == null ||
      available < 0 ||
      available > total) {
    return null;
  }
  return 1 - available / total;
}

enum SdCardState { mounted, readOnly, notPresent, notMounted, unavailable }

class DeviceStats {
  const DeviceStats({
    this.locatorActive,
    this.keepAlivePaused,
    this.healthCode,
    this.fullChargeUah,
    this.designChargeUah,
    this.cycleCount,
    this.sequence,
    this.sourceTimeMs,
    this.battery,
    this.temperature,
    this.voltageMv,
    this.currentUa,
    this.chargeUah,
    this.statusCode,
    this.pluggedCode,
    this.interactive,
    this.freeBytes,
    this.cpuPercent,
    this.cpuWindowMs,
    this.gpuPercent,
    this.ramAvailableBytes,
    this.sdState,
    this.sdTotalBytes,
    this.sdFreeBytes,
    this.inputWatts,
  });

  final int? healthCode, fullChargeUah, designChargeUah, cycleCount;
  String get healthLabel => switch (healthCode) {
    2 => 'Good',
    3 => 'Overheating',
    4 => 'Battery failure',
    5 => 'Overvoltage',
    6 => 'Fault reported',
    7 => 'Cold',
    _ => 'Not reported',
  };
  factory DeviceStats.fromBytes(List<int> bytes) {
    final j = decodeObject(bytes);
    if (_nonnegative(j['seq']) == null || _nonnegative(j['ts_ms']) == null) {
      throw const FormatException('Missing sample identity or timestamp');
    }
    // The host omits a field or sends null when it cannot supply that reading.
    // Never coerce a missing or malformed value to a convincing zero.
    return DeviceStats(
      keepAlivePaused: j['keep_alive_paused'] is bool
          ? j['keep_alive_paused'] as bool
          : null,
      locatorActive: j['locator_active'] is bool
          ? j['locator_active'] as bool
          : null,
      healthCode: _integer(j['health']),
      fullChargeUah: _nonnegative(j['full_uah']),
      designChargeUah: _nonnegative(j['design_uah']),
      cycleCount: _nonnegative(j['cycles']),
      sequence: _nonnegative(j['seq']),
      sourceTimeMs: _nonnegative(j['ts_ms']),
      battery: _range(j['battery_pct'], 0, 100),
      temperature: _range(j['temp_c'], -50, 150),
      voltageMv: _nonnegative(j['voltage_mv']),
      currentUa: _integer(j['current_ua_raw']),
      chargeUah: _nonnegative(j['charge_uah']),
      statusCode: _integer(j['status_code']),
      pluggedCode: _nonnegative(j['plugged_code']),
      interactive: j['interactive'] is bool ? j['interactive'] as bool : null,
      freeBytes: _nonnegative(j['free_bytes']),
      cpuPercent: _range(j['cpu_pct'], 0, 100),
      cpuWindowMs: _nonnegative(j['cpu_window_ms']),
      gpuPercent: _range(j['gpu_pct'], 0, 100),
      ramAvailableBytes: _nonnegative(j['ram_free_bytes']),
      sdState: switch (j['sd_state']) {
        'mounted' => SdCardState.mounted,
        'read_only' => SdCardState.readOnly,
        'not_present' => SdCardState.notPresent,
        'not_mounted' => SdCardState.notMounted,
        'unavailable' => SdCardState.unavailable,
        _ => null,
      },
      sdTotalBytes: _nonnegative(j['sd_total_bytes']),
      sdFreeBytes: _nonnegative(j['sd_free_bytes']),
      inputWatts: j['plugged_code'] == 0 ? null : _range(j['input_w'], 0, 480),
    );
  }

  final int? sequence,
      sourceTimeMs,
      voltageMv,
      currentUa,
      chargeUah,
      statusCode,
      pluggedCode,
      freeBytes,
      cpuWindowMs,
      ramAvailableBytes,
      sdTotalBytes,
      sdFreeBytes;
  final double? battery, temperature, cpuPercent, gpuPercent, inputWatts;
  final bool? interactive, locatorActive, keepAlivePaused;
  final SdCardState? sdState;
  double? ramUsedFraction(int? total) =>
      _usedFraction(total, ramAvailableBytes);
  double? get sdUsedFraction =>
      sdState == SdCardState.mounted || sdState == SdCardState.readOnly
      ? _usedFraction(sdTotalBytes, sdFreeBytes)
      : null;

  String get chargingLabel => switch (statusCode) {
    2 => 'Charging',
    3 => 'On battery',
    4 => 'Not charging',
    5 => 'Fully charged',
    _ => 'Status unavailable',
  };
  String get powerSource {
    final p = pluggedCode;
    if (p == null) return 'Unknown power source';
    if (p == 0) return 'Unplugged';
    return [
      if ((p & 1) != 0) 'AC',
      if ((p & 2) != 0) 'USB',
      if ((p & 4) != 0) 'Wireless',
    ].join(' + ');
  }
}

class DeviceHardware {
  const DeviceHardware({
    this.model,
    this.deviceName,
    this.variant,
    this.socModel,
    this.storageCapacityBytes,
    this.android,
    this.build,
    this.ramBytes,
    this.dataBytes,
    this.storageModel,
    this.ufsVersion,
    this.cpuName,
    this.gpuName,
  });

  factory DeviceHardware.fromBytes(List<int> bytes) {
    final j = decodeObject(bytes);
    return DeviceHardware(
      model: _text(j['model']),
      deviceName: _text(j['device_name']),
      variant: const {'Lite', 'Base', 'Pro', 'Max'}.contains(j['variant'])
          ? j['variant'] as String
          : null,
      socModel: _text(j['soc_model']),
      storageCapacityBytes: _nonnegative(j['storage_capacity_bytes']),
      android: _text(j['android']),
      build: _text(j['build']),
      ramBytes: _nonnegative(j['ram_total_bytes']),
      dataBytes: _nonnegative(j['data_total_bytes']),
      storageModel: _text(j['storage_model']),
      ufsVersion: _text(j['ufs_version']),
      cpuName: _text(j['cpu_name']),
      gpuName: _text(j['gpu_name']),
    );
  }

  final String? model,
      deviceName,
      variant,
      socModel,
      android,
      build,
      storageModel,
      ufsVersion,
      cpuName,
      gpuName;
  final int? ramBytes, dataBytes, storageCapacityBytes;

  String? get displayModel => variant == null ? model : 'AYN Thor $variant';
  String? get storageConfiguration => switch (storageCapacityBytes) {
    1000000000000 => '1 TB',
    512000000000 => '512 GB',
    256000000000 => '256 GB',
    128000000000 => '128 GB',
    _ => null,
  };

  double? usedFraction(int? freeBytes) {
    return _usedFraction(dataBytes, freeBytes);
  }
}

class Heartbeat {
  const Heartbeat(this.sequence, this.battery);
  factory Heartbeat.fromBytes(List<int> bytes) {
    final text = utf8.decode(bytes);
    final match = RegExp(r'^n=(\d+) b=(\d+)$').firstMatch(text);
    if (match == null) throw const FormatException('Unrecognized live reading');
    final sequence = int.tryParse(match[1]!);
    final battery = int.tryParse(match[2]!);
    if (sequence == null || battery == null || battery > 100) {
      throw const FormatException('Invalid live reading');
    }
    return Heartbeat(sequence, battery);
  }
  final int sequence, battery;
}

String capacity(int? bytes, {int decimals = 0}) {
  if (bytes == null || bytes < 0) return 'Unavailable';
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  double value = bytes.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(i == 0 ? 0 : decimals)} ${units[i]}';
}

String ageLabel(DateTime? receivedAt, DateTime now) {
  if (receivedAt == null) return 'No readings yet';
  final seconds = now.difference(receivedAt).inSeconds.clamp(0, 1 << 31);
  if (seconds < 5) return 'Updated just now';
  if (seconds < 60) return 'Updated ${seconds}s ago';
  if (seconds < 3600) return 'Updated ${seconds ~/ 60}m ago';
  return 'Updated ${seconds ~/ 3600}h ago';
}
