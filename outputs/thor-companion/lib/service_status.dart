import 'dart:async';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'web_ops_page.dart';
import 'ui.dart';

class ServiceStatusStrip extends StatefulWidget {
  const ServiceStatusStrip({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<ServiceStatusStrip> createState() => _ServiceStatusStripState();
}

class _ServiceStatusStripState extends State<ServiceStatusStrip> {
  CompanionController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.servicesVisible = true;
  }

  @override
  void dispose() {
    c.servicesVisible = false;
    super.dispose();
  }

  Future<void> toggle(String key, int bit) async {
    if (key == 'web' && (c.serviceBits! & 8) == 0) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => WebOpsPage(controller: c)),
      );
      return;
    }
    final on = c.serviceRunning(bit) == true;
    if (key == 'monitor' && on) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pause monitoring?'),
          content: const Text(
            'Readings and battery history will pause. Remote controls stay available. This does not put the Thor to sleep.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pause'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    try {
      await c.hostServiceAction(
        key == 'monitor'
            ? (on ? 'monitor_pause' : 'monitor_resume')
            : key == 'web'
            ? (on ? 'web_ops_stop' : 'web_ops_start')
            : (on ? 'ftp_stop' : 'ftp_start'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Could not change this service. Try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      children: [
        for (final item in [
          ('Web Ops', 'web', 2),
          ('FTP', 'ftp', 4),
          ('Monitoring', 'monitor', 1),
        ]) ...[
          if (item.$2 != 'web') const SizedBox(width: 7),
          Expanded(
            child: Tooltip(
              message: c.serviceBits == null
                  ? 'Update Thor Monitor to use service shortcuts'
                  : '${item.$1}: ${c.serviceRunning(item.$3) == true
                        ? 'On'
                        : item.$2 == 'monitor' && c.readingsPaused
                        ? 'Paused'
                        : 'Off'}',
              child: OutlinedButton(
                key: ValueKey('service-${item.$2}'),
                onPressed:
                    c.connected &&
                        !c.isDemo &&
                        c.serviceBits != null &&
                        !c.serviceBusy.contains(item.$2)
                    ? () => unawaited(toggle(item.$2, item.$3))
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  backgroundColor: p.card,
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.serviceRunning(item.$3) == true
                            ? p.accent
                            : p.secondaryText.withValues(alpha: .45),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.15,
                          fontWeight: FontWeight.w500,
                          color: c.serviceRunning(item.$3) == true
                              ? p.accent
                              : p.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
