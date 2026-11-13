import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'diagnostics.dart';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'file_transfer.dart';
import 'ui.dart';
import 'ftp_page.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  FileConnection? connection;
  ThorFiles? client;
  final host = TextEditingController();
  List<Map<String, dynamic>> roots = [], entries = [];
  String? root, error;
  String folder = '', status = '';
  bool busy = false, previousControls = false;
  double? progress;
  @override
  void initState() {
    super.initState();
    previousControls = widget.controller.controlsVisible;
    widget.controller.controlsVisible = false;
    unawaited(restore());
  }

  Future<void> restore() async {
    if (widget.controller.isDemo) return;
    try {
      final raw = await fileBridge.invokeMapMethod<String, dynamic>(
        'loadConnection',
      );
      if (raw != null && mounted) {
        connection = FileConnection.fromMap(raw);
        host.text = connection!.defaultHost;
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    client?.close();
    host.dispose();
    widget.controller.controlsVisible = previousControls;
    super.dispose();
  }

  Future<void> task(Future<void> Function() run) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await run();
    } catch (e) {
      logBle(
        'Thor Files failed: ${e.runtimeType}${e is PlatformException ? ' code=${e.code} details=${e.details}' : ''}',
      );
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : e is PlatformException
              ? (e.message ?? 'Could not open Files.')
              : 'Could not complete the transfer. Check the network, folder access and available space.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
          status = '';
        });
      }
    }
  }

  Future<void> pair() async {
    await task(() async {
      final j = await widget.controller.pairFiles();
      final next = FileConnection.fromMap(j);
      await fileBridge.invokeMethod('saveConnection', next.toMap());
      connection = next;
      host.text = next.defaultHost;
      root = null;
      entries = [];
      roots = [];
    });
  }

  Future<void> connect() async {
    await task(() async {
      if (connection == null) return;
      client?.close();
      client = ThorFiles(connection!, host.text);
      final j = await client!.get('roots');
      roots = (j['roots'] as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      root = roots.isEmpty ? null : roots.first['id'] as String;
      folder = '';
      if (root != null) await list();
    });
  }

  Future<void> list() async {
    if (client == null || root == null) return;
    entries = [];
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    for (var page = 0; page < 50; page++) {
      final j = await client!.get('list', {
        'root': root!,
        'path': folder,
        'offset': '$offset',
      });
      final rows = (j['entries'] as List).map(
        (r) => Map<String, dynamic>.from(r),
      );
      result.addAll(rows);
      final next = j['next'] as int;
      if (next < 0) {
        entries = result;
        return;
      }
      if (next <= offset) throw StateError('Folder listing did not advance');
      offset = next;
    }
    throw StateError(
      'This folder exceeds 10,000 entries. Open a smaller folder.',
    );
  }

  int lastPaint = 0;
  void update(int done, int total) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (mounted && (now - lastPaint >= 150 || done == total)) {
      lastPaint = now;
      setState(() => progress = total == 0 ? 1 : done / total);
    }
  }

  Future<void> upload() async {
    await task(() async {
      final picked = await fileBridge.invokeMapMethod<String, dynamic>(
        'pickFile',
      );
      if (picked == null) return;
      final file = File(picked['path'] as String);
      try {
        if (entries.any((entry) => entry['name'] == picked['name'])) {
          throw StateError(
            'A file with this name already exists in this folder. Rename the file in Files or choose another destination.',
          );
        }
        if (mounted) setState(() => status = 'Uploading ${picked['name']}');
        await client!.upload(
          root!,
          folder,
          picked['name'] as String,
          file,
          update,
        );
        await list();
      } finally {
        if (await file.exists()) await file.delete();
      }
    });
  }

  Future<void> download(Map<String, dynamic> entry) async {
    await task(() async {
      final dir = await fileBridge.invokeMethod<String>('cacheDirectory');
      final name = entry['name'] as String;
      final file = File(
        '$dir/download-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        if (mounted) setState(() => status = 'Downloading $name');
        await client!.download(
          root!,
          folder.isEmpty ? name : '$folder/$name',
          file,
          update,
        );
        logBle('Thor Files download complete; opening Files export');
        await fileBridge.invokeMethod('saveFile', {
          'path': file.path,
          'name': name,
        });
      } finally {
        if (await file.exists()) await file.delete();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Files')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Transfer files over Wi-Fi or your existing VPN.',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 12),
        surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                connection?.name ?? 'Link your Thor',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose folders or allow shared-storage access in Thor Monitor. Link over Bluetooth once, then connect over Wi-Fi or VPN.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed:
                    busy ||
                        widget.controller.isDemo ||
                        !widget.controller.connected
                    ? null
                    : pair,
                child: Text(
                  connection == null
                      ? 'Link file access over Bluetooth'
                      : 'Update secure connection',
                ),
              ),
              if (connection != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: host,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Thor IP address or hostname',
                    helperText: 'Wi-Fi or VPN address',
                  ),
                ),
                if (connection!.hosts.length > 1)
                  Wrap(
                    spacing: 8,
                    children: connection!.hosts
                        .map(
                          (h) => ActionChip(
                            label: Text(h),
                            onPressed: busy
                                ? null
                                : () => setState(() => host.text = h),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : connect,
                  child: const Text('Connect over network'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FtpServerPage(controller: widget.controller),
            ),
          ),
          icon: const Icon(Icons.dns_outlined),
          label: const Text('FTP server'),
        ),
        const SizedBox(height: 16),
        if (error != null) ...[
          notice('Files', error!, warning: true),
          const SizedBox(height: 12),
        ],
        if (busy) ...[
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(status.isEmpty ? 'Connecting…' : status),
          TextButton(
            onPressed: () => client?.close(),
            child: const Text('Cancel transfer'),
          ),
          const SizedBox(height: 12),
        ],
        if (roots.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: root,
            items: roots
                .map(
                  (r) => DropdownMenuItem(
                    value: r['id'] as String,
                    child: Text(
                      '${r['id'] == 'sd' ? 'microSD' : 'Internal'} · ${r['name']}',
                    ),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) => task(() async {
                    root = value;
                    folder = '';
                    await list();
                  }),
          ),
          const SizedBox(height: 12),
          Text(
            folder.isEmpty ? 'Shared folder' : folder,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || folder.isEmpty
                      ? null
                      : () => task(() async {
                          final parts = folder.split('/')..removeLast();
                          folder = parts.join('/');
                          await list();
                        }),
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Up'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload'),
                ),
              ),
            ],
          ),
          ...entries.map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                e['dir'] == true
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
              ),
              title: Text(e['name'] as String),
              subtitle: e['dir'] == true
                  ? null
                  : Text(
                      e['size'] is num
                          ? '${((e['size'] as num) / 1048576).toStringAsFixed(1)} MB'
                          : 'Size unavailable',
                    ),
              trailing: Icon(
                e['dir'] == true ? Icons.chevron_right : Icons.download,
              ),
              onTap: busy
                  ? null
                  : () => e['dir'] == true
                        ? task(() async {
                            folder = folder.isEmpty
                                ? e['name'] as String
                                : '$folder/${e['name']}';
                            await list();
                          })
                        : download(e),
            ),
          ),
          if (entries.isEmpty && !busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('This folder is empty. Upload a file to add it.'),
            ),
        ] else if (client != null && !busy && error == null)
          const Text(
            'No shared folders. Choose a folder in Thor Monitor, then connect again.',
          ),
        const SizedBox(height: 20),
        const Text(
          'Existing files are never overwritten. Keep this page open during transfers. Internet access without a shared network needs your existing VPN; this app does not configure it.',
          style: TextStyle(fontSize: 14),
        ),
      ],
    ),
  );
}
