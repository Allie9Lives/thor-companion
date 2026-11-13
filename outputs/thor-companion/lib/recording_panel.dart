import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'file_transfer.dart';
import 'network_link.dart';
import 'ui.dart';
import 'recording_session.dart';
import 'diagnostics.dart';

const captureBridge = MethodChannel('com.alan.thorCompanion/screenshots');

class RecordingPanel extends StatefulWidget {
  const RecordingPanel({
    super.key,
    required this.network,
    required this.onBusyChanged,
  });
  final NetworkLink network;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<RecordingPanel> createState() => _RecordingPanelState();
}

class _RecordingPanelState extends State<RecordingPanel> {
  Map<String, dynamic>? session;
  int mode = 0, quality = 1, fps = 60;
  bool busy = false,
      polling = false,
      saved = false,
      cancelled = false,
      transferring = false;
  String? error;
  String message = '';
  double? progress;
  Timer? timer;
  final files = <int, File>{};
  bool get recording => session?['state'] == 'recording';
  bool get hasClip => session != null && session!['state'] != 'idle';
  bool get ready =>
      widget.network.ready && widget.network.status?['recording'] == true;
  String get token => session?['token'] as String? ?? '';
  String get screen =>
      const ['top', 'bottom', 'both'][(session?['mode'] as int?) ?? mode];
  String get elapsed {
    final seconds = ((session?['elapsed_ms'] as num? ?? 0) / 1000).floor();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String get savedKey => '${widget.network.connection?.pin ?? ''}:$token';
  @override
  void initState() {
    super.initState();
    widget.network.addListener(networkChanged);
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (ready && !busy && !polling) unawaited(refresh());
    });
    unawaited(restoreOptions());
  }

  Future<void> restoreOptions() async {
    try {
      final store = SharedPreferencesAsync();
      final savedQuality = await store.getInt('recording_quality'),
          savedFps = await store.getInt('recording_fps');
      if (mounted && !hasClip && !busy) {
        setState(() {
          if ([0, 1].contains(savedQuality)) quality = savedQuality!;
          if ([30, 60].contains(savedFps)) fps = savedFps!;
        });
      }
    } catch (_) {}
    if (mounted && ready) await refresh();
  }

  void networkChanged() {
    if (mounted && ready && !busy && !polling) unawaited(refresh());
  }

  Future<void> awake(bool active) async {
    try {
      await captureBridge.invokeMethod<void>('keepAwake', active);
    } catch (_) {}
  }

  void changed() {
    if (mounted) {
      setState(() {});
      widget.onBusyChanged(busy || recording);
    }
  }

  Future<void> apply(Map<String, dynamic> next) async {
    next = validateRecordingStatus(next);
    final prior = token;
    if (prior.isNotEmpty && next['state'] == 'idle') {
      message = saved
          ? 'Saved to Photos · Thor copy removed'
          : 'The temporary recording expired or was removed.';
    }
    session = next;
    if (next['mode'] is int) mode = next['mode'] as int;
    if (next['quality'] is int) quality = next['quality'] as int;
    if (next['fps'] is int) fps = next['fps'] as int;
    if (prior != token || next['state'] == 'idle') {
      saved = false;
      if (token.isNotEmpty) {
        try {
          final ledger =
              await SharedPreferencesAsync().getStringList(
                'saved_capture_sessions',
              ) ??
              [];
          saved = ledger.contains(savedKey);
        } catch (_) {
          saved = false;
        }
      }
    }
    await awake(busy || recording);
    changed();
  }

  Future<void> refresh() async {
    if (!ready || busy || polling) return;
    polling = true;
    try {
      await apply(await widget.network.transport!.recording('status'));
    } catch (_) {
      /* Leave pending clips available for an explicit retry. */
    } finally {
      polling = false;
    }
  }

  Future<void> start() async {
    if (!ready || busy || hasClip) return;
    busy = true;
    error = null;
    message = 'Starting recording…';
    changed();
    try {
      await apply(
        await widget.network.transport!.recording(
          'start',
          mode: mode,
          quality: quality,
          fps: fps,
        ),
      );
      try {
        final store = SharedPreferencesAsync();
        await store.setInt('recording_quality', quality);
        await store.setInt('recording_fps', fps);
      } catch (_) {}
    } catch (e) {
      error = describe(e);
    } finally {
      busy = false;
      message = '';
      changed();
    }
  }

  String describe(Object error) => error is StateError
      ? error.message
      : error is FormatException
      ? error.message
      : error is PlatformException
      ? error.message ?? 'Could not save recording.'
      : 'Could not reach the recording. Check the network and keep the Thor open.';
  Future<void> stopAndSave() async {
    if (!ready || busy) return;
    busy = true;
    error = null;
    cancelled = false;
    progress = null;
    message = recording ? 'Finishing the recording…' : 'Preparing download…';
    changed();
    try {
      await awake(true);
      if (recording) {
        await apply(
          await widget.network.transport!.recording('stop', token: token),
        );
      }
      if (session?['state'] != 'ready') {
        throw StateError(
          session?['error'] as String? ?? 'Recording could not be finalized.',
        );
      }
      if (!saved) {
        final directory = await fileBridge.invokeMethod<String>(
          'cacheDirectory',
        );
        if (directory == null) throw StateError('Recording cache unavailable');
        final tracks =
            (session!['tracks'] as List)
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList()
              ..sort(
                (a, b) => (a['screen'] as int).compareTo(b['screen'] as int),
              );
        final total = tracks.fold<int>(
          0,
          (sum, track) => sum + (track['bytes'] as num).toInt(),
        );
        transferring = true;
        var completed = 0;
        for (final track in tracks) {
          final id = track['screen'] as int,
              size = (track['bytes'] as num).toInt();
          var file = files[id];
          if (file == null ||
              !await file.exists() ||
              await file.length() != size) {
            file = File('$directory/record-$token-$id.mp4');
            files[id] = file;
            message = 'Receiving ${id == 0 ? 'Top' : 'Bottom'} recording…';
            changed();
            await widget.network.transport!.recordingFile(token, id, file, (
              received,
              _,
            ) {
              if (mounted) {
                progress = total == 0 ? null : (completed + received) / total;
                changed();
              }
            });
          }
          completed += size;
        }
        transferring = false;
        progress = null;
        message = screen == 'both' && Platform.isIOS
            ? 'Combining screens and saving to Photos…'
            : 'Saving to Photos…';
        changed();
        await captureBridge.invokeMethod<void>('saveVideo', {
          'paths': [for (final track in tracks) files[track['screen']]!.path],
          'offsets': [
            for (final track in tracks)
              (track['offset_ms'] as num? ?? 0).toDouble(),
          ],
          'screen': screen,
          'fps': fps,
        });
        saved = true;
        try {
          final store = SharedPreferencesAsync(),
              ledger =
                  await SharedPreferencesAsync().getStringList(
                    'saved_capture_sessions',
                  ) ??
                  [];
          ledger.remove(savedKey);
          ledger.add(savedKey);
          await store.setStringList(
            'saved_capture_sessions',
            ledger.skip(ledger.length > 16 ? ledger.length - 16 : 0).toList(),
          );
        } catch (_) {
          /* Photos succeeded; keep this session saved in memory. */
        }
      }
      try {
        await widget.network.transport!.recording('clear', token: token);
        session = {'state': 'idle'};
      } catch (_) {
        message = 'Saved to Photos. Reconnect to remove the Thor copy.';
      }
      if (session?['state'] == 'idle') {
        message = 'Saved to Photos · Thor copy removed';
      }
      for (final file in files.values) {
        try {
          await file.delete();
        } catch (_) {}
      }
      files.clear();
    } catch (e) {
      logBle(
        'Recording save failed: ${e is PlatformException ? "${e.code}: ${e.details}" : e.runtimeType}',
      );
      error = cancelled
          ? 'Transfer cancelled. The Thor copy is still available.'
          : describe(e);
    } finally {
      busy = false;
      transferring = false;
      progress = null;
      await awake(recording);
      changed();
    }
  }

  Future<void> discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard recording?'),
        content: const Text('Deletes the temporary clips from the Thor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !ready || busy) return;
    busy = true;
    changed();
    try {
      await widget.network.transport!.recording('clear', token: token);
      session = {'state': 'idle'};
      saved = false;
      error = null;
      message = '';
      for (final file in files.values) {
        try {
          await file.delete();
        } catch (_) {}
      }
      files.clear();
    } catch (e) {
      error = describe(e);
    } finally {
      busy = false;
      await awake(false);
      changed();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.network.removeListener(networkChanged);
    unawaited(awake(false));
    for (final file in files.values) {
      unawaited(file.delete().then<void>((_) {}, onError: (_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Video recording',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Top')),
            ButtonSegment(value: 1, label: Text('Bottom')),
            ButtonSegment(value: 2, label: Text('Both')),
          ],
          selected: {mode},
          onSelectionChanged: busy || hasClip
              ? null
              : (choice) => setState(() => mode = choice.single),
        ),
        const SizedBox(height: 16),
        const Text(
          'Quality',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Standard')),
            ButtonSegment(value: 1, label: Text('High')),
          ],
          selected: {quality},
          onSelectionChanged: busy || hasClip
              ? null
              : (value) => setState(() => quality = value.single),
        ),
        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: 16),
          const Text(
            'Frame rate',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30 FPS')),
              ButtonSegment(value: 60, label: Text('60 FPS')),
            ],
            selected: {fps},
            onSelectionChanged: busy || hasClip
                ? null
                : (value) => setState(() => fps = value.single),
          ),
        ],
        const SizedBox(height: 16),
        if (!hasClip)
          FilledButton.icon(
            onPressed: ready && !busy ? start : null,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Start recording'),
          ),
        if (recording) ...[
          Text(
            'Recording ${screen == 'both' ? 'both screens' : '$screen screen'} · $elapsed / 3:00',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
        ],
        if (hasClip && session?['state'] != 'failed')
          FilledButton.icon(
            onPressed: ready && !busy ? stopAndSave : null,
            icon: Icon(
              recording
                  ? Icons.stop_circle_outlined
                  : saved
                  ? Icons.delete_outline
                  : Icons.save_alt,
            ),
            label: Text(
              recording
                  ? 'Stop & save'
                  : saved
                  ? 'Remove Thor copy'
                  : 'Save to Photos',
            ),
          ),
        if (hasClip && !busy)
          TextButton(
            onPressed: ready ? discard : null,
            child: const Text('Discard recording'),
          ),
        if (busy) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(message),
          if (transferring)
            TextButton(
              onPressed: () {
                cancelled = true;
                widget.network.cancel();
              },
              child: const Text('Cancel transfer'),
            ),
        ],
        if (!busy && message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message),
          ),
        if ((session?['audio_warning'] as String? ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: notice(
              'Audio',
              session!['audio_warning'] as String,
              warning: true,
            ),
          ),
        if (error != null || session?['state'] == 'failed')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: notice(
              'Recording',
              error ?? session?['error'] as String? ?? 'Recording failed.',
              warning: true,
            ),
          ),
      ],
    ),
  );
}
