import 'dart:convert';
import 'telemetry.dart';

class BatteryPoint {
  const BatteryPoint(
    this.timeMs,
    this.level,
    this.plugged,
    this.temperature,
    this.voltageMv,
    this.currentUa,
    this.chargeUah,
    this.inputWatts,
    this.screenOn,
  );
  factory BatteryPoint.fromList(List<dynamic> row) {
    if (row.length != 9 ||
        row[0] is! num ||
        row[1] is! num ||
        row[2] is! num ||
        row[8] is! num) {
      throw const FormatException('Invalid battery history sample');
    }
    final t = (row[0] as num).toInt(), p = (row[1] as num).toDouble();
    if (t <= 0 || !p.isFinite || p < 0 || p > 100) {
      throw const FormatException('Invalid battery history sample');
    }
    double? metric(int i, double min, double max) {
      final n = row[i];
      return n is num && n.toDouble().isFinite && n >= min && n <= max
          ? n.toDouble()
          : null;
    }

    return BatteryPoint(
      t,
      p,
      (row[2] as num).toInt() != 0,
      metric(3, -40, 100),
      metric(4, 0, 20000),
      metric(5, -20000000, 20000000),
      metric(6, 0, 20000000),
      metric(7, 0, 480),
      (row[8] as num).toInt() == 1,
    );
  }
  factory BatteryPoint.fromStats(DeviceStats s) => BatteryPoint(
    s.sourceTimeMs!,
    s.battery!,
    (s.pluggedCode ?? 0) != 0,
    s.temperature,
    s.voltageMv?.toDouble(),
    s.currentUa?.toDouble(),
    s.chargeUah?.toDouble(),
    s.inputWatts,
    s.interactive == true,
  );
  final int timeMs;
  final double level;
  final bool plugged, screenOn;
  final double? temperature, voltageMv, currentUa, chargeUah, inputWatts;
  List<Object?> toList() => [
    timeMs,
    level,
    plugged ? 1 : 0,
    temperature,
    voltageMv,
    currentUa,
    chargeUah,
    inputWatts,
    screenOn ? 1 : 0,
  ];
}

class SleepEvent {
  const SleepEvent(this.timeMs, this.code);
  factory SleepEvent.fromList(List<dynamic> row) {
    if (row.length != 2 ||
        row[0] is! int ||
        row[1] is! int ||
        row[0] <= 0 ||
        row[1] < 0 ||
        row[1] > 3) {
      throw const FormatException('Invalid sleep marker');
    }
    return SleepEvent(row[0] as int, row[1] as int);
  }
  final int timeMs, code;
}

class BatteryLedger {
  final points = <BatteryPoint>[];
  final sleepEvents = <SleepEvent>[];
  void mergeSleep(Iterable<SleepEvent> events) {
    final cutoff = DateTime.now()
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch,
        index = {for (final e in sleepEvents) e.timeMs: e};
    for (final e in events) {
      if (e.timeMs >= cutoff &&
          e.timeMs <= DateTime.now().millisecondsSinceEpoch + 60000) {
        index[e.timeMs] = e;
      }
    }
    final sorted = index.values.where((e) => e.timeMs >= cutoff).toList()
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    sleepEvents
      ..clear()
      ..addAll(sorted.skip(sorted.length > 2000 ? sorted.length - 2000 : 0));
  }

  void merge(Iterable<BatteryPoint> samples, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now())
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    final index = {for (final p in points) p.timeMs: p};
    for (final point in samples) {
      if (point.timeMs >= cutoff &&
          point.timeMs <=
              (now ?? DateTime.now()).millisecondsSinceEpoch + 60000) {
        index[point.timeMs] = point;
      }
    }
    final sorted = index.values.where((p) => p.timeMs >= cutoff).toList()
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    points
      ..clear()
      ..addAll(sorted.skip(sorted.length > 10000 ? sorted.length - 10000 : 0));
  }

  bool observe(DeviceStats stats) {
    if (stats.battery == null || stats.sourceTimeMs == null) return false;
    final point = BatteryPoint.fromStats(stats);
    if (points.isNotEmpty) {
      final last = points.last;
      if (point.timeMs <= last.timeMs ||
          (point.timeMs - last.timeMs < 300000 &&
              point.plugged == last.plugged &&
              point.screenOn == last.screenOn)) {
        return false;
      }
    }
    merge([point]);
    return true;
  }

  void load(String encoded) {
    final rows = jsonDecode(encoded);
    if (rows is! List) throw const FormatException('Invalid history');
    merge(rows.take(10000).map((row) => BatteryPoint.fromList(row as List)));
  }

  String encode() => jsonEncode(points.map((p) => p.toList()).toList());
  String encodeSleep() =>
      jsonEncode(sleepEvents.map((e) => [e.timeMs, e.code]).toList());
  void loadSleep(String encoded) {
    final rows = jsonDecode(encoded);
    if (rows is! List || rows.length > 2000) {
      throw const FormatException('Invalid sleep history');
    }
    mergeSleep(rows.map((r) => SleepEvent.fromList(r as List)));
  }

  BatterySummary summary(DateTime start, DateTime end) {
    var drain = 0.0, pluggedMs = 0, screenMs = 0, covered = 0;
    double? peak;
    final hours = <int, double>{};
    for (final p in points) {
      if (p.timeMs >= start.millisecondsSinceEpoch &&
          p.timeMs <= end.millisecondsSinceEpoch &&
          p.temperature != null) {
        peak = peak == null
            ? p.temperature
            : peak > p.temperature!
            ? peak
            : p.temperature;
      }
    }
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final delta = b.timeMs - a.timeMs;
      if (delta <= 0 || delta > 600000) {
        continue; // Do not invent usage across gaps.
      }
      final from = a.timeMs < start.millisecondsSinceEpoch
          ? start.millisecondsSinceEpoch
          : a.timeMs;
      final to = b.timeMs > end.millisecondsSinceEpoch
          ? end.millisecondsSinceEpoch
          : b.timeMs;
      if (to <= from) continue;
      final duration = to - from;
      covered += duration;
      if (a.plugged) pluggedMs += duration;
      if (a.screenOn) screenMs += duration;
      if (!a.plugged && !b.plugged && a.level > b.level) {
        final drop = (a.level - b.level) * (duration / delta);
        drain += drop;
        // Split interval proportionally across local clock-hour boundaries.
        var cursor = from;
        while (cursor < to) {
          final date = DateTime.fromMillisecondsSinceEpoch(cursor);
          final hour =
              cursor -
              (date.minute * 60000 + date.second * 1000 + date.millisecond);
          final next = hour + 3600000;
          final stop = next < to ? next : to;
          hours[hour] = (hours[hour] ?? 0) + drop * (stop - cursor) / duration;
          cursor = stop;
        }
      }
    }
    return BatterySummary(
      drain,
      Duration(milliseconds: pluggedMs),
      Duration(milliseconds: screenMs),
      Duration(milliseconds: covered),
      peak,
      hours,
    );
  }
}

class BatterySummary {
  const BatterySummary(
    this.drain,
    this.charging,
    this.screenOn,
    this.coverage,
    this.peakTemperature,
    this.hourlyDrain,
  );
  final double drain;
  final Duration charging, screenOn, coverage;
  final double? peakTemperature;
  final Map<int, double> hourlyDrain;
}
