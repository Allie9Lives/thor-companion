import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'ui.dart';
import 'design_components.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.controller,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onAction,
  });
  final CompanionController controller;
  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final ValueChanged<String> onAction;
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late AppAppearance selected = widget.appearance;
  bool appearancePage = false;
  static const choices = [
    (AppAppearance.system, 'System default', Icons.brightness_auto_outlined),
    (AppAppearance.light, 'Light', Icons.light_mode_outlined),
    (AppAppearance.dark, 'Dark', Icons.dark_mode_outlined),
    (AppAppearance.clearPurple, 'Clear Purple', Icons.palette_outlined),
    (AppAppearance.rainbow, 'Rainbow', Icons.color_lens_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        child: AnimatedSize(
          alignment: Alignment.topCenter,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: thorCurve,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (appearancePage)
                    IconButton(
                      tooltip: 'Back to settings',
                      onPressed: () => setState(() => appearancePage = false),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      appearancePage ? 'Appearance' : 'Settings',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close settings',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (appearancePage) ...[
                appearanceChoices(),
              ] else ...[
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) => surface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reconnect automatically',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Disconnect pauses retries.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: p.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: widget.controller.automaticReconnect,
                          onChanged: widget.controller.isDemo
                              ? null
                              : (value) => unawaited(
                                  widget.controller.setAutomaticReconnect(
                                    value,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                grid([
                  (
                    'Appearance',
                    Icons.palette_outlined,
                    choices.firstWhere((c) => c.$1 == selected).$2,
                    () => setState(() => appearancePage = true),
                  ),
                  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                    (
                      'Battery widgets',
                      Icons.widgets_outlined,
                      'Home & Lock Screen',
                      () => widget.onAction('widgets'),
                    ),
                  (
                    'Battery notifications',
                    Icons.notifications_outlined,
                    'Alerts & thresholds',
                    () => widget.onAction('alerts'),
                  ),
                  (
                    'Battery insights',
                    Icons.insights_outlined,
                    'History & runtime',
                    () => widget.onAction('insights'),
                  ),
                  (
                    'Files',
                    Icons.folder_outlined,
                    'Wi-Fi / VPN',
                    () => widget.onAction('files'),
                  ),
                  (
                    'Connection health',
                    Icons.monitor_heart_outlined,
                    'Bluetooth & network',
                    () => widget.onAction('health'),
                  ),
                ]),
                const SizedBox(height: 12),
                surface(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: p.accent,
                        size: 21,
                      ),
                    ),
                    title: const Text(
                      'About',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Thor Companion · Allie Stark'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => widget.onAction('about'),
                  ),
                ),
                const SizedBox(height: 22),
                Divider(color: p.border, height: 1),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Connection help'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => widget.onAction('help'),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.music_note_outlined),
                  title: const Text('Sound credits'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => widget.onAction('credits'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget appearanceChoices() => LayoutBuilder(
    builder: (context, box) {
      final p = AppPalette.of(context),
          scale = MediaQuery.textScalerOf(context);
      final columns = box.maxWidth >= 290 && scale.scale(16) <= 22 ? 2 : 1;
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      void choose(AppAppearance mode) {
        widget.onAppearanceChanged(mode);
        setState(() => selected = mode);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => choose(AppAppearance.system),
            icon: Icon(
              selected == AppAppearance.system
                  ? Icons.check_circle_outline
                  : Icons.brightness_auto_outlined,
            ),
            label: const Text('System default'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final choice in choices.where(
                (c) => c.$1 != AppAppearance.system,
              ))
                SizedBox(
                  width: width,
                  height: (58 + 12 + scale.scale(16) * 1.2 + 24).clamp(
                    126.0,
                    240.0,
                  ),
                  child: OutlinedButton(
                    onPressed: () => choose(choice.$1),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      side: BorderSide(
                        color: selected == choice.$1 ? p.accent : p.border,
                        width: selected == choice.$1 ? 1.5 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _themePreview(choice.$1)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                choice.$2,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: p.foreground,
                                ),
                              ),
                            ),
                            if (selected == choice.$1)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 17,
                                color: p.accent,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );

  Widget _themePreview(AppAppearance mode) {
    final palette = switch (mode) {
      AppAppearance.light => AppPalette.light,
      AppAppearance.dark => AppPalette.dark,
      AppAppearance.clearPurple => AppPalette.clearPurple,
      _ => AppPalette.rainbow,
    };
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.foreground.withValues(alpha: .7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 24,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.secondaryText.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  if (mode == AppAppearance.rainbow) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final color in palette.rainbowColors)
                          Container(width: 8, height: 3, color: color),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: .72,
                strokeWidth: 3,
                color: palette.accent,
                backgroundColor: palette.border,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget grid(
    List<(String, IconData, String, VoidCallback)> actions, {
    String? selectedLabel,
  }) => LayoutBuilder(
    builder: (context, box) {
      final p = AppPalette.of(context),
          scaler = MediaQuery.textScalerOf(context);
      final columns = box.maxWidth >= 290 && scaler.scale(16) <= 22 ? 2 : 1;
      final width = (box.maxWidth - (columns - 1) * 10) / columns;
      final height =
          (36 + 12 + scaler.scale(16) * 2.4 + 5 + scaler.scale(13) * 1.25 + 40)
              .clamp(144.0, 360.0);
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < actions.length; i++)
            SizedBox(
              width: width,
              height: height,
              child: ActionTile(
                label: actions[i].$1,
                icon: actions[i].$2,
                subtitle: actions[i].$3,
                onPressed: actions[i].$4,
                selected: actions[i].$1 == selectedLabel,
                color: p.isRainbow ? p.rainbowColors[i % 4] : p.accent,
              ),
            ),
        ],
      );
    },
  );
}
