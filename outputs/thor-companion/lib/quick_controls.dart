import 'package:flutter/material.dart';
import 'ui.dart';
import 'design_components.dart';
import 'control_symbol.dart';

class QuickControls extends StatelessWidget {
  const QuickControls({
    super.key,
    required this.values,
    required this.enabled,
    required this.onSet,
  });
  final Map<String, dynamic> values;
  final bool enabled;
  final void Function(String key, int value) onSet;
  static const settings = [
    ('Refresh rate', 'hz', {60: '60 Hz', 120: '120 Hz'}),
    (
      'Performance',
      'performance',
      {0: 'Standard', 1: 'Performance', 2: 'High performance'},
    ),
    ('Fan', 'fan', {0: 'Off', 1: 'Quiet', 4: 'Smart', 5: 'Sports'}),
    (
      'Input focus',
      'focus',
      {0: 'Automatic', 1: 'Top screen', 2: 'Bottom screen'},
    ),
    ('Direct power', 'bypass', {0: 'Off', 1: 'On'}),
    ('Vibration', 'vibration', {0: 'Off', 1: 'On'}),
    ('Controller', 'style', {1: 'Standard', 0: 'Xbox', 2: 'Disabled'}),
    ('Ambient LEDs', 'led', {0: 'Off', 1: 'On'}),
    ('Clean memory', 'clean', <int, String>{}),
  ];

  Future<void> choose(
    BuildContext context,
    String label,
    String key,
    Map<int, String> choices,
    int? value,
  ) async {
    final selection = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      sheetAnimationStyle: thorSheetAnimation(context),
      builder: (context) {
        final p = AppPalette.of(context);
        // Scrolls on short screens instead of overflowing the sheet.
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final (index, choice) in choices.entries.indexed)
                // Rows cascade in after the sheet starts to rise.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: motionDuration(context, 260 + 45 * index),
                  curve: thorCurve,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      tileColor: choice.key == value
                          ? p.accent.withValues(alpha: .10)
                          : null,
                      title: Text(choice.value),
                      trailing: choice.key == value
                          ? Icon(Icons.check, color: p.accent)
                          : null,
                      selected: choice.key == value,
                      onTap: () => Navigator.pop(context, choice.key),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (selection != null && context.mounted && enabled) onSet(key, selection);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final columns =
            box.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 20
            ? 2
            : 3;
        final width = (box.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 14,
          children: [
            for (final (label, key, options) in settings)
              // Hosts omit controls the handheld doesn't have.
              if (values.isEmpty || key == 'clean' || values.containsKey(key))
                Builder(
                  builder: (context) {
                    final value = values[key] is int && values[key] >= 0
                        ? values[key] as int
                        : null;
                    final toggle =
                        key == 'bypass' || key == 'vibration' || key == 'led';
                    final active = toggle && value == 1;
                    final available =
                        enabled &&
                        (key == 'clean' || options.containsKey(value));
                    final status = key == 'clean'
                        ? 'Clear cached apps'
                        : options[value] ?? 'Unavailable';
                    return SizedBox(
                      width: width,
                      child: Semantics(
                        button: true,
                        enabled: available,
                        toggled: toggle ? active : null,
                        label: '$label, $status',
                        excludeSemantics: true,
                        child: InkWell(
                          key: ValueKey('quick-$key'),
                          borderRadius: BorderRadius.circular(18),
                          onTap: !available
                              ? null
                              : key == 'clean'
                              ? () => onSet(key, 0)
                              : options.length == 2
                              ? () => onSet(
                                  key,
                                  options.keys.firstWhere((v) => v != value),
                                )
                              : () =>
                                    choose(context, label, key, options, value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                PressGlow(
                                  enabled: available,
                                  builder: (context, pressed) => AnimatedScale(
                                    scale: pressed ? .93 : 1,
                                    duration: motionDuration(context, 140),
                                    curve: thorCurve,
                                    child: AnimatedContainer(
                                      duration: motionDuration(context, 220),
                                      curve: Curves.easeOutCubic,
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: glow(
                                          p.accent,
                                          pressed
                                              ? 1
                                              : active
                                              ? .55
                                              : 0,
                                        ),
                                        color: active
                                            ? p.accent
                                            : p.accent.withValues(
                                                alpha: available ? .12 : .04,
                                              ),
                                        border: Border.all(
                                          color: p.accent.withValues(
                                            alpha: active ? .8 : .22,
                                          ),
                                        ),
                                      ),
                                      child: Center(
                                        child: ControlSymbol(
                                          key,
                                          color: active
                                              ? p.onAccent
                                              : available
                                              ? p.accent
                                              : p.secondaryText,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height:
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(14) *
                                      2.3,
                                  child: Center(
                                    child: Text(
                                      label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.15,
                                        fontWeight: FontWeight.w600,
                                        color: available
                                            ? p.foreground
                                            : p.secondaryText,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SizedBox(
                                  height:
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(13) *
                                      2.3,
                                  child: Text(
                                    status,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.15,
                                      color: active
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
                    );
                  },
                ),
          ],
        );
      },
    );
  }
}
