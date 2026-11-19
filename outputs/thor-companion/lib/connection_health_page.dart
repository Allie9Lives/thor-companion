import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_transport.dart';
import 'companion_controller.dart';
import 'network_link.dart';
import 'wifi_page.dart';
import 'diagnostics.dart';
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
  String? backgroundStatus;
  Map<String, dynamic> platformInfo = {};
  bool copying = false;
  static const backgroundChannel = MethodChannel(
    'com.alan.thorCompanion/backgroundRefresh',
  );
  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    previousControls = c.controlsVisible;
    c.controlsVisible = false;
    network = NetworkLink(c);
    unawaited(
      diagnosticChannel
          .invokeMapMethod<String, dynamic>('info', {
            'deviceId': c.selected?.id,
          })
          .then((value) {
            if (mounted && value != null) setState(() => platformInfo = value);
          })
          .catchError((Object _) {}),
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(
        backgroundChannel
            .invokeMethod<String>('status')
            .then((value) {
              if (mounted) setState(() => backgroundStatus = value);
            })
            .catchError((Object _) {}),
      );
    }
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
        'Report time': DateTime.now().toUtc().toIso8601String(),
        if (platformInfo['client'] != null)
          'Client': '${platformInfo['client']}',
        if (platformInfo['phone'] != null) 'Phone': '${platformInfo['phone']}',
        if (platformInfo['os'] != null) 'Phone OS': '${platformInfo['os']}',
        'Device': c.deviceDisplayName,
        'App state': c.appInForeground ? 'Foreground' : 'Background',
        if (platformInfo['bond'] != null)
          'Android system pairing': '${platformInfo['bond']}',
        if (platformInfo['scanPermission'] != null)
          'Nearby scan permission': '${platformInfo['scanPermission']}',
        if (platformInfo['connectPermission'] != null)
          'Nearby connect permission': '${platformInfo['connectPermission']}',
        'Connection setup': c.reading
            ? 'Reading device data'
            : c.initializing
            ? 'Preparing services'
            : c.connected
            ? (c.receivedCount == 0
                  ? 'Connected; first reading unavailable'
                  : 'Readings received')
            : c.phase.name,
        if (c.error != null)
          'Current error': redactConnectionDiagnostic(c.error!),
        if (c.lastFailure != null)
          'Last failure': redactConnectionDiagnostic(c.lastFailure!),
        if (c.lastFailureStage != null) 'Failure stage': c.lastFailureStage!,
        if (c.adaptive?.lastBluetoothError != null)
          'Native Bluetooth error': c.adaptive!.lastBluetoothError!,
        if (c.adaptive?.lastBluetoothErrorAt != null)
          'Native error time': c.adaptive!.lastBluetoothErrorAt!
              .toUtc()
              .toIso8601String(),
        'Pairing repair required': c.pairingRecoveryRequired ? 'Yes' : 'No',
        'Bluetooth radio': switch (c.radioState) {
          RadioState.ready => 'Ready',
          RadioState.off => 'Off',
          RadioState.unauthorized => 'Permission needed',
          RadioState.unavailable => 'Unavailable',
          _ => 'Starting',
        },
        if (c.adaptive?.knownNetworkHosts.isNotEmpty == true)
          'Saved network addresses': c.adaptive!.knownNetworkHosts.join(' · '),
        'Control route': c.adaptive?.routeLabel ?? 'Bluetooth',
        'Bluetooth link': c.adaptive == null
            ? c.phase.name
            : c.adaptive!.bleConnected
            ? c.receivedCount == 0
                  ? 'Connected · awaiting first reading'
                  : 'Connected · retained for fallback'
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
        'Automatic reconnect': c.automaticReconnect
            ? (c.pairingRecoveryRequired
                  ? 'Paused for pairing repair'
                  : 'Enabled')
            : 'Off in settings',
        ...?(backgroundStatus == null
            ? null
            : {'Background App Refresh': backgroundStatus!}),
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
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WifiPage(controller: c),
                ),
              ),
              icon: const Icon(Icons.wifi),
              label: const Text('Device Wi-Fi'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.copy_outlined),
              label: Text(copying ? 'Copying…' : 'Copy connection report'),
              onPressed: copying
                  ? null
                  : () async {
                      setState(() => copying = true);
                      final events = await connectionEventReport();
                      await Clipboard.setData(
                        ClipboardData(
                          text: '$report\n\nRecent connection events\n$events',
                        ),
                      );
                      if (context.mounted) {
                        setState(() => copying = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Connection report copied'),
                          ),
                        );
                      }
                    },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Includes phone details, errors and recent connection events. Review before sharing.',
                style: TextStyle(fontSize: 14),
              ),
            ),
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
            if (backgroundStatus != null) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Background App Refresh settings'),
                onPressed: () =>
                    backgroundChannel.invokeMethod<void>('settings'),
              ),
              const SizedBox(height: 16),
            ],
            if (c.adaptive != null) ...[
              surface(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic connection'),
                  subtitle: const Text(
                    'Uses Wi-Fi or your existing VPN whenever the device answers on it, and keeps Bluetooth connected as a fallback. Bluetooth is still used for pairing, changing the device’s Wi-Fi and background alerts.',
                  ),
                  value: c.adaptive!.automatic,
                  onChanged: (value) => c.adaptive!.setAutomatic(value),
                ),
              ),
              const SizedBox(height: 16),
            ],
            NetworkConnectionCard(link: n, showAdvanced: true),
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
                    'Bluetooth: allow access on this phone and start monitoring on the device. Complete pairing prompts on both devices.\n\nNetwork: keep monitoring and network access enabled on the device. Use a reachable Wi-Fi or existing VPN address.\n\nAdvanced controls: open Recovery setup on the device and check its permission and local pairing.\n\nFrontmost locator Stop: allow display over other apps in Thor Monitor.\n\nLast scan signal is a saved scan measurement, not a live signal reading.',
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
