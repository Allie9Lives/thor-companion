import 'focused_apps.dart';
import 'apps_page.dart';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'telemetry.dart';
import 'ui.dart';
import 'design_components.dart';
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
        Text(
          h?.deviceName ?? c.selected?.name ?? 'Your Thor',
          style: const TextStyle(
            fontSize: 28,
            height: 1.12,
            fontWeight: FontWeight.w600,
            letterSpacing: -.65,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                h?.displayModel ?? 'AYN Thor',
                style: TextStyle(color: secondaryText, fontSize: 16),
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
        const SizedBox(height: 6),
        Text(c.freshness, style: TextStyle(color: secondaryText, fontSize: 14)),
        SizedBox(height: 20),
        batteryPanel(),
        SizedBox(height: 16),
        performance(),
        if (c.activity != null) ...[
          const SizedBox(height: 12),
          focusedAppsCard(),
        ],
        SizedBox(height: 12),
        surface(
          copyText: statsForClipboard(c, StatsSection.internal),
          copyLabel: 'Storage stats',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'Internal storage',
                Icons.storage_outlined,
                trailing: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: tag(
                    h?.ufsVersion == null
                        ? 'UFS unknown'
                        : 'UFS ${h!.ufsVersion}',
                  ),
                ),
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
                child: AnimatedReadingBar(
                  value: fraction ?? 0,
                  minHeight: 6,
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BatteryInsightsPage(controller: controller),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final showGauge =
                    box.maxWidth >= 280 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 20;
                return Row(
                  children: [
                    Expanded(
                      flex: showGauge ? 2 : 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.battery_full_outlined,
                                size: 19,
                                color: p.accent,
                              ),
                              const SizedBox(width: 6),
                              const Flexible(
                                child: Text(
                                  'Battery',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: p.secondaryText,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              s.battery == null
                                  ? '—'
                                  : '${s.battery!.round()}%',
                              style: TextStyle(
                                fontSize: 56,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
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
                    if (showGauge)
                      Expanded(
                        flex: 3,
                        child: Center(
                          child: SizedBox(
                            key: const ValueKey('overview-battery-gauge'),
                            width: (box.maxWidth * .45).clamp(126.0, 164.0),
                            height: (box.maxWidth * .45).clamp(126.0, 164.0),
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
                                  size: 54,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: p.secondaryText),
                      ),
                      SizedBox(height: 8),
                      Text(
                        reading,
                        textAlign: TextAlign.center,
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
      final s = controller.stats!, h = controller.hardware;
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
            const SectionHeading('Performance', Icons.speed_rounded),
            SizedBox(height: 18),
            usage(
              'CPU',
              cpu,
              model: h?.cpuName?.replaceFirst('Qualcomm ', ''),
              caption: cpu == null
                  ? null
                  : '${(s.cpuWindowMs! / 1000).round()} s average · all cores',
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1),
            ),
            usage('GPU', s.gpuPercent, model: h?.gpuName),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1),
            ),
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

  Widget focusedAppsCard() => Builder(
    builder: (context) {
      final c = controller;
      return surface(
        child: Column(
          children: [
            FocusedApps(
              device: c.selected?.id,
              apps: (c.activity?['apps'] as List? ?? [])
                  .map((a) => Map<String, dynamic>.from(a as Map))
                  .toList(),
              interactive: c.stats?.interactive,
              onOpenDrawer: (screen) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AppsPage(controller: c, initialTarget: screen),
                ),
              ),
            ),
            if (c.activity?['lid'] is bool) ...[
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).accent.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        c.activity!['lid'] == true
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                        size: 17,
                        color: AppPalette.of(context).accent,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        c.activity!['lid'] == true ? 'Lid closed' : 'Lid open',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (c.activity!['lid'] == true &&
                          (c.activity!['closed_s'] as num? ?? 0) >= 60) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ${(c.activity!['closed_s'] as num? ?? 0).toInt() ~/ 60} min',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.of(context).secondaryText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (percent != null) ...[
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: AnimatedReadingBar(
                value: percent / 100,
                minHeight: 6,
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
            SectionHeading(
              'microSD card',
              Icons.sd_storage_outlined,
              trailing: s.sdState == SdCardState.readOnly
                  ? tag('Read only')
                  : null,
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
                child: AnimatedReadingBar(
                  value: fraction,
                  minHeight: 6,
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
          h?.displayModel ?? 'AYN Thor',
          style: TextStyle(color: secondaryText),
        ),
        SizedBox(height: 24),
        surface(
          copyText: statsForClipboard(c, StatsSection.device),
          copyLabel: 'Device stats',
          child: Column(
            children: [
              const SectionHeading('Hardware', Icons.developer_board_outlined),
              const SizedBox(height: 8),
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
              const SectionHeading('Firmware', Icons.system_update_alt_rounded),
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
              const SectionHeading(
                'Battery diagnostics',
                Icons.battery_saver_outlined,
              ),
              const SizedBox(height: 8),
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
                'USB input shows the power measured by the Thor. Remaining charge is not a battery health measurement.',
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
