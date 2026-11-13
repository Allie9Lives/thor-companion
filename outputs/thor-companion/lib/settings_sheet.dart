import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'ui.dart';

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
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
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
                grid(
                  choices
                      .map(
                        (choice) => (
                          choice.$2,
                          choice.$3,
                          choice.$1 == selected
                              ? 'Selected'
                              : choice.$1 == AppAppearance.system
                              ? 'Follow iPhone appearance'
                              : 'Use ${choice.$2}',
                          () {
                            widget.onAppearanceChanged(choice.$1);
                            setState(() {
                              selected = choice.$1;
                              appearancePage = false;
                            });
                          },
                        ),
                      )
                      .toList(),
                  selectedLabel: choices.firstWhere((c) => c.$1 == selected).$2,
                ),
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
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => widget.onAction('about'),
                ),
              ],
            ],
          ),
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
          (24 + 8 + scaler.scale(16) * 2.4 + 4 + scaler.scale(13) * 1.2 + 24)
              .clamp(126.0, 340.0);
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < actions.length; i++)
            SizedBox(
              width: width,
              height: height,
              child: OutlinedButton(
                onPressed: actions[i].$4,
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.foreground,
                  backgroundColor: actions[i].$1 == selectedLabel
                      ? p.accent.withValues(alpha: .10)
                      : p.card,
                  side: BorderSide(
                    color: actions[i].$1 == selectedLabel ? p.accent : p.border,
                    width: actions[i].$1 == selectedLabel ? 1.5 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      actions[i].$1 == selectedLabel
                          ? Icons.check_circle_outline
                          : actions[i].$2,
                      size: 24,
                      color: p.isRainbow ? p.rainbowColors[i % 4] : p.accent,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: scaler.scale(16) * 2.4,
                      child: Center(
                        child: Text(
                          actions[i].$1,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      actions[i].$3,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: p.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
