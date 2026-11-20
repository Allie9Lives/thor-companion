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
      leading: DeviceIcon(device: device, color: p.accent),
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

/// Thor: two screens. Retroid Pocket Classic: a portrait handheld outline.
/// Anything else: a generic handheld.
class DeviceIcon extends StatelessWidget {
  const DeviceIcon({super.key, required this.device, required this.color});
  final SavedDevice device;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final product = device.product ?? '';
    if (product.startsWith('Retroid Pocket Classic')) {
      return SizedBox.square(
        dimension: 24,
        child: CustomPaint(painter: _PortraitHandheld(color)),
      );
    }
    return Icon(
      product.startsWith('AYN Thor') ||
              (device.product == null && device.screens == 2)
          ? Icons.splitscreen_outlined
          : Icons.videogame_asset_outlined,
      color: color,
    );
  }
}

/// Boxy outline of a vertical handheld: body, screen, d-pad and two buttons.
class _PortraitHandheld extends CustomPainter {
  const _PortraitHandheld(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * s
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    // Body: square corners, boxy like the Retroid Pocket Classic.
    canvas.drawRect(Rect.fromLTRB(5 * s, 2 * s, 19 * s, 22 * s), line);
    canvas.drawRect(Rect.fromLTRB(8 * s, 5 * s, 16 * s, 11 * s), line);
    // D-pad.
    canvas.drawRect(Rect.fromLTRB(7.6 * s, 15.4 * s, 11.4 * s, 16.6 * s), fill);
    canvas.drawRect(Rect.fromLTRB(8.9 * s, 14.1 * s, 10.1 * s, 17.9 * s), fill);
    // A/B buttons.
    canvas.drawCircle(Offset(15.6 * s, 15 * s), 1.1 * s, fill);
    canvas.drawCircle(Offset(13.6 * s, 16.8 * s), 1.1 * s, fill);
  }

  @override
  bool shouldRepaint(_PortraitHandheld old) => old.color != color;
}
