import 'package:flutter/material.dart';
import 'ui.dart';
import 'app_icons.dart';

class FocusedApps extends StatefulWidget {
  const FocusedApps({
    super.key,
    required this.apps,
    this.interactive,
    this.onOpenDrawer,
    this.device,
  });
  final List<Map<String, dynamic>> apps;
  final bool? interactive;
  final ValueChanged<String>? onOpenDrawer;
  final String? device;
  @override
  State<FocusedApps> createState() => _FocusedAppsState();
}

class _FocusedAppsState extends State<FocusedApps> {
  AppIconCache? icons;
  @override
  void initState() {
    super.initState();
    if (widget.device != null) icons = AppIconCache(widget.device!);
  }

  @override
  void didUpdateWidget(FocusedApps old) {
    super.didUpdateWidget(old);
    if (old.device != widget.device) {
      icons?.close();
      icons = widget.device == null ? null : AppIconCache(widget.device!);
    }
  }

  @override
  void dispose() {
    icons?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Map<String, dynamic>? at(bool top) {
      for (final app in widget.apps) {
        if (top ? app['d'] == 0 : app['d'] == 4) return app;
      }
      return null;
    }

    Widget screen(bool top) {
      final app = at(top), cpu = at(top)?['cpu'];
      final name = app?['name'] ?? app?['p'] ?? 'No focused app';
      return Semantics(
        button: widget.onOpenDrawer != null,
        label: '${top ? 'Top' : 'Bottom'} screen. Open app drawer.',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onOpenDrawer == null
                ? null
                : () => widget.onOpenDrawer!(top ? 'top' : 'bottom'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              key: ValueKey(
                top ? 'focused-top-screen' : 'focused-bottom-screen',
              ),
              constraints: BoxConstraints(minHeight: top ? 180 : 168),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: p.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: p.accent.withValues(alpha: .55),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    top ? 'TOP SCREEN' : 'BOTTOM SCREEN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CachedAppIcon(
                      future: icons?.get(
                        app?['p'] as String? ?? '',
                        app?['icon'] as String?,
                      ),
                      name: '$name',
                      identity: '${app?['p']}',
                      color: p.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$name',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (app != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${widget.interactive == false ? 'Last focused' : 'Focused'}${cpu is num ? ' · ${cpu.toStringAsFixed(1)}% CPU' : ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: p.secondaryText),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices_outlined, size: 22),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Focused apps',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (widget.onOpenDrawer != null) ...[
              const SizedBox(height: 5),
              Text(
                'Tap a screen to choose an app',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: p.secondaryText),
              ),
            ],
            const SizedBox(height: 14),
            Center(child: SizedBox(width: 220, child: screen(true))),
            Center(
              child: Container(
                width: 80,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Center(child: SizedBox(width: 180, child: screen(false))),
          ],
        ),
      ),
    );
  }
}
