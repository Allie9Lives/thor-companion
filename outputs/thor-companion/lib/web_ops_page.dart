import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'companion_controller.dart';
import 'design_components.dart';
import 'ui.dart';
import 'network_link.dart';

class WebOpsPage extends StatefulWidget {
  const WebOpsPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<WebOpsPage> createState() => _WebOpsPageState();
}

class _WebOpsPageState extends State<WebOpsPage> {
  Map<String, dynamic>? status;
  String? error;
  bool busy = false, opening = false;
  Timer? timer;
  bool get running => ((status?['svc'] as int? ?? 0) & 2) != 0;
  bool get configured => ((status?['svc'] as int? ?? 0) & 8) != 0;
  @override
  void initState() {
    super.initState();
    unawaited(action('web_ops_status'));
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy && widget.controller.connected) {
        unawaited(action('web_ops_status', silent: true));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> action(String name, {bool silent = false}) async {
    if (busy || widget.controller.isDemo) return;
    busy = true;
    if (!silent) setState(() => error = null);
    try {
      final next = await widget.controller.hostServiceAction(name);
      if (mounted) setState(() => status = next);
    } catch (e) {
      if (mounted && !silent) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Could not reach Web Ops. Try again.',
        );
      }
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> open(String address) async {
    try {
      await const MethodChannel(
        'com.alan.thorCompanion/about',
      ).invokeMethod<void>('webOps', address);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the browser. Copy the address instead.',
            ),
          ),
        );
      }
    }
  }

  Future<void> openAutomatically() async {
    if (opening) return;
    setState(() {
      opening = true;
      error = null;
    });
    final network = NetworkLink(widget.controller);
    try {
      await network.restore();
      if (network.connection == null) await network.linkBluetooth();
      await network.check();
      if (!network.ready) {
        throw StateError(network.error ?? 'Could not reach Web Ops.');
      }
      if (mounted) {
        await open(
          Uri(
            scheme: 'https',
            host: network.host,
            port: 47184,
            path: '/',
          ).toString(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is StateError ? e.message : 'Could not reach Web Ops.',
        );
      }
    } finally {
      network.dispose();
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = (status?['urls'] as List? ?? []).whereType<String>().toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Web Ops')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading('Web Ops', Icons.web_outlined),
                const SizedBox(height: 16),
                Text(
                  running
                      ? 'Running'
                      : status == null
                      ? 'Checking status…'
                      : 'Stopped',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Use your device from a browser over Wi-Fi or a private VPN.',
                ),
                const SizedBox(height: 16),
                if (status != null && !configured)
                  const Text(
                    'Set an owner login in Thor Monitor → Settings → Web Ops.',
                  ),
                FilledButton.icon(
                  onPressed:
                      busy ||
                          !widget.controller.connected ||
                          widget.controller.isDemo ||
                          (!running && !configured)
                      ? null
                      : () =>
                            action(running ? 'web_ops_stop' : 'web_ops_start'),
                  icon: Icon(
                    running ? Icons.stop_circle_outlined : Icons.play_arrow,
                  ),
                  label: Text(running ? 'Stop Web Ops' : 'Start Web Ops'),
                ),
                if (running) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: opening ? null : openAutomatically,
                    icon: const Icon(Icons.open_in_browser),
                    label: Text(
                      opening ? 'Finding connection…' : 'Open Web Ops',
                    ),
                  ),
                ],
                if (busy || opening)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: notice('Web Ops', error!, warning: true),
                  ),
              ],
            ),
          ),
          if (urls.isNotEmpty)
            ExpansionTile(
              title: const Text('Addresses'),
              children: [
                for (final url in urls) ...[
                  const SizedBox(height: 12),
                  surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          url,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    Clipboard.setData(ClipboardData(text: url)),
                                icon: const Icon(Icons.copy_outlined),
                                label: const Text('Copy'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => open(url),
                                icon: const Icon(Icons.open_in_browser),
                                label: const Text('Open'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          if (urls.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Trust the device’s certificate in your browser. Export it from Thor Monitor → Web Ops.',
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy ? null : () => action('web_ops_status'),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
