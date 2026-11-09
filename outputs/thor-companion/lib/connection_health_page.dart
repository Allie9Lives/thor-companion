import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_transport.dart';
import 'companion_controller.dart';
import 'network_link.dart';
import 'ui.dart';

class ConnectionHealthPage extends StatefulWidget {
  const ConnectionHealthPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<ConnectionHealthPage> createState() => _ConnectionHealthPageState();
}

class _ConnectionHealthPageState extends State<ConnectionHealthPage> {
  late final NetworkLink network;
  bool previousControls = false;
  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    previousControls = c.controlsVisible;
    c.controlsVisible = false;
    network = NetworkLink(c);
    unawaited(
      network.restore().then((_) {
        if (mounted && network.connection != null) network.check();
      }),
    );
  }

  @override
  void dispose() {
    widget.controller.controlsVisible = previousControls;
    network.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, network]),
    builder: (context, _) {
      final c = widget.controller, n = network, p = AppPalette.of(context);
      String yes(Object? value) => value == true
          ? 'Ready'
          : value == false
          ? 'Not ready'
          : 'Not checked';
      final fields = <String, String>{
        'Device': c.deviceDisplayName,
        'Bluetooth radio': switch (c.radioState) {
          RadioState.ready => 'Ready',
          RadioState.off => 'Off',
          RadioState.unauthorized => 'Permission needed',
          RadioState.unavailable => 'Unavailable',
          _ => 'Starting',
        },
        'Control route': c.adaptive?.routeLabel ?? 'Bluetooth',
        'Bluetooth link': c.adaptive == null
            ? c.phase.name
            : c.adaptive!.bleConnected
            ? 'Connected · retained for fallback'
            : 'Reconnecting',
        if (c.adaptive?.policy.rssi != null)
          'Live Bluetooth signal': '${c.adaptive!.policy.rssi} dBm',
        if (c.adaptive?.policy.bleMs != null)
          'Bluetooth response': '${c.adaptive!.policy.bleMs!.round()} ms',
        if (c.adaptive?.policy.networkMs != null)
          'Network response': '${c.adaptive!.policy.networkMs!.round()} ms',
        if (c.adaptive != null)
          'Automatic connection': c.adaptive!.networkStatus,
        'Live updates': c.notificationsRequested
            ? 'Subscribed'
            : 'Not subscribed',
        'Last reading': c.freshness,
        'Readings received': '${c.receivedCount}',
        'Automatic reconnect': c.automaticReconnect ? 'Enabled' : 'Paused',
        'Reconnect attempt': '${c.retryAttempt}',
        if (c.selected != null &&
            c.selected!.rssi < 0 &&
            c.selected!.rssi > -127)
          'Last scan signal': '${c.selected!.rssi} dBm',
        'Advanced controls': c.connected && !c.stale
            ? c.controls?.settingsAllowed == true
                  ? 'Ready'
                  : 'Check host recovery'
            : 'Last-known state',
        if (n.ready) ...{
          'Network': 'Reachable',
          'Network checked': '${n.checkedAt!.toLocal()}',
          'Network check time':
              '${n.checkTime!.inMilliseconds} ms (includes connection setup)',
          'Host version': '${n.status!['version']}',
          'Host monitoring': yes(n.status!['monitoring']),
          'Host Wi-Fi': yes(n.status!['wifi']),
          'Controls helper': yes(n.status!['helper']),
          'Recovery status':
              '${n.status!['recovery_status'] ?? 'Not reported'}',
          'Recovery enabled': n.status!['recovery_enabled'] == true
              ? 'Yes'
              : 'No',
          'Recovery pairing': yes(n.status!['recovery_paired']),
          'Recovery permission': yes(n.status!['recovery_permission']),
          'Locator Stop overlay': n.status!['overlay_permission'] == true
              ? 'Allowed'
              : 'Optional permission needed',
        },
      };
      final report =
          (c.isDemo ? 'Demo data — no device connected\n' : '') +
          fields.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      return Scaffold(
        appBar: AppBar(title: const Text('Connection health')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            surface(
              copyText: report,
              copyLabel: 'Connection health',
              child: Column(
                children: fields.entries
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                e.key,
                                style: TextStyle(color: p.secondaryText),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(e.value)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            if (c.error != null) notice('Bluetooth', c.error!, warning: true),
            if (c.controlError != null)
              notice('Controls', c.controlError!, warning: true),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: c.isDemo || c.reading || c.busy
                  ? null
                  : c.connected
                  ? c.refresh
                  : c.selected != null
                  ? () => c.connect(c.selected!)
                  : null,
              child: Text(
                c.connected ? 'Refresh readings' : 'Reconnect Bluetooth',
              ),
            ),
            const SizedBox(height: 16),
            if (c.adaptive != null) ...[
              surface(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic connection'),
                  subtitle: const Text(
                    'Uses live Bluetooth signal and response times. Verifies Wi-Fi or your existing VPN before switching, and keeps Bluetooth connected as a fallback. Files and screenshots still require a network connection.',
                  ),
                  value: c.adaptive!.automatic,
                  onChanged: (value) => c.adaptive!.setAutomatic(value),
                ),
              ),
              const SizedBox(height: 16),
            ],
            NetworkConnectionCard(link: n),
            const SizedBox(height: 16),
            surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'If something needs attention',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bluetooth: allow access on this phone and start monitoring on the Thor. Complete pairing prompts on both devices.\n\nNetwork: keep monitoring and network access enabled on the Thor. Use a reachable Wi-Fi or existing VPN address.\n\nAdvanced controls: open Recovery setup on the Thor and check its permission and local pairing.\n\nFrontmost locator Stop: allow display over other apps in Thor Monitor.\n\nLast scan signal is a saved scan measurement, not a live signal reading.',
                  ),
                  TextButton(
                    onPressed: () => openAppSettings(),
                    child: const Text('Open phone settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
