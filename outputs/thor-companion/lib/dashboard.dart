import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'telemetry.dart';
import 'ui.dart';
import 'battery_pages.dart';
import 'stats_copy.dart';
import 'runtime_view.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.controller});
  final CompanionController controller;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final accent = p.accent,
        foreground = p.foreground,
        secondaryText = p.secondaryText,
        border = p.border;
    final c = controller, s = c.stats!, h = c.hardware;
    final fraction = h?.usedFraction(s.freeBytes);
    final label = c.isDemo
        ? 'Preview'
        : c.retryAt != null
        ? 'Reconnecting'
        : c.busy
        ? 'Connecting'
        : !c.connected
        ? 'Offline'
        : c.stale
        ? 'Waiting'
        : 'Connected';
    final color = c.isDemo || !c.stale ? accent : p.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h?.deviceName ?? c.selected?.name ?? 'Your Thor',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 4),
                  Text(
                    h?.displayModel ?? 'AYN Thor',
                    style: TextStyle(color: secondaryText, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    c.freshness,
                    style: TextStyle(color: secondaryText, fontSize: 14),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: color.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        batteryPanel(),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BatteryInsightsPage(controller: c),
            ),
          ),
          icon: const Icon(Icons.insights_outlined),
          label: const Text('Battery insights'),
        ),
        SizedBox(height: 12),
        performance(),
        SizedBox(height: 12),
        surface(
          copyText: statsForClipboard(c, StatsSection.internal),
          copyLabel: 'Storage stats',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storage_outlined,
                        size: 20,
                        color: secondaryText,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Internal storage',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  tag(
                    h?.ufsVersion == null
                        ? 'UFS unknown'
                        : 'UFS ${h!.ufsVersion}',
                  ),
                ],
              ),
              SizedBox(height: 18),
              RichText(
                text: TextSpan(
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: foreground),
                  children: [
                    TextSpan(
                      text: capacity(s.freeBytes),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.7,
                      ),
                    ),
                    TextSpan(
                      text: ' free',
                      style: TextStyle(fontSize: 14, color: secondaryText),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction ?? 0,
                  minHeight: 5,
                  backgroundColor: border,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
              SizedBox(height: 8),
              Text(
                h?.dataBytes == null
                    ? 'Total capacity unavailable'
                    : '${capacity(h!.dataBytes)} usable total${fraction == null ? '' : ' · ${(fraction * 100).round()}% used'}',
                style: TextStyle(fontSize: 14, color: secondaryText),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        sdStorage(),
        SizedBox(height: 12),
        surface(
          child: Row(
            children: [
              Icon(
                s.interactive == false
                    ? Icons.bedtime_outlined
                    : Icons.smartphone_outlined,
                color: accent,
                size: 21,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.interactive == false
                          ? 'Screens off'
                          : s.interactive == true
                          ? 'Screens active'
                          : 'Screen state unavailable',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 3),
                    Text(
                      c.connected
                          ? c.keepAlivePaused
                                ? 'CPU keep-alive paused'
                                : 'Connected over ${c.adaptive?.routeLabel ?? 'Bluetooth'}'
                          : 'Disconnected',
                      style: TextStyle(fontSize: 14, color: secondaryText),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh readings',
                onPressed: c.connected && !c.isDemo && !c.reading
                    ? c.refresh
                    : null,
                icon: c.reading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh, size: 21),
              ),
            ],
          ),
        ),
        if (c.stale && !c.isDemo) ...[
          SizedBox(height: 14),
          notice(
            'Out of date',
            'These readings may be old. Check that monitoring is running on your Thor.',
            warning: true,
          ),
        ],
        if (!c.connected && !c.isDemo) ...[
          SizedBox(height: 16),
          FilledButton.icon(
            onPressed: c.busy || c.selected == null
                ? null
                : () => c.connect(c.selected!),
            icon: Icon(Icons.bluetooth_connected),
            label: Text(c.busy ? 'Connecting…' : 'Reconnect to Thor'),
          ),
        ],
      ],
    );
  }

  Widget batteryPanel() => Builder(
    builder: (context) {
      final p = AppPalette.of(context), s = controller.stats!;
      return surface(
        copyText: statsForClipboard(controller, StatsSection.battery),
        copyLabel: 'Battery stats',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final showGauge =
                    box.maxWidth >= 280 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 24;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Battery',
                            style: TextStyle(
                              fontSize: 16,
                              color: p.secondaryText,
                            ),
                          ),
                          Text(
                            s.battery == null ? '—' : '${s.battery!.round()}%',
                            style: TextStyle(
                              fontSize: 46,
                              height: 1.15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -1,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(s.chargingLabel, style: TextStyle(fontSize: 16)),
                          Text(
                            s.powerSource,
                            style: TextStyle(
                              fontSize: 14,
                              color: p.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showGauge) ...[
                      SizedBox(width: 12),
                      SizedBox(
                        width: 112,
                        height: 112,
                        child: CustomPaint(
                          painter: BatteryRing(
                            s.battery,
                            color: p.accent,
                            track: p.border,
                            lowColor: p.warning,
                          ),
                          child: Center(
                            child: Icon(
                              s.statusCode == 2
                                  ? Icons.bolt
                                  : Icons.battery_std,
                              size: 38,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 20),
                    ],
                  ],
                );
              },
            ),
            SizedBox(height: 16),
            Divider(height: 1),
            SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, box) {
                final columns =
                    box.maxWidth < 280 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20
                    ? 2
                    : 3;
                final width = (box.maxWidth - (columns - 1) * 12) / columns;
                Widget value(String label, String reading) => SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 14, color: p.secondaryText),
                      ),
                      SizedBox(height: 4),
                      Text(
                        reading,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    value(
                      'Temperature',
                      s.temperature == null
                          ? '—'
                          : '${s.temperature!.toStringAsFixed(1)}°C',
                    ),
                    value(
                      'Voltage',
                      s.voltageMv == null
                          ? '—'
                          : '${(s.voltageMv! / 1000).toStringAsFixed(2)} V',
                    ),
                    value(
                      'USB input',
                      s.inputWatts == null
                          ? '—'
                          : '${s.inputWatts!.toStringAsFixed(1)} W',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            RuntimeView(
              controller: controller,
              onDetails: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BatteryInsightsPage(controller: controller),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget performance() => Builder(
    builder: (context) {
      final c = controller, s = controller.stats!, h = controller.hardware;
      final ram = s.ramUsedFraction(h?.ramBytes);
      final cpu = s.cpuWindowMs != null && s.cpuWindowMs! >= 1000
          ? s.cpuPercent
          : null;
      return surface(
        copyText: statsForClipboard(controller, StatsSection.performance),
        copyLabel: 'Performance stats',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 18),
            usage(
              'CPU',
              cpu,
              model: h?.cpuName,
              caption: cpu == null
                  ? null
                  : '${(s.cpuWindowMs! / 1000).round()} s average · all cores',
            ),
            SizedBox(height: 18),
            usage('GPU', s.gpuPercent, model: h?.gpuName),
            if (c.activity != null) ...[
              const SizedBox(height: 18),
              const Text(
                'Focused apps',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              for (final a in (c.activity!['apps'] as List? ?? []))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${a['d'] == 0 ? 'Top' : 'Bottom'} · ${a['name'] ?? a['p']}\n${a['cpu'] is num ? '${(a['cpu'] as num).toStringAsFixed(1)}% CPU · all cores' : 'CPU sampling…'}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              if (c.activity!['lid'] is bool)
                Text(
                  c.activity!['lid'] == true
                      ? 'Lid closed · ${(c.activity!['closed_s'] as num? ?? 0).toInt() ~/ 60} min'
                      : 'Lid open',
                  style: const TextStyle(fontSize: 14),
                ),
              const Text(
                'Focused means current or last focused while asleep. GPU readings describe the whole device.',
                style: TextStyle(fontSize: 14),
              ),
            ],
            SizedBox(height: 18),
            usage(
              'RAM',
              ram == null ? null : ram * 100,
              caption: ram == null
                  ? null
                  : '${capacity(h!.ramBytes! - s.ramAvailableBytes!, decimals: 1)} of ${capacity(h.ramBytes, decimals: 1)} used',
            ),
          ],
        ),
      );
    },
  );

  Widget usage(
    String title,
    double? percent, {
    String? caption,
    String? model,
  }) => Builder(
    builder: (context) {
      final p = AppPalette.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16)),
                    if (model != null)
                      Text(
                        model,
                        style: TextStyle(fontSize: 15, color: p.secondaryText),
                      ),
                  ],
                ),
              ),
              Text(
                percent == null ? 'Unavailable' : '${percent.round()}%',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (percent != null) ...[
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 5,
                backgroundColor: p.border,
                valueColor: AlwaysStoppedAnimation(p.metricAccent(title)),
              ),
            ),
          ],
          if (caption != null) ...[
            SizedBox(height: 6),
            Text(
              caption,
              style: TextStyle(fontSize: 14, color: p.secondaryText),
            ),
          ],
        ],
      );
    },
  );

  Widget sdStorage() => Builder(
    builder: (context) {
      final p = AppPalette.of(context), s = controller.stats!;
      final fraction = s.sdUsedFraction;
      final state = switch (s.sdState) {
        SdCardState.notPresent => 'No card detected',
        SdCardState.notMounted => 'Card not mounted',
        _ => 'Storage unavailable',
      };
      return surface(
        copyText: statsForClipboard(controller, StatsSection.sd),
        copyLabel: 'microSD stats',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sd_storage_outlined,
                  size: 18,
                  color: p.secondaryText,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text('microSD card', style: TextStyle(fontSize: 14)),
                ),
                if (s.sdState == SdCardState.readOnly) tag('Read only'),
              ],
            ),
            SizedBox(height: 18),
            if (fraction == null)
              Text(
                state,
                style: TextStyle(fontSize: 14, color: p.secondaryText),
              )
            else ...[
              Text.rich(
                TextSpan(
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: p.foreground),
                  children: [
                    TextSpan(
                      text: capacity(s.sdFreeBytes),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.7,
                      ),
                    ),
                    TextSpan(
                      text: ' free',
                      style: TextStyle(fontSize: 14, color: p.secondaryText),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  backgroundColor: p.border,
                  valueColor: AlwaysStoppedAnimation(p.accent),
                ),
              ),
              SizedBox(height: 8),
              Text(
                '${capacity(s.sdTotalBytes)} usable total · ${(fraction * 100).round()}% used',
                style: TextStyle(fontSize: 14, color: p.secondaryText),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget metric(IconData icon, String label, String value) => Builder(
    builder: (context) {
      final p = AppPalette.of(context);
      return surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: p.secondaryText, size: 17),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(color: p.secondaryText, fontSize: 14),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class DevicePage extends StatelessWidget {
  const DevicePage({super.key, required this.controller});
  final CompanionController controller;
  @override
  Widget build(BuildContext context) {
    final secondaryText = AppPalette.of(context).secondaryText;
    final c = controller, h = c.hardware, s = c.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Device information',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 6),
        Text(
          'Hardware and system details.',
          style: TextStyle(color: secondaryText),
        ),
        SizedBox(height: 24),
        surface(
          copyText: statsForClipboard(c, StatsSection.device),
          copyLabel: 'Device stats',
          child: Column(
            children: [
              detail(
                'Device name',
                h?.deviceName ?? c.selected?.name ?? 'Unavailable',
              ),
              detail('Model', h?.displayModel ?? 'Unavailable'),
              if (h?.variant != null)
                detail(
                  'Model detection',
                  'Processor + RAM',
                  singleLine: true,
                  fullValue: 'Inferred from processor and RAM',
                ),
              if (h?.storageConfiguration != null)
                detail('Storage configuration', h!.storageConfiguration!),
              if (h?.socModel != null) detail('SoC identifier', h!.socModel!),
              detail('Android', h?.android ?? 'Unavailable'),
              detail(
                'CPU',
                h?.cpuName?.replaceFirst('Qualcomm ', '') ?? 'Unavailable',
                singleLine: true,
                fullValue: h?.cpuName,
              ),
              detail('GPU', h?.gpuName ?? 'Unavailable'),
              detail('System RAM', capacity(h?.ramBytes, decimals: 1)),
              detail(
                'Storage standard',
                h?.ufsVersion == null ? 'Unknown' : 'UFS ${h!.ufsVersion}',
              ),
              detail('Storage chip', h?.storageModel ?? 'Unavailable'),
              detail(
                'Usable data capacity',
                capacity(h?.dataBytes, decimals: 1),
                last: true,
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        surface(
          copyText: statsForClipboard(c, StatsSection.firmware),
          copyLabel: 'Firmware',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Firmware',
                style: TextStyle(
                  fontSize: 16,
                  color: secondaryText,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 12),
              Text(
                h?.build ?? 'Unavailable',
                style: TextStyle(fontSize: 16, height: 1.6),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        surface(
          copyText: statsForClipboard(c, StatsSection.diagnostics),
          copyLabel: 'Battery diagnostics',
          child: Column(
            children: [
              detail(
                'Reported current',
                s?.currentUa == null
                    ? 'Unavailable'
                    : '${(s!.currentUa! / 1000).toStringAsFixed(0)} mA',
              ),
              detail(
                'Remaining charge',
                s?.chargeUah == null
                    ? 'Unavailable'
                    : '${(s!.chargeUah! / 1000).toStringAsFixed(0)} mAh',
                last: true,
              ),
              SizedBox(height: 8),
              Text(
                'USB input power is voltage × current reported by the charging hardware. It is not the charger’s rated wattage. Remaining charge is not a battery health measurement.',
                style: TextStyle(color: secondaryText, fontSize: 16),
              ),
            ],
          ),
        ),

        if (!c.isDemo) ...[
          SizedBox(height: 24),
          OutlinedButton(
            onPressed: c.busy
                ? null
                : c.connected
                ? c.disconnect
                : c.selected == null
                ? null
                : () => c.connect(c.selected!),
            child: Text(c.connected ? 'Disconnect' : 'Reconnect'),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: () => confirmForget(context),
            child: Text(
              'Forget this device',
              style: TextStyle(color: secondaryText),
            ),
          ),
        ],
      ],
    );
  }

  Widget detail(
    String title,
    String value, {
    bool last = false,
    bool singleLine = false,
    String? fullValue,
  }) => Builder(
    builder: (context) {
      final p = AppPalette.of(context);
      return Container(
        padding: EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: p.border)),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: box.maxWidth * .44,
                child: Text(
                  title,
                  maxLines: singleLine ? 1 : null,
                  softWrap: !singleLine,
                  overflow: singleLine ? TextOverflow.ellipsis : null,
                  style: TextStyle(fontSize: 16, color: p.secondaryText),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Semantics(
                  label: fullValue ?? value,
                  excludeSemantics: true,
                  child: Text(
                    value,
                    maxLines: singleLine ? 1 : null,
                    softWrap: !singleLine,
                    overflow: singleLine ? TextOverflow.ellipsis : null,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Future<void> confirmForget(BuildContext context) async {
    final forget = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget this Thor?'),
        content: Text(
          'Removes the remembered device from this app. Your phone’s Bluetooth pairing is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Forget'),
          ),
        ],
      ),
    );
    if (forget == true) await controller.forget();
  }
}
