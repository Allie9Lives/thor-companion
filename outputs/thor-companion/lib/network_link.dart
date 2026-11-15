import 'dart:async';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'file_transfer.dart';
import 'ui.dart';
import 'network_endpoint.dart';

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
      final next = FileConnection.fromMap(j);
      connection = next
          .withManualHost(
            connection?.pin == next.pin ? connection?.manualHost : null,
          )
          .retainingAddresses(connection);
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
      final saved = await fileBridge.invokeMapMethod<String, dynamic>(
        'loadConnection',
      );
      if (saved != null) {
        final latest = FileConnection.fromMap(saved);
        if (latest.pin == connection!.pin) connection = latest;
      }
      final result = await connectFilesAutomatically(
        connection!,
        cancelled: () => _disposed,
      );
      if (_disposed) {
        result.value.client.close();
        return;
      }
      transport?.close();
      transport = result.value.client;
      host = result.host;
      status = result.value.status;
      checkTime = result.elapsed;
      checkedAt = DateTime.now();
      await controller.adaptive?.configure(connection!);
    } catch (e) {
      error = e is StateError
          ? e.message
          : 'Could not reach the Thor over Wi-Fi or VPN.';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> setManualHost(String value) async {
    final address = value.trim();
    if (connection == null) return;
    if (address.isNotEmpty && !FileConnection.validHost(address)) {
      throw StateError('Enter an IP address or hostname.');
    }
    connection = connection!.withManualHost(address.isEmpty ? null : address);
    await fileBridge.invokeMethod('saveConnection', connection!.toMap());
    await controller.adaptive?.configure(connection!);
    changed();
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
    this.showAdvanced = false,
  });
  final NetworkLink link;
  final bool disabled, showAdvanced;
  @override
  State<NetworkConnectionCard> createState() => _NetworkConnectionCardState();
}

class _NetworkConnectionCardState extends State<NetworkConnectionCard> {
  final address = TextEditingController();
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    address.text = widget.link.connection?.manualHost ?? '';
    widget.link.addListener(sync);
  }

  void sync() {
    final manual = widget.link.connection?.manualHost ?? '';
    if (!focus.hasFocus && address.text != manual) {
      address.text = manual;
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
            'Network connection',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(n.connection?.name ?? 'Link this phone to your Thor'),
          const SizedBox(height: 8),
          const Text('Automatically uses a reachable VPN or local address.'),
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
            if (widget.showAdvanced)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Address override'),
                subtitle: const Text('Automatic by default'),
                children: [
                  TextField(
                    controller: address,
                    focusNode: focus,
                    enabled: !n.busy && !widget.disabled,
                    decoration: const InputDecoration(
                      labelText: 'IP address or hostname',
                      hintText: 'Automatic',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: n.busy
                            ? null
                            : () async {
                                try {
                                  await n.setManualHost(address.text);
                                  focus.unfocus();
                                  await n.check();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '$e'.replaceFirst('Bad state: ', ''),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                        child: const Text('Apply'),
                      ),
                      TextButton(
                        onPressed: n.busy
                            ? null
                            : () async {
                                await n.setManualHost('');
                                address.clear();
                                focus.unfocus();
                                await n.check();
                              },
                        child: const Text('Use automatic'),
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: n.busy || widget.disabled
                  ? null
                  : () {
                      focus.unfocus();
                      n.check();
                    },
              icon: const Icon(Icons.wifi),
              label: Text(n.busy ? 'Checking…' : 'Check connection'),
            ),
          ],
          if (n.busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (n.ready) ...[
            const SizedBox(height: 12),
            Text(
              '${isVpnAddress(n.host) ? 'VPN' : 'Local network'} · ${n.host} · ${n.checkTime!.inMilliseconds} ms',
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
