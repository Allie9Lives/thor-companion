import 'companion_controller.dart';
import 'telemetry.dart';
import 'battery_runtime.dart';

enum StatsSection {
  battery,
  performance,
  internal,
  sd,
  device,
  firmware,
  diagnostics,
}

String statsForClipboard(CompanionController c, StatsSection section) {
  final s = c.stats, h = c.hardware;
  String text(String? value) => value ?? 'Unavailable';
  String number(num? value, String unit, {int digits = 1}) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(digits)}$unit';
  final lines = <String>[];
  void row(String label, Object? value) =>
      lines.add('$label: ${value ?? 'Unavailable'}');
  final title = switch (section) {
    StatsSection.battery => 'Battery',
    StatsSection.performance => 'Performance',
    StatsSection.internal => 'Internal storage',
    StatsSection.sd => 'microSD card',
    StatsSection.device => 'Device information',
    StatsSection.firmware => 'Firmware',
    StatsSection.diagnostics => 'Battery diagnostics',
  };
  lines.add('$title — ${c.deviceDisplayName}');
  if (c.isDemo) {
    lines.add('Demo data — no device connected');
  } else if (section != StatsSection.device &&
      section != StatsSection.firmware) {
    lines.add(
      c.stale || !c.connected ? 'Last known readings' : 'Live readings',
    );
    if (s?.sourceTimeMs != null) {
      row(
        'Sample time',
        DateTime.fromMillisecondsSinceEpoch(
          s!.sourceTimeMs!,
        ).toLocal().toIso8601String(),
      );
    }
  }
  switch (section) {
    case StatsSection.battery:
      row('Battery', number(s?.battery, '%', digits: 0));
      row('Status', s?.chargingLabel);
      row('Power source', s?.powerSource);
      row('Temperature', number(s?.temperature, ' °C'));
      row(
        'Voltage',
        number(
          s?.voltageMv == null ? null : s!.voltageMv! / 1000,
          ' V',
          digits: 2,
        ),
      );
      row('USB input', number(s?.inputWatts, ' W'));
      final runtime = estimateBatteryRuntime(
        c.batteryLedger.points,
        s,
        fresh: c.isDemo || c.connected && !c.stale,
      );
      row('Estimated runtime', runtime.label);
      row('Estimate basis', runtime.detail);
    case StatsSection.performance:
      row('CPU', text(h?.cpuName));
      row(
        'CPU usage (all cores)',
        number(
          s?.cpuWindowMs != null && s!.cpuWindowMs! >= 1000
              ? s.cpuPercent
              : null,
          '%',
        ),
      );
      row(
        'CPU measurement window',
        s?.cpuWindowMs == null ? 'Unavailable' : '${s!.cpuWindowMs} ms',
      );
      row('GPU', text(h?.gpuName));
      row('GPU usage (device-wide)', number(s?.gpuPercent, '%'));
      row(
        'RAM used',
        h?.ramBytes == null || s?.ramAvailableBytes == null
            ? 'Unavailable'
            : capacity(h!.ramBytes! - s!.ramAvailableBytes!, decimals: 1),
      );
      row('RAM total', capacity(h?.ramBytes, decimals: 1));
      final activity = c.activity;
      if (activity != null) {
        for (final raw in (activity['apps'] as List? ?? [])) {
          final app = raw as Map;
          row(
            '${app['d'] == 0 ? 'Top' : 'Bottom'} focused / last focused',
            app['name'] ?? app['p'],
          );
          row(
            'App CPU (all cores)',
            number(app['cpu'] is num ? app['cpu'] as num : null, '%'),
          );
        }
      }
    case StatsSection.internal:
      row('UFS', h?.ufsVersion == null ? 'Unknown' : 'UFS ${h!.ufsVersion}');
      row('Free', capacity(s?.freeBytes));
      row('Usable total', capacity(h?.dataBytes));
      row(
        'Used',
        number(
          h?.usedFraction(s?.freeBytes) == null
              ? null
              : h!.usedFraction(s?.freeBytes)! * 100,
          '%',
          digits: 0,
        ),
      );
    case StatsSection.sd:
      row('State', switch (s?.sdState) {
        SdCardState.mounted => 'Mounted',
        SdCardState.readOnly => 'Read only',
        SdCardState.notPresent => 'No card detected',
        SdCardState.notMounted => 'Not mounted',
        _ => 'Unavailable',
      });
      if (s?.sdUsedFraction != null) {
        row('Free', capacity(s?.sdFreeBytes));
        row('Usable total', capacity(s?.sdTotalBytes));
        row('Used', number(s!.sdUsedFraction! * 100, '%', digits: 0));
      }
    case StatsSection.device:
      row('Device name', h?.deviceName ?? c.selected?.name);
      row('Model', h?.displayModel);
      if (h?.variant != null) {
        row('Model detection', 'Inferred from processor and RAM');
      }
      row('Storage configuration', h?.storageConfiguration);
      row('SoC identifier', h?.socModel);
      row('Android', h?.android);
      row('CPU', h?.cpuName);
      row('GPU', h?.gpuName);
      row('System RAM', capacity(h?.ramBytes, decimals: 1));
      row(
        'Storage standard',
        h?.ufsVersion == null ? 'Unknown' : 'UFS ${h!.ufsVersion}',
      );
      row('Storage chip', h?.storageModel);
      row('Usable data capacity', capacity(h?.dataBytes, decimals: 1));
    case StatsSection.firmware:
      row('Build', h?.build);
    case StatsSection.diagnostics:
      row(
        'Reported current (raw)',
        number(
          s?.currentUa == null ? null : s!.currentUa! / 1000,
          ' mA',
          digits: 0,
        ),
      );
      row(
        'Remaining charge',
        number(
          s?.chargeUah == null ? null : s!.chargeUah! / 1000,
          ' mAh',
          digits: 0,
        ),
      );
  }
  return lines.join('\n');
}
