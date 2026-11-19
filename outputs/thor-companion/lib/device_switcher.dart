import 'dart:async';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'design_components.dart';
import 'saved_devices.dart';
import 'ui.dart';

/// Lists saved handhelds; one is connected at a time.
Future<void> showDevices(BuildContext context, CompanionController c) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      sheetAnimationStyle: thorSheetAnimation(context),
      builder: (context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final p = AppPalette.of(context);
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Your devices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (final d in c.devices)
                  DeviceRow(
                    device: d,
                    active: d.id == c.remembered?.id,
                    onTap: c.busy || d.id == c.remembered?.id
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            unawaited(c.switchTo(d));
                          },
                    onForget: () => unawaited(c.forgetDevice(d)),
                  ),
                ListTile(
                  leading: Icon(Icons.add, color: p.accent),
                  title: const Text('Add a device'),
                  subtitle: const Text(
                    'Pair another handheld running Thor Monitor',
                  ),
                  onTap: c.busy
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          unawaited(c.addDevice());
                        },
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );

class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.device,
    required this.active,
    this.onTap,
    this.onForget,
  });
  final SavedDevice device;
  final bool active;
  final VoidCallback? onTap, onForget;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListTile(
      leading: Icon(
        device.screens == 1
            ? Icons.stay_current_portrait_outlined
            : Icons.splitscreen_outlined,
        color: p.accent,
      ),
      title: Text(device.name),
      subtitle: Text(
        [
          device.product ?? (device.screens == 1 ? 'Handheld' : 'AYN Thor'),
          if (active) 'Current',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active) Icon(Icons.check, color: p.accent),
          if (onForget != null)
            PopupMenuButton<String>(
              tooltip: 'Device options',
              icon: const Icon(Icons.more_horiz),
              onSelected: (_) => onForget!(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'forget', child: Text('Forget device')),
              ],
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
