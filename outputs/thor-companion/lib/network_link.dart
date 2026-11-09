import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'file_transfer.dart';
import 'ui.dart';

class NetworkLink extends ChangeNotifier {
  NetworkLink(this.controller);
  final CompanionController controller;
  FileConnection? connection;
  ThorFiles? transport;
  String host = '';
  Map<String, dynamic>? status;
  String? error;
  bool busy = false, _disposed = false;
  DateTime? checkedAt;
  Duration? checkTime;
  bool get ready => transport != null && status != null && error == null;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    if (controller.isDemo) return;
    try {
      final j = await fileBridge.invokeMapMethod<String, dynamic>(
        'loadConnection',
      );
      if (!_disposed && j != null) {
        connection = FileConnection.fromMap(j);
        host = connection!.defaultHost;
        changed();
      }
    } catch (_) {}
  }

  Future<void> linkBluetooth() async {
    if (busy) return;
    busy = true;
    error = null;
    changed();
    try {
      final j = await controller.pairFiles();
      if (_disposed) return;
      connection = FileConnection.fromMap(j);
      host = connection!.defaultHost;
      await fileBridge.invokeMethod('saveConnection', connection!.toMap());
      await controller.adaptive?.configure(connection!);
    } catch (e) {
      error = e is StateError
          ? e.message
          : 'Could not link network access. Connect over Bluetooth first.';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> check() async {
    if (controller.isDemo) return;
    if (busy) return;
    busy = true;
    error = null;
    status = null;
    changed();
    try {
      if (connection == null) {
        throw StateError(
          'Link network access over Bluetooth once, then connect over Wi-Fi.',
        );
      }
      transport?.close();
      transport = ThorFiles(connection!, host);
      final watch = Stopwatch()..start();
      final j = await transport!
          .get('status')
          .timeout(const Duration(seconds: 15));
      watch.stop();
      if (_disposed) return;
      if (j['version'] is! String || j['monitoring'] is! bool) {
        throw StateError(
          'Update Thor Monitor to use network health and Wi-Fi screenshots.',
        );
      }
      status = j;
      checkTime = watch.elapsed;
      checkedAt = DateTime.now();
      connection = connection!.usingHost(host.trim());
      await fileBridge.invokeMethod('saveConnection', connection!.toMap());
      await controller.adaptive?.configure(connection!);
    } catch (e) {
      transport?.close();
      transport = null;
      error = e is StateError
          ? e.message
          : e is HandshakeException
          ? 'The Thor identity could not be verified. Link network access again over Bluetooth.'
          : 'Could not reach the Thor. Check Wi-Fi, its address, and any existing VPN connection.';
    } finally {
      busy = false;
      changed();
    }
  }

  void cancel() {
    transport?.close();
    transport = null;
    status = null;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    transport?.close();
    super.dispose();
  }
}

class NetworkConnectionCard extends StatefulWidget {
  const NetworkConnectionCard({
    super.key,
    required this.link,
    this.disabled = false,
  });
  final NetworkLink link;
  final bool disabled;
  @override
  State<NetworkConnectionCard> createState() => _NetworkConnectionCardState();
}

class _NetworkConnectionCardState extends State<NetworkConnectionCard> {
  final address = TextEditingController();
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    address.text = widget.link.host;
    widget.link.addListener(sync);
  }

  void sync() {
    if (!focus.hasFocus && address.text != widget.link.host) {
      address.text = widget.link.host;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.link.removeListener(sync);
    address.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.link;
    return surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Wi-Fi connection',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(n.connection?.name ?? 'Link this phone to your Thor'),
          const SizedBox(height: 8),
          const Text(
            'Uses the Thor’s Wi-Fi address or an existing VPN route. Link once over Bluetooth; images and network checks use the encrypted network connection.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed:
                n.busy ||
                    widget.disabled ||
                    !n.controller.connected ||
                    n.controller.isDemo
                ? null
                : () async {
                    focus.unfocus();
                    await n.linkBluetooth();
                  },
            child: Text(
              n.connection == null
                  ? 'Link network access'
                  : 'Update network link',
            ),
          ),
          if (n.connection != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: address,
              focusNode: focus,
              enabled: !n.busy && !widget.disabled,
              onChanged: (v) => n.host = v,
              decoration: const InputDecoration(
                labelText: 'Thor IP address or hostname',
              ),
            ),
            if (n.connection!.hosts.length > 1)
              Wrap(
                spacing: 8,
                children: n.connection!.hosts
                    .map(
                      (h) => ActionChip(
                        label: Text(h),
                        onPressed: n.busy || widget.disabled
                            ? null
                            : () {
                                address.text = h;
                                n.host = h;
                              },
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: n.busy || widget.disabled
                  ? null
                  : () {
                      n.host = address.text;
                      focus.unfocus();
                      n.check();
                    },
              icon: const Icon(Icons.wifi),
              label: Text(n.busy ? 'Checking…' : 'Check Wi-Fi connection'),
            ),
          ],
          if (n.busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (n.ready) ...[
            const SizedBox(height: 12),
            Text(
              'Network reachable · ${n.checkTime!.inMilliseconds} ms check · ${TimeOfDay.fromDateTime(n.checkedAt!).format(context)}',
              style: TextStyle(color: AppPalette.of(context).accent),
            ),
          ],
          if (n.error != null) ...[
            const SizedBox(height: 12),
            notice('Network', n.error!, warning: true),
          ],
        ],
      ),
    );
  }
}
