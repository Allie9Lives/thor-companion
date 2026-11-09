import 'dart:math' as math;
import 'battery_history.dart';
import 'telemetry.dart';

class BatteryRuntime {
  const BatteryRuntime(
    this.label,
    this.detail, {
    this.minimum,
    this.maximum,
    this.window,
    this.drainPerHour,
  });
  final String label, detail;
  final Duration? minimum, maximum, window;
  final double? drainPerHour;
  bool get available => minimum != null && maximum != null;
}

String _runtimeTime(int minutes) => minutes < 60
    ? '$minutes min'
    : minutes % 60 == 0
    ? '${minutes ~/ 60} h'
    : '${minutes ~/ 60} h ${minutes % 60} min';
BatteryRuntime estimateBatteryRuntime(
  List<BatteryPoint> history,
  DeviceStats? current, {
  bool fresh = true,
}) {
  if (current?.battery == null || current?.sourceTimeMs == null) {
    return const BatteryRuntime(
      'Waiting for readings',
      'Connect to the Thor to collect battery readings.',
    );
  }
  if (!fresh) {
    return const BatteryRuntime(
      'Reading is out of date',
      'Reconnect for a runtime estimate based on current battery data.',
    );
  }
  if (current!.pluggedCode == null) {
    return const BatteryRuntime(
      'Power source unknown',
      'Waiting for a confirmed battery-power reading.',
    );
  }
  if (current.pluggedCode != 0) {
    return const BatteryRuntime(
      'External power connected',
      'An estimate will appear after enough unplugged usage is recorded.',
    );
  }
  if (current.battery! <= 0) {
    return const BatteryRuntime('Battery empty', 'Connect the Thor to power.');
  }
  final now = current.sourceTimeMs!;
  final index = <int, BatteryPoint>{
    for (final p in history)
      if (p.timeMs <= now && p.timeMs >= now - 7200000) p.timeMs: p,
  };
  index[now] = BatteryPoint.fromStats(current);
  final sorted = index.values.toList()
    ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final segment = <BatteryPoint>[sorted.last];
  for (var i = sorted.length - 2; i >= 0; i--) {
    final a = sorted[i], b = segment.first;
    final gap = b.timeMs - a.timeMs;
    if (a.plugged || gap <= 0 || gap > 600000 || b.level - a.level > 1) break;
    segment.insert(0, a);
  }
  final span = now - segment.first.timeMs;
  final drop = segment.first.level - current.battery!;
  if (segment.length < 4 || span < 900000 || drop < 2) {
    return const BatteryRuntime(
      'Collecting usage history',
      'Needs at least 15 minutes of continuous unplugged readings and a 2% drop. Recording gaps and charging start a new segment.',
    );
  }
  final overall = drop / (span / 3600000);
  if (!overall.isFinite || overall < .5) {
    return const BatteryRuntime(
      'Drain is too low to estimate',
      'A clearer estimate needs more measured battery use.',
    );
  }
  var recent = overall;
  final recentPoints = segment.where((p) => p.timeMs >= now - 1800000).toList();
  final recentSpan = now - recentPoints.first.timeMs,
      recentDrop = recentPoints.first.level - current.battery!;
  if (recentSpan >= 900000 && recentDrop >= 1) {
    recent = recentDrop / (recentSpan / 3600000);
  }
  if (math.max(overall, recent) / math.min(overall, recent) > 4) {
    return const BatteryRuntime(
      'Usage is changing',
      'Wait for a steadier recent usage pattern.',
    );
  }
  final fast = math.max(overall, recent) * 1.35,
      slow = math.max(.5, math.min(overall, recent) * .75);
  final lowMinutes = math.max(
        1,
        (current.battery! / fast * 60 / 5).floor() * 5,
      ),
      highMinutes = math.max(
        lowMinutes,
        (current.battery! / slow * 60 / 5).ceil() * 5,
      );
  if (lowMinutes > 7 * 24 * 60) {
    return const BatteryRuntime(
      'Drain is too low to estimate',
      'Recent use is too light for a useful prediction.',
    );
  }
  final label = lowMinutes >= 1440
      ? 'Over 24 h'
      : highMinutes <= 5
      ? 'Under 5 min'
      : lowMinutes == highMinutes
      ? 'About ${_runtimeTime(lowMinutes)}'
      : '${_runtimeTime(lowMinutes)} – ${_runtimeTime(highMinutes)}';
  return BatteryRuntime(
    label,
    'At recent usage, based on ${span ~/ 60000} minutes unplugged. Workload, brightness and fan settings can change the result.',
    minimum: Duration(minutes: lowMinutes),
    maximum: Duration(minutes: highMinutes),
    window: Duration(milliseconds: span),
    drainPerHour: overall,
  );
}
