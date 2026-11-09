import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'ui.dart';

class RemoteKeyboardPage extends StatefulWidget {
  const RemoteKeyboardPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<RemoteKeyboardPage> createState() => _RemoteKeyboardPageState();
}

class _RemoteKeyboardPageState extends State<RemoteKeyboardPage> {
  final draft = TextEditingController();
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final supported = c.controls?.values['keyboard'] == true;
      final selected = c.controls?.values['keyboard_selected'] == true;
      final enabled =
          c.connected &&
          !c.stale &&
          !c.reading &&
          !c.initializing &&
          !c.controlBusy &&
          selected &&
          !c.isDemo;
      Widget key(String label, String value, {IconData? icon}) =>
          OutlinedButton.icon(
            onPressed: enabled ? () => c.sendKeyboardKey(value) : null,
            icon: Icon(icon ?? Icons.keyboard),
            label: Text(label),
          );
      return Scaffold(
        appBar: AppBar(title: const Text('Keyboard')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!supported || !selected) ...[
                notice(
                  'Set up on your Thor',
                  supported
                      ? 'Open Thor Monitor → Phone keyboard. Enable Thor Remote Keyboard, then select it.'
                      : 'Update Thor Monitor, then enable Thor Remote Keyboard under Phone keyboard.',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: c.connected && !c.controlBusy && !c.reading
                      ? c.refreshControls
                      : null,
                  child: const Text('Check keyboard setup'),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Tap a text field on your Thor. Type here, then send.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: draft,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                enabled: !c.keyboardBusy,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Text to type',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: enabled && draft.text.isNotEmpty
                    ? () async {
                        final sent = await c.sendKeyboardText(draft.text);
                        if (sent && context.mounted) {
                          draft.clear();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Text sent')),
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.send),
                label: Text(c.keyboardBusy ? 'Sending…' : 'Send text'),
              ),
              if (c.keyboardError != null) ...[
                const SizedBox(height: 12),
                notice('Keyboard', c.keyboardError!, warning: true),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  key('Backspace', 'backspace', icon: Icons.backspace_outlined),
                  key('Enter', 'enter', icon: Icons.keyboard_return),
                  key('Tab', 'tab', icon: Icons.keyboard_tab),
                  key('Left', 'left', icon: Icons.arrow_back),
                  key('Right', 'right', icon: Icons.arrow_forward),
                  key('Up', 'up', icon: Icons.arrow_upward),
                  key('Down', 'down', icon: Icons.arrow_downward),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Input goes to the focused field on either Thor screen. Enter follows that app’s keyboard action.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      );
    },
  );
}
