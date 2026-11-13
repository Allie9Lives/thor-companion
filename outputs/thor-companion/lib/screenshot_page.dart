import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'companion_controller.dart';
import 'diagnostics.dart';
import 'screenshot_transfer.dart';
import 'ui.dart';
import 'network_link.dart';
import 'recording_panel.dart';

Future<Uint8List> composeScreenshot(Uint8List container, int mode) async {
  final images = screenshotImages(container, mode);
  if (mode != 2) return images[mode]!;
  final topCodec = await ui.instantiateImageCodec(images[0]!);
  ui.Codec? bottomCodec;
  ui.Image? top, bottom;
  ui.Picture? picture;
  ui.Image? combined;
  try {
    bottomCodec = await ui.instantiateImageCodec(images[1]!);
    top = (await topCodec.getNextFrame()).image;
    bottom = (await bottomCodec.getNextFrame()).image;
    final width = top.width > bottom.width ? top.width : bottom.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0x00000000), BlendMode.src);
    canvas.drawImage(top, Offset((width - top.width) / 2, 0), Paint());
    canvas.drawImage(
      bottom,
      Offset((width - bottom.width) / 2, top.height.toDouble()),
      Paint(),
    );
    picture = recorder.endRecording();
    combined = await picture.toImage(width, top.height + bottom.height);
    final bytes = await combined.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not stitch screenshots.');
    return bytes.buffer.asUint8List();
  } finally {
    topCodec.dispose();
    bottomCodec?.dispose();
    top?.dispose();
    bottom?.dispose();
    picture?.dispose();
    combined?.dispose();
  }
}

const _screenshots = MethodChannel('com.alan.thorCompanion/screenshots');
Future<void> saveScreenshot(Uint8List png, String screen) =>
    _screenshots.invokeMethod<void>('save', {'png': png, 'screen': screen});

class ScreenshotPage extends StatefulWidget {
  const ScreenshotPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<ScreenshotPage> createState() => _ScreenshotPageState();
}

class _ScreenshotPageState extends State<ScreenshotPage> {
  late final NetworkLink network;
  @override
  void initState() {
    super.initState();
    network = NetworkLink(widget.controller);
    unawaited(
      network.restore().then((_) {
        if (mounted && network.connection != null) network.check();
      }),
    );
  }

  int mode = 0, captureKind = 0;
  bool videoBusy = false;
  bool busy = false, saved = false, cancelled = false;
  double? progress;
  int lastProgressPaint = 0;
  Uint8List? image;
  String? error;
  String status = '';
  String get screen => const ['top', 'bottom', 'both'][mode];
  Future<void> keepAwake(bool value) async {
    try {
      await _screenshots.invokeMethod<void>('keepAwake', value);
    } catch (_) {}
  }

  @override
  void dispose() {
    network.dispose();
    unawaited(keepAwake(false));
    super.dispose();
  }

  Future<void> capture() async {
    setState(() {
      busy = true;
      saved = false;
      image = null;
      error = null;
      status = 'Capturing over Wi-Fi…';
      cancelled = false;
      progress = null;
    });
    try {
      await keepAwake(true);
      if (!network.ready) {
        throw StateError('Check the Wi-Fi connection before capturing.');
      }
      final raw = await network.transport!
          .capture(mode, (received, total) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (mounted && now - lastProgressPaint > 100) {
              lastProgressPaint = now;
              setState(() {
                progress = received / total;
                status = 'Receiving over Wi-Fi…';
              });
            }
          })
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              network.cancel();
              throw StateError(
                'Screenshot timed out. Check Wi-Fi and try again.',
              );
            },
          );
      await keepAwake(false);
      if (!mounted) return;
      setState(() {
        status = 'Preparing image…';
      });
      final png = await composeScreenshot(raw, mode);
      if (!mounted) return;
      setState(() {
        image = png;
        status = 'Saving to Photos…';
      });
      await saveScreenshot(png, screen);
      logBle('Screenshot saved on client: screen=$screen bytes=${png.length}');
      if (mounted) {
        setState(() {
          saved = true;
          status = 'Saved to Photos';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = cancelled
              ? 'Screenshot cancelled.'
              : e is PlatformException
              ? e.message
              : e is StateError
              ? e.message
              : 'Could not transfer the screenshot over Wi-Fi. Check the connection and keep the Thor open and unlocked.';
        });
      }
    } finally {
      await keepAwake(false);
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> retrySave() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await saveScreenshot(image!, screen);
      if (mounted) {
        setState(() {
          saved = true;
          status = 'Saved to Photos';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is PlatformException
              ? e.message
              : 'Could not save screenshot.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, network]),
    builder: (context, _) {
      final c = widget.controller;
      final enabled =
          network.ready &&
          network.status!['wifi'] == true &&
          network.status!['helper'] == true &&
          network.status!['capture'] == true &&
          !c.isDemo;
      return Scaffold(
        appBar: AppBar(title: const Text('Screen capture')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Save screenshots or recordings from your Thor to Photos.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              NetworkConnectionCard(link: network, disabled: busy || videoBusy),
              if (network.ready &&
                  (network.status!['helper'] != true ||
                      network.status!['wifi'] != true)) ...[
                const SizedBox(height: 12),
                notice(
                  'Screenshot setup',
                  network.status!['wifi'] != true
                      ? 'Connect the Thor to Wi-Fi.'
                      : 'Advanced controls are unavailable. Check Recovery setup on the Thor.',
                  warning: true,
                ),
              ],
              const SizedBox(height: 20),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.photo_camera_outlined),
                    label: Text('Screenshot'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.videocam_outlined),
                    label: Text('Video'),
                  ),
                ],
                selected: {captureKind},
                onSelectionChanged: busy || videoBusy
                    ? null
                    : (choice) => setState(() => captureKind = choice.single),
              ),
              const SizedBox(height: 20),
              if (captureKind == 1)
                RecordingPanel(
                  network: network,
                  onBusyChanged: (value) {
                    if (mounted && videoBusy != value) {
                      setState(() => videoBusy = value);
                    }
                  },
                ),
              if (captureKind == 0) ...[
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Top')),
                    ButtonSegment(value: 1, label: Text('Bottom')),
                    ButtonSegment(value: 2, label: Text('Both')),
                  ],
                  selected: {mode},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() {
                          mode = v.single;
                          image = null;
                          saved = false;
                          error = null;
                          status = '';
                        }),
                ),
                const SizedBox(height: 12),
                if (mode == 2)
                  const Text(
                    'Top above bottom, centered at their original resolution.',
                    style: TextStyle(fontSize: 14),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: enabled && !busy ? capture : null,
                  icon: const Icon(Icons.screenshot_monitor),
                  label: const Text('Capture & save'),
                ),
                if (busy) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(
                    progress == null
                        ? status
                        : 'Receiving ${(progress! * 100).round()}% over Wi-Fi',
                  ),
                  TextButton(
                    onPressed: () {
                      cancelled = true;
                      network.cancel();
                    },
                    child: const Text('Cancel transfer'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  notice('Screenshot', error!, warning: true),
                ],
                if (saved) ...[const SizedBox(height: 16), Text(status)],
                if (image != null) ...[
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(image!, fit: BoxFit.contain),
                  ),
                  if (!saved && !busy) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: retrySave,
                      child: const Text('Save to Photos'),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                const Text(
                  'Screenshots use the encrypted network connection. Keep the Thor open and unlocked. Images are saved on this device.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
