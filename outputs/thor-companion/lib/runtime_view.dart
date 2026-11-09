import 'package:flutter/material.dart';
import 'battery_runtime.dart';
import 'companion_controller.dart';
import 'ui.dart';

class RuntimeView extends StatelessWidget {
  const RuntimeView({
    super.key,
    required this.controller,
    this.details = false,
    this.onDetails,
  });
  final CompanionController controller;
  final bool details;
  final VoidCallback? onDetails;
  @override
  Widget build(BuildContext context) {
    final c = controller,
        p = AppPalette.of(context),
        r = estimateBatteryRuntime(
          c.batteryLedger.points,
          c.stats,
          fresh: c.isDemo || c.connected && !c.stale,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.schedule_outlined, size: 21, color: p.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estimated runtime',
                style: TextStyle(fontSize: 14, color: p.secondaryText),
              ),
              Text(
                r.label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (details) ...[
                const SizedBox(height: 6),
                Text(
                  r.detail,
                  style: TextStyle(fontSize: 14, color: p.secondaryText),
                ),
              ],
            ],
          ),
        ),
        if (onDetails != null)
          IconButton(
            tooltip: 'About runtime estimate',
            onPressed: onDetails,
            icon: const Icon(Icons.info_outline, size: 21),
          ),
      ],
    );
  }
}
