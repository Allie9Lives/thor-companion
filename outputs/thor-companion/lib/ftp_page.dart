import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'companion_controller.dart';
import 'ui.dart';

class FtpServerPage extends StatefulWidget {
  const FtpServerPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<FtpServerPage> createState() => _FtpServerPageState();
}

class _FtpServerPageState extends State<FtpServerPage> {
  Map<String, dynamic>? status;
  String? error;
  bool busy = false, revealPassword = false, previousControls = false;
  Timer? timer;
  Completer<void>? polling;
  bool get running => status?['running'] == true;
  @override
  void initState() {
    super.initState();
    previousControls = widget.controller.controlsVisible;
    widget.controller.controlsVisible = false;
    unawaited(action('ftp_status'));
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy && widget.controller.connected) {
        unawaited(action('ftp_status', silent: true));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.controller.controlsVisible = previousControls;
    super.dispose();
  }

  Future<void> action(String command, {bool silent = false}) async {
    if (busy || (silent && polling != null)) return;
    final previousPoll = polling?.future;
    if (silent) {
      polling = Completer<void>();
    } else {
      setState(() {
        busy = true;
        error = null;
      });
      await previousPoll;
      if (!mounted) return;
    }
    try {
      final next = await widget.controller.ftpAction(command);
      if (mounted) {
        setState(() {
          status = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Could not reach the FTP server. Connect to an updated Thor Monitor and try again.',
        );
      }
    } finally {
      if (silent) {
        polling?.complete();
        polling = null;
      } else if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label copied')));
    }
  }

  Widget detail(String title, String value, {bool secret = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 3),
              SelectableText(
                secret && !revealPassword ? '••••••••••••' : value,
                style: const TextStyle(fontSize: 17),
              ),
            ],
          ),
        ),
        if (secret)
          IconButton(
            tooltip: revealPassword ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => revealPassword = !revealPassword),
            icon: Icon(
              revealPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        IconButton(
          tooltip: 'Copy $title',
          onPressed: () => copy(title, value),
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final hosts = (status?['hosts'] as List? ?? [])
        .whereType<String>()
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('FTP server'),
        actions: [
          IconButton(
            tooltip: 'Refresh server status',
            onPressed: busy ? null : () => action('ftp_status'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      running
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        running ? 'Server running' : 'Server stopped',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Encrypted file transfers over Wi-Fi or VPN.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      busy ||
                          !widget.controller.connected ||
                          widget.controller.isDemo
                      ? null
                      : () => action(running ? 'ftp_stop' : 'ftp_start'),
                  icon: Icon(
                    running ? Icons.stop_circle_outlined : Icons.play_arrow,
                  ),
                  label: Text(running ? 'Stop server' : 'Start server'),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (error != null) ...[
            notice('FTP server', error!, warning: true),
            const SizedBox(height: 16),
          ],
          if (running)
            surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'FTP client setup',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'File protocol: FTP\nEncryption: TLS/SSL Explicit encryption\nTransfer mode: Passive',
                  ),
                  const SizedBox(height: 12),
                  for (final host in hosts) detail('Host address', host),
                  detail('Port', '${status!['port']}'),
                  detail('Username', '${status!['user']}'),
                  detail('Password', '${status!['password']}', secret: true),
                  detail('Certificate SHA-256', '${status!['pin']}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Verify the certificate fingerprint on first connection. Open /internal or /sd. Restarting the server changes its password.',
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Storage access',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  'In Thor Monitor → Settings → Wi-Fi access, allow Shared storage permission and turn on Share storage roots. Android still protects other apps’ private files.',
                ),
                SizedBox(height: 8),
                Text(
                  'Stops with monitoring or a Thor restart. Active transfers keep the Thor awake.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
