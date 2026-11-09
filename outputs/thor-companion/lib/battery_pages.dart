import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'companion_controller.dart';
import 'battery_history.dart';
import 'ui.dart';
import 'runtime_view.dart';

class BatteryAlertsPage extends StatelessWidget {
  const BatteryAlertsPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller, o = c.batteryAlertOptions;
      Widget option(String title, bool value, void Function(bool) update) =>
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            value: value,
            onChanged: (v) {
              update(v);
              unawaited(c.saveBatteryAlertOptions());
            },
          );
      return Scaffold(
        appBar: AppBar(title: const Text('Battery notifications')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Battery notifications'),
              subtitle: const Text('Notify this phone about your Thor.'),
              value: o.enabled,
              onChanged: c.isDemo ? null : (v) => c.enableBatteryAlerts(v),
            ),
            if (c.batteryAlertError != null)
              notice('Notifications', c.batteryAlertError!, warning: true),
            const SizedBox(height: 16),
            surface(
              child: Column(
                children: [
                  option(
                    'Activity after 10 minutes closed',
                    o.closedLid,
                    (v) => o.closedLid = v,
                  ),
                  const Text(
                    'Warn about sustained measured CPU, device GPU activity or observed battery drain. Per-app GPU and battery attribution are not available.',
                    style: TextStyle(fontSize: 14),
                  ),
                  option('Low battery at 20%', o.low20, (v) => o.low20 = v),
                  option('Low battery at 10%', o.low10, (v) => o.low10 = v),
                  option('Charged to 80%', o.charged80, (v) => o.charged80 = v),
                  option('Connected to power', o.plugged, (v) => o.plugged = v),
                  option(
                    'Disconnected from power',
                    o.unplugged,
                    (v) => o.unplugged = v,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: o.enabled && !c.isDemo ? c.testBatteryAlert : null,
              child: const Text('Send test notification'),
            ),
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('System notification settings'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Alerts need incoming readings from the Thor. They may be delayed while out of Bluetooth range or if iOS suspends the app. Reopen the app after force-quitting it. History sync does not send old notifications.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    },
  );
}

class BatteryInsightsPage extends StatefulWidget {
  const BatteryInsightsPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<BatteryInsightsPage> createState() => _BatteryInsightsPageState();
}

class _BatteryInsightsPageState extends State<BatteryInsightsPage> {
  bool week = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.loadBatteryHistory());
    });
  }

  String duration(Duration d) => '${d.inHours}h ${d.inMinutes % 60}m';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          p = AppPalette.of(context),
          now = DateTime.now(),
          start = now.subtract(Duration(days: week ? 7 : 1));
      final summary = c.batteryLedger.summary(start, now),
          samples = c.batteryLedger.points
              .where(
                (s) =>
                    s.timeMs >= start.millisecondsSinceEpoch &&
                    s.timeMs <= now.millisecondsSinceEpoch,
              )
              .toList(),
          s = c.stats;
      Widget value(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('Battery insights'),
          actions: [
            IconButton(
              tooltip: 'Sync battery history',
              onPressed: c.batteryHistoryBusy || c.controlBusy || c.reading
                  ? null
                  : c.loadBatteryHistory,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            surface(child: RuntimeView(controller: c, details: true)),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Last 24 hours')),
                ButtonSegment(value: true, label: Text('Last 7 days')),
              ],
              selected: {week},
              onSelectionChanged: (v) => setState(() => week = v.single),
            ),
            const SizedBox(height: 16),
            if (c.batteryHistoryBusy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Syncing recorded battery history…'),
              const SizedBox(height: 16),
            ],
            if (c.batteryHistoryError != null) ...[
              notice('History', c.batteryHistoryError!, warning: true),
              const SizedBox(height: 16),
            ],
            surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Battery level',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (samples.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'History appears as Thor Monitor records readings. Connect to your Thor and sync to fill recorded gaps.',
                      ),
                    )
                  else ...[
                    SizedBox(
                      height: 200,
                      child: CustomPaint(
                        painter: _BatteryLevelPainter(
                          samples,
                          start.millisecondsSinceEpoch,
                          now.millisecondsSinceEpoch,
                          p.accent,
                          p.border,
                          p.secondaryText,
                          c.batteryLedger.sleepEvents,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Blue segments show connection to power. Shading marks CPU keep-alive pauses, not proof that Android slept for the entire interval.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Observed battery use',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${summary.drain.toStringAsFixed(1)} percentage points used while unplugged',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: CustomPaint(
                      painter: _BatteryUsePainter(
                        summary.hourlyDrain,
                        start.millisecondsSinceEpoch,
                        now.millisecondsSinceEpoch,
                        p.accent,
                        p.border,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  value('Recorded coverage', duration(summary.coverage)),
                  value('Screen on · sampled', duration(summary.screenOn)),
                  value('Connected to power', duration(summary.charging)),
                  value(
                    'Highest temperature',
                    summary.peakTemperature == null
                        ? 'Not recorded'
                        : '${summary.peakTemperature!.toStringAsFixed(1)} °C',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Current diagnostics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  value('Battery status', s?.healthLabel ?? 'Not reported'),
                  value(
                    'Full charge · controller',
                    s?.fullChargeUah == null
                        ? 'Unavailable'
                        : '${(s!.fullChargeUah! / 1000).round()} mAh',
                  ),
                  value(
                    'Design capacity · controller',
                    s?.designChargeUah == null
                        ? 'Unavailable'
                        : '${(s!.designChargeUah! / 1000).round()} mAh',
                  ),
                  value(
                    'Charge cycles · reported',
                    s?.cycleCount?.toString() ?? 'Unavailable',
                  ),
                  value(
                    'Temperature',
                    s?.temperature == null
                        ? 'Unavailable'
                        : '${s!.temperature!.toStringAsFixed(1)} °C',
                  ),
                  value(
                    'Voltage',
                    s?.voltageMv == null
                        ? 'Unavailable'
                        : '${(s!.voltageMv! / 1000).toStringAsFixed(2)} V',
                  ),
                  value(
                    'Battery current · reported',
                    s?.currentUa == null
                        ? 'Unavailable'
                        : '${(s!.currentUa! / 1000).round()} mA',
                  ),
                  value(
                    'Charge remaining · reported',
                    s?.chargeUah == null
                        ? 'Unavailable'
                        : '${(s!.chargeUah! / 1000).round()} mAh',
                  ),
                  value(
                    'USB input',
                    s?.inputWatts == null
                        ? 'Unavailable'
                        : '${s!.inputWatts!.toStringAsFixed(2)} W',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'History is recorded on the Thor while monitoring is running, including when this phone is disconnected. Gaps are left blank. Usage and screen time are based on recorded samples, not per-app energy measurements. Controller capacity readings are estimates; no maximum-capacity percentage is inferred.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    },
  );
}

class _BatteryLevelPainter extends CustomPainter {
  _BatteryLevelPainter(
    this.points,
    this.start,
    this.end,
    this.color,
    this.grid,
    this.text,
    this.sleepEvents,
  );
  final List<SleepEvent> sleepEvents;
  final List<BatteryPoint> points;
  final int start, end;
  final Color color, grid, text;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      40,
      8,
      math.max(1.0, size.width - 48),
      size.height - 35,
    );
    int? paused;
    void shade(int a, int b) {
      final from = math.max(start, a), to = math.min(end, b);
      if (to > from) {
        canvas.drawRect(
          Rect.fromLTRB(
            rect.left + rect.width * (from - start) / (end - start),
            rect.top,
            rect.left + rect.width * (to - start) / (end - start),
            rect.bottom,
          ),
          Paint()..color = color.withValues(alpha: .12),
        );
      }
    }

    for (final e in sleepEvents) {
      if (e.code == 1) {
        paused = e.timeMs;
      } else if (e.code == 0 && paused != null) {
        shade(paused, e.timeMs);
        paused = null;
      }
    }
    if (paused != null) shade(paused, end);
    void label(String value, Offset at) {
      final p = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: 12, color: text),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, at);
    }

    for (final level in [0, 25, 50, 75, 100]) {
      final y = rect.bottom - level / 100 * rect.height;
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
      label('$level%', Offset(0, y - 7));
    }
    Offset position(BatteryPoint p) => Offset(
      rect.left + (p.timeMs - start) / (end - start) * rect.width,
      rect.bottom - p.level / 100 * rect.height,
    );
    for (var i = 0; i < points.length; i++) {
      final b = points[i], at = position(b);
      canvas.drawCircle(
        at,
        2,
        Paint()..color = (b.plugged ? Colors.blue : color),
      );
      if (i == 0) continue;
      final a = points[i - 1];
      if (b.timeMs - a.timeMs > 600000) continue;
      canvas.drawLine(
        position(a),
        at,
        Paint()
          ..color = (a.plugged ? Colors.blue : color)
          ..strokeWidth = 2.5
          ..isAntiAlias = true,
      );
    }
    for (final fraction in [0.0, 0.5, 1.0]) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        (start + (end - start) * fraction).round(),
      );
      final stamp = end - start > 2 * 86400000
          ? '${t.month}/${t.day}'
          : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      label(
        stamp,
        Offset(rect.left + fraction * (rect.width - 37), rect.bottom + 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryLevelPainter old) => true;
}

class _BatteryUsePainter extends CustomPainter {
  _BatteryUsePainter(this.hours, this.start, this.end, this.color, this.grid);
  final Map<int, double> hours;
  final int start, end;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()..color = grid,
    );
    final maxValue = hours.values.fold<double>(5, (a, b) => math.max(a, b));
    final width = math.max(1.0, size.width * 3600000 / (end - start) - 1);
    for (final entry in hours.entries) {
      final x = (entry.key - start) / (end - start) * size.width;
      if (x + width < 0 || x > size.width) continue;
      final height = entry.value / maxValue * (size.height - 8);
      canvas.drawRect(
        Rect.fromLTWH(math.max(0.0, x), size.height - height, width, height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryUsePainter old) => true;
}
