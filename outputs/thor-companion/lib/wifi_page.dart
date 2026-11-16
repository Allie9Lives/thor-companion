import 'dart:async';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'wifi_delegation.dart';
import 'ui.dart';

class WifiPage extends StatefulWidget {
  const WifiPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  List<Map<String, dynamic>> saved = [], nearby = [];
  bool busy = false, showNearby = false;
  String? error, message;
  CompanionController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.wifiVisible = true;
    unawaited(load());
  }

  @override
  void dispose() {
    c.wifiVisible = false;
    super.dispose();
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Could not complete Wi-Fi setup. Check Controls recovery on the Thor.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => action(() async {
    await c.refreshWifi();
    final list = await c.wifiNetworks();
    if (mounted) setState(() => saved = list);
  });
  Future<void> connect(Map<String, dynamic> n) => action(() async {
    await c.joinSavedWifi((n['id'] as num).toInt());
    if (mounted) {
      setState(() => message = 'Connection requested. Waiting for the Thor…');
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await c.refreshWifi();
  });
  Future<void> join([Map<String, dynamic>? network]) async {
    final name = TextEditingController(text: network?['n'] as String? ?? ''),
        password = TextEditingController();
    String security = network?['s'] as String? ?? 'wpa2';
    bool reveal = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Join Wi-Fi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Network name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: security,
                  decoration: const InputDecoration(labelText: 'Security'),
                  items: const [
                    DropdownMenuItem(
                      value: 'wpa2',
                      child: Text('WPA2 Personal'),
                    ),
                    DropdownMenuItem(
                      value: 'wpa3',
                      child: Text('WPA3 Personal'),
                    ),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(
                      value: 'owe',
                      child: Text('Enhanced Open'),
                    ),
                  ],
                  onChanged: (v) => update(() => security = v!),
                ),
                if (security == 'wpa2' || security == 'wpa3')
                  TextField(
                    controller: password,
                    obscureText: !reveal,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => update(() => reveal = !reveal),
                        icon: Icon(
                          reveal ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'The password is sent to the Thor over encrypted Bluetooth.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
    final ssid = name.text, secret = password.text;
    name.dispose();
    password.clear();
    password.dispose();
    if (result == true) {
      await action(() async {
        await c.joinNewWifi(ssid, security, secret);
        if (mounted) setState(() => message = 'Connection requested.');
        await Future<void>.delayed(const Duration(seconds: 3));
        await c.refreshWifi();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final state = c.wifiState,
          p = AppPalette.of(context),
          connected = state?['connected'] == true;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Thor Wi-Fi'),
          actions: [
            IconButton(
              onPressed: busy ? null : load,
              tooltip: 'Refresh networks',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            surface(
              child: Row(
                children: [
                  Icon(
                    connected ? Icons.wifi : Icons.wifi_off,
                    size: 30,
                    color: p.accent,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected
                              ? '${state?['name']}'
                              : state?['enabled'] == false
                              ? 'Wi-Fi is off'
                              : 'Not connected',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          state?['captive'] == true
                              ? 'Sign-in required'
                              : state?['validated'] == true
                              ? 'Internet available'
                              : connected
                              ? 'Local network connected'
                              : 'Choose a saved network or join another.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (state?['enabled'] == false)
              FilledButton.icon(
                onPressed: busy || !c.bluetoothAvailable
                    ? null
                    : () => action(() async {
                        await c.enableThorWifi();
                        await Future<void>.delayed(const Duration(seconds: 2));
                        await c.refreshWifi();
                      }),
                icon: const Icon(Icons.wifi),
                label: const Text('Turn on Thor Wi-Fi'),
              ),
            if (state?['captive'] == true) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : () => action(c.openWifiSignIn),
                icon: const Icon(Icons.login),
                label: const Text('Open sign-in on Thor'),
              ),
              const Text(
                'Complete sign-in on the Thor. You can use the remote keyboard to help.',
                style: TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 16),
            surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Follow phone Wi-Fi'),
                    subtitle: Text(
                      WifiFollowing.usesAutomation
                          ? 'Use an iPhone Wi-Fi automation.'
                          : 'Join the phone’s network when the app is active.',
                    ),
                    value: c.followWifi,
                    onChanged: busy
                        ? null
                        : (v) => action(() => c.setFollowWifi(v)),
                  ),
                  const Text(
                    'Only joins networks already saved on the Thor. Bluetooth must be connected. Passwords aren’t copied from your phone.',
                    style: TextStyle(fontSize: 14),
                  ),
                  if (WifiFollowing.usesAutomation)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Set up iPhone automation'),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'In Shortcuts → Automation, add a Wi-Fi “is joined” automation. Add Get Network Details (Wi-Fi → Network Name), then Follow Wi-Fi on Thor and pass the network name. Choose Run Immediately. Enable this switch for each Thor you want to follow. iPhone may need to be unlocked to open the app.',
                          ),
                        ),
                      ],
                    ),
                  if (c.followStatus != null) Text(c.followStatus!),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Saved networks',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            if (saved.isEmpty && !busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No saved networks loaded. Refresh after setting up Controls recovery.',
                ),
              ),
            ...saved.map(
              (n) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  n['s'] == 'open' ? Icons.wifi : Icons.wifi_password,
                ),
                title: Text('${n['n']}'),
                subtitle: Text(
                  n['s'] == 'enterprise'
                      ? 'Enterprise · saved configuration'
                      : '${n['s']}'.toUpperCase(),
                ),
                trailing: state?['id'] == n['id'] && connected
                    ? const Icon(Icons.check_circle_outline)
                    : const Icon(Icons.chevron_right),
                onTap: busy || !c.bluetoothAvailable ? null : () => connect(n),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy || !c.bluetoothAvailable ? null : () => join(),
              icon: const Icon(Icons.add),
              label: const Text('Join another network'),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => action(() async {
                      final list = await c.wifiNetworks(nearby: true);
                      if (mounted) {
                        setState(() {
                          nearby = list;
                          showNearby = true;
                        });
                      }
                    }),
              icon: const Icon(Icons.radar),
              label: const Text('Scan nearby'),
            ),
            if (showNearby)
              ...nearby.map(
                (n) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${n['n']}'),
                  subtitle: Text('${n['s']}'.toUpperCase()),
                  trailing: const Icon(Icons.add),
                  onTap: busy || !c.bluetoothAvailable
                      ? null
                      : () => n['s'] == 'enterprise'
                            ? showDialog<void>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Enterprise Wi-Fi'),
                                  content: const Text(
                                    'Set up this network and its certificate in Android Settings on the Thor. Once saved, you can select it here.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              )
                            : join(n),
                ),
              ),
            if (!c.bluetoothAvailable)
              notice(
                'Bluetooth needed',
                'Connect over Bluetooth before changing the Thor’s Wi-Fi.',
              ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(message!),
              ),
            if (error ?? c.wifiError case final String text)
              notice('Wi-Fi', text, warning: true),
          ],
        ),
      );
    },
  );
}
