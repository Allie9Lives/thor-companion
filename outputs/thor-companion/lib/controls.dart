import 'dart:async';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'telemetry.dart';
import 'ui.dart';
import 'keyboard_page.dart';
import 'screenshot_page.dart';
import 'files_page.dart';
import 'connection_health_page.dart';
import 'battery_pages.dart';

class ThorControlState {
  ThorControlState.fromBytes(List<int> bytes) : values = decodeObject(bytes) {
    if (values['v'] != 1) throw const FormatException('Unsupported controls');
  }
  final Map<String, dynamic> values;
  bool get settingsAllowed => values['settings'] == true;
  int? number(String key) =>
      values[key] is int && values[key] >= 0 ? values[key] as int : null;
}

class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  bool get brightnessLinked => c.brightnessLinked;
  bool get volumeLinked => c.volumeLinked;
  CompanionController get c => widget.controller;
  bool get powerEnabled =>
      c.connected &&
      !c.initializing &&
      !c.isDemo &&
      (!c.stale || c.keepAlivePaused);
  bool get enabled => c.connected && !c.stale && !c.initializing && !c.isDemo;
  final _sliderDrafts = <String, double>{};
  final _sliderTimers = <String, Timer>{};
  final _sliderPending = <String, (String, int, String)>{};
  final _sliderSentAt = <String, DateTime>{};
  @override
  void initState() {
    super.initState();
    c.controlsVisible = true;
  }

  @override
  void dispose() {
    for (final timer in _sliderTimers.values) {
      timer.cancel();
    }
    c.controlsVisible = false;
    super.dispose();
  }

  void _liveSlider(String key, int value, String target) {
    final slot = '$key:$target';
    _sliderPending[slot] = (key, value, target);
    void send() {
      _sliderTimers.remove(slot);
      final request = _sliderPending.remove(slot);
      if (!mounted || request == null) return;
      _sliderSentAt[slot] = DateTime.now();
      unawaited(c.setControl(request.$1, request.$2, target: request.$3));
    }

    final elapsed = DateTime.now()
        .difference(
          _sliderSentAt[slot] ?? DateTime.fromMillisecondsSinceEpoch(0),
        )
        .inMilliseconds;
    if (elapsed >= 150) {
      _sliderTimers.remove(slot)?.cancel();
      send();
    } else {
      _sliderTimers.putIfAbsent(
        slot,
        () => Timer(Duration(milliseconds: 150 - elapsed), send),
      );
    }
  }

  Future<void> _openTool(Widget page) async {
    c.controlsVisible = false;
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted) c.controlsVisible = true;
    }
  }

  Future<void> _power(int action) async {
    final label = switch (action) {
      0 => 'Sleep screens',
      1 => 'Restart Thor',
      2 => 'Shut down Thor',
      3 => 'Wake screens',
      _ => 'Allow deep sleep',
    };
    if (action == 1 || action == 2 || action == 4) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$label?'),
          content: Text(
            action == 4
                ? 'Release Thor Monitor’s CPU keep-alive and turn off the screens. Android decides when it sleeps; other apps may keep it awake. Remote commands may stop arriving until it wakes. Keep-alive restores at the configured local restore time, if monitoring stays enabled.'
                : action == 1
                ? 'Running games and apps will close. Monitoring resumes after restart if Start after restart is enabled.'
                : 'Running games and apps will close and the phone will disconnect. You will need to turn the Thor on again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: action == 2
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
                      foregroundColor: Theme.of(ctx).colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(label),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await c.devicePower(action);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label requested')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }
  }

  List<String> _sliderFields(String key, String target, bool linked) =>
      key == 'brightness'
      ? (linked ? ['bt', 'bb'] : [target == 'top' ? 'bt' : 'bb'])
      : (linked ? ['vt', 'vb'] : [target == 'top' ? 'vt' : 'vb']);

  void _setLinked(String key, bool linked) {
    final top = key == 'brightness' ? 'bt' : 'vt';
    final value = _sliderDrafts[top]?.round() ?? c.controlNumber(top);
    unawaited(
      c.setControlLink(
        brightness: key == 'brightness' ? linked : null,
        volume: key == 'volume' ? linked : null,
      ),
    );
    if (linked && value != null) {
      unawaited(c.setControl(key, value, target: 'both'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = c.controls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Controls',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (c.applyingControls)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: 'Applying changes',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (c.controlError != null)
          notice('Controls', c.controlError!, warning: true),
        surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tools',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final scale = MediaQuery.textScalerOf(context).scale(16),
                      columns = box.maxWidth >= 300 && scale <= 21 ? 2 : 1;
                  final width = (box.maxWidth - (columns - 1) * 8) / columns;
                  final height = (24 + 6 + scale * 2 * 1.3 + 20).clamp(
                    94.0,
                    320.0,
                  );
                  Widget tool(
                    String label,
                    IconData icon,
                    VoidCallback? action, {
                    bool primary = false,
                  }) {
                    final content = Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 24),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: scale * 2.4,
                          child: Center(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16, height: 1.2),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    );
                    return SizedBox(
                      width: width,
                      height: height,
                      child: primary
                          ? FilledButton.tonal(
                              onPressed: action,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              child: content,
                            )
                          : OutlinedButton(
                              onPressed: action,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              child: content,
                            ),
                    );
                  }

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      tool(
                        c.controlNumber('find') == 1
                            ? 'Stop sound'
                            : 'Find my Thor',
                        c.controlNumber('find') == 1
                            ? Icons.volume_off_outlined
                            : Icons.volume_up_outlined,
                        enabled && c.controls?.values['finder'] == true
                            ? () => c.setControl(
                                'find',
                                c.controlNumber('find') == 1 ? 0 : 1,
                              )
                            : null,
                        primary: true,
                      ),
                      tool(
                        'Open files',
                        Icons.folder_outlined,
                        () => _openTool(FilesPage(controller: c)),
                      ),
                      tool(
                        'Open keyboard',
                        Icons.keyboard_outlined,
                        () => _openTool(RemoteKeyboardPage(controller: c)),
                      ),
                      tool(
                        'Open screenshots',
                        Icons.screenshot_monitor,
                        () => _openTool(ScreenshotPage(controller: c)),
                      ),
                      tool(
                        'Connection health',
                        Icons.monitor_heart_outlined,
                        () => _openTool(ConnectionHealthPage(controller: c)),
                      ),
                      tool(
                        'Battery insights',
                        Icons.insights_outlined,
                        () => _openTool(BatteryInsightsPage(controller: c)),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'Find my Thor rises gently to full alarm volume over 20 seconds and stops after one minute. Tap the Thor’s notification to stop early.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (state == null) ...[
          surface(
            child: const Text(
              'Connect to an updated Thor Monitor to load its controls.',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: enabled ? c.refresh : null,
            child: const Text('Load controls'),
          ),
        ] else ...[
          if (!state.settingsAllowed) ...[
            notice(
              'Advanced controls',
              'Open Automatic recovery in Thor Monitor to check its status, then refresh here.',
            ),
            const SizedBox(height: 12),
          ],
          surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Brightness',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sync screens'),
                  value: brightnessLinked,
                  onChanged: (v) => _setLinked('brightness', v),
                ),
                slider(
                  'Top screen',
                  'brightness',
                  'top',
                  c.controlNumber('bt'),
                  brightnessLinked,
                ),
                slider(
                  'Bottom screen',
                  'brightness',
                  'bottom',
                  c.controlNumber('bb'),
                  brightnessLinked,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Volume',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sync volume'),
                  value: volumeLinked,
                  onChanged: (v) => _setLinked('volume', v),
                ),
                slider(
                  'Top screen',
                  'volume',
                  'top',
                  c.controlNumber('vt'),
                  volumeLinked,
                  allowed: state.settingsAllowed || !volumeLinked,
                ),
                slider(
                  'Bottom screen',
                  'volume',
                  'bottom',
                  c.controlNumber('vb'),
                  volumeLinked,
                  allowed: state.settingsAllowed,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                choice('Refresh rate', 'hz', c.controlNumber('hz'), const {
                  60: '60 Hz',
                  120: '120 Hz',
                }),
                const Text(
                  'Sets the display limit. Game frame rates depend on the game.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                choice('Fan', 'fan', c.controlNumber('fan'), const {
                  0: 'Off',
                  1: 'Quiet',
                  4: 'Smart',
                  5: 'Sports',
                }),
                choice(
                  'Performance',
                  'performance',
                  c.controlNumber('performance'),
                  const {
                    0: 'Standard',
                    1: 'Performance',
                    2: 'High performance',
                  },
                ),
                choice('Input focus', 'focus', c.controlNumber('focus'), const {
                  0: 'Automatic',
                  1: 'Top screen',
                  2: 'Bottom screen',
                }),
                toggle(
                  'Direct power supply',
                  'bypass',
                  c.controlNumber('bypass'),
                ),
                toggle('Vibration', 'vibration', c.controlNumber('vibration')),
                toggle('Ambient LEDs', 'led', c.controlNumber('led')),
                choice(
                  'Controller layout',
                  'style',
                  c.controlNumber('style'),
                  const {1: 'Standard', 0: 'Xbox', 2: 'Disabled'},
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Device Power',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      powerEnabled &&
                          !c.powerBusy &&
                          state.values['power_control'] == true
                      ? () => _power(
                          state.values['wake_control'] == true &&
                                  state.values['screens_awake'] == false
                              ? 3
                              : 0,
                        )
                      : null,
                  icon: const Icon(Icons.bedtime_outlined),
                  label: Text(
                    state.values['wake_control'] == true &&
                            state.values['screens_awake'] == false
                        ? 'Wake screens'
                        : 'Sleep screens',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      powerEnabled &&
                          !c.powerBusy &&
                          state.values['power_control'] == true
                      ? () => _power(1)
                      : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restart'),
                ),
                const SizedBox(height: 8),
                if (state.values['sleep_policy'] == true) ...[
                  OutlinedButton.icon(
                    onPressed:
                        enabled &&
                            !c.powerBusy &&
                            state.values['power_control'] == true
                        ? () => _power(4)
                        : null,
                    icon: const Icon(Icons.nights_stay_outlined),
                    label: const Text('Allow deep sleep'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onPressed:
                      powerEnabled &&
                          !c.powerBusy &&
                          state.values['power_control'] == true
                      ? () => _power(2)
                      : null,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Shut down'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          if (state.values['sleep_policy'] == true) ...[
            surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Battery saving',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.values['sleep_suspended'] == true
                        ? 'CPU keep-alive is paused'
                        : 'Overnight saving uses trusted networks configured on the Thor.',
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled
                        ? () async {
                            final minute = state.number('sleep_end') ?? 360;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: minute ~/ 60,
                                minute: minute % 60,
                              ),
                            );
                            if (time != null) {
                              await c.setControl(
                                'sleep_end',
                                time.hour * 60 + time.minute,
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.alarm),
                    label: Text(
                      'Restore keep-alive · ${TimeOfDay(hour: (state.number('sleep_end') ?? 360) ~/ 60, minute: (state.number('sleep_end') ?? 360) % 60).format(context)}',
                    ),
                  ),
                  Text(
                    state.values['sleep_exact'] == true
                        ? 'Scheduled on the Thor; the phone can be disconnected. Screens stay off.'
                        : 'Allow Alarms & reminders on the Thor for precise restoration; otherwise Android may delay it.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.tonal(
            onPressed: enabled && state.settingsAllowed
                ? () => c.setControl('clean', 0)
                : null,
            child: const Text('Clean background apps'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Clears cached background apps.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          OutlinedButton(
            onPressed: enabled ? c.refresh : null,
            child: const Text('Refresh controls'),
          ),
        ],
      ],
    );
  }

  Widget slider(
    String label,
    String key,
    String target,
    int? value,
    bool linked, {
    bool allowed = true,
  }) {
    final field = _sliderFields(key, target, false).single;
    return _ControlSlider(
      key: ValueKey('$key-$target'),
      label: label,
      value: _sliderDrafts[field] ?? value?.toDouble(),
      enabled: enabled && allowed && value != null,
      onPreview: (v) => setState(() {
        for (final f in _sliderFields(key, target, linked)) {
          _sliderDrafts[f] = v;
        }
        _liveSlider(key, v.round(), linked ? 'both' : target);
      }),
      onCommit: (v) {
        final slot = '$key:${linked ? 'both' : target}';
        _sliderTimers.remove(slot)?.cancel();
        _sliderPending.remove(slot);
        unawaited(c.setControl(key, v, target: linked ? 'both' : target));
        setState(() {
          for (final f in _sliderFields(key, target, true)) {
            _sliderDrafts.remove(f);
          }
        });
      },
    );
  }

  Widget choice(
    String label,
    String key,
    int? value,
    Map<int, String> options,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<int>(
      key: ValueKey('$key-$value'),
      initialValue: options.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: enabled && c.controls!.settingsAllowed
          ? (v) {
              if (v != null) unawaited(c.setControl(key, v));
            }
          : null,
    ),
  );
  Widget toggle(String label, String key, int? value) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value == 1,
    onChanged: enabled && c.controls!.settingsAllowed && value != null
        ? (v) => c.setControl(key, v ? 1 : 0)
        : null,
  );
}

class _ControlSlider extends StatelessWidget {
  const _ControlSlider({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPreview,
    required this.onCommit,
  });
  final String label;
  final double? value;
  final bool enabled;
  final ValueChanged<double> onPreview;
  final ValueChanged<int> onCommit;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(value == null ? '—' : '${value!.round()}%'),
        ],
      ),
      Slider(
        value: (value ?? 0).clamp(0, 100),
        min: 0,
        max: 100,
        divisions: 100,
        onChanged: enabled ? onPreview : null,
        onChangeEnd: enabled ? (v) => onCommit(v.round()) : null,
      ),
    ],
  );
}
