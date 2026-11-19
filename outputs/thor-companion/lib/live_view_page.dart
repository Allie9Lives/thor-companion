import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'companion_controller.dart';
import 'file_transfer.dart';
import 'gamepad_overlay.dart';
import 'network_link.dart';
import 'ui.dart';

const _live = MethodChannel('com.alan.thorCompanion/live');
const _awake = MethodChannel('com.alan.thorCompanion/screenshots');

/// Maps a point in the shown video to the 0–10000 range the Thor expects.
(int, int) liveFraction(Offset point, Size box) => (
  (point.dx / box.width * 10000).round().clamp(0, 10000),
  (point.dy / box.height * 10000).round().clamp(0, 10000),
);

/// Which screens a focus shows: 0 top, 1 bottom, 2 both.
List<int> liveScreens(int focus) => focus == 2 ? const [0, 1] : [focus];

class _Feed {
  int? texture;
  Size? size;
  StreamSubscription<List<int>>? stream;
}

class LiveViewPage extends StatefulWidget {
  const LiveViewPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<LiveViewPage> createState() => _LiveViewPageState();
}

class _LiveViewPageState extends State<LiveViewPage>
    with WidgetsBindingObserver {
  late final NetworkLink network;
  int focus = 0;
  bool pad = false, starting = false, immersive = false, full = false;
  final feeds = {0: _Feed(), 1: _Feed()};
  String? error, inputError;
  LivePad? livePad;
  int _attempt = 0;
  Offset? panStart, panLast;
  DateTime? panAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _live.setMethodCallHandler((call) async {
      final args = call.arguments as Map;
      final feed = feeds[args['id']];
      if (!mounted || feed == null) return;
      if (call.method == 'size') {
        setState(
          () => feed.size = Size(
            (args['width'] as num).toDouble(),
            (args['height'] as num).toDouble(),
          ),
        );
      } else if (call.method == 'reset' && feed.stream != null) {
        unawaited(start());
      }
    });
    network = NetworkLink(widget.controller);
    unawaited(
      network.restore().then((_) async {
        if (!mounted || network.connection == null) return;
        await network.check();
        if (mounted && network.ready) await start();
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(stop());
    if (state == AppLifecycleState.resumed && network.ready) unawaited(start());
  }

  Future<void> start() async {
    final attempt = ++_attempt;
    await stop(keepTextures: true);
    if (!mounted || attempt != _attempt) return;
    setState(() {
      starting = true;
      error = null;
      for (final f in feeds.values) {
        f.size = null;
      }
    });
    try {
      final shown = liveScreens(focus);
      for (final hidden in feeds.keys.where((s) => !shown.contains(s))) {
        if (feeds[hidden]!.texture == null) continue;
        feeds[hidden]!.texture = null;
        await _live.invokeMethod<void>('stop', {'id': hidden});
      }
      for (final screen in shown) {
        final feed = feeds[screen]!;
        // A fresh decoder per stream: a reused one never re-reports its size
        // and can mix the old stream's last bytes into the new one.
        feed.texture = await _live.invokeMethod<int>('start', {'id': screen});
        final response = await network.transport!.liveStream(screen);
        if (!mounted || attempt != _attempt) {
          await response.listen(null).cancel();
          return;
        }
        feed.stream = response.listen(
          (chunk) => _live.invokeMethod<void>('feed', {
            'id': screen,
            'data': chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
          }),
          onError: (_) => _ended('The live view stopped. Check the network.'),
          onDone: () => _ended('The live view ended.'),
          cancelOnError: true,
        );
      }
      try {
        await _awake.invokeMethod<void>('keepAwake', true);
      } catch (_) {}
      // Touch, Back and Home use this channel too, so it opens with the video.
      await _openPad();
    } catch (e) {
      if (mounted && attempt == _attempt) {
        setState(
          () => error = e is StateError
              ? e.message
              : e is SocketException || e is HandshakeException
              ? 'Could not reach the device over the network.'
              : 'Could not start the live view.',
        );
      }
    } finally {
      if (mounted && attempt == _attempt) setState(() => starting = false);
    }
  }

  Future<void> _openPad() async {
    livePad?.close();
    livePad = null;
    try {
      livePad = await network.transport!.livePad();
    } catch (_) {
      if (mounted) {
        setState(() => inputError = 'Could not open the controller channel.');
      }
    }
  }

  void _ended(String message) {
    if (mounted) setState(() => error = message);
  }

  Future<void> stop({bool keepTextures = false}) async {
    livePad?.close();
    livePad = null;
    for (final entry in feeds.entries) {
      final feed = entry.value;
      final s = feed.stream;
      feed.stream = null;
      await s?.cancel();
      if (!keepTextures && feed.texture != null) {
        feed.texture = null;
        try {
          await _live.invokeMethod<void>('stop', {'id': entry.key});
        } catch (_) {}
      }
    }
    try {
      await _awake.invokeMethod<void>('keepAwake', false);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attempt++;
    _live.setMethodCallHandler(null);
    unawaited(stop());
    if (immersive) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    network.dispose();
    super.dispose();
  }

  Future<void> send(
    int screen,
    int action, {
    Offset? from,
    Offset? to,
    Size? box,
    int? ms,
  }) async {
    int? x, y, x2, y2;
    if (from != null && box != null) (x, y) = liveFraction(from, box);
    if (to != null && box != null) (x2, y2) = liveFraction(to, box);
    final channel = livePad;
    if (channel != null && !channel.closed && channel.error == null) {
      channel.input(screen, action, {
        'x': ?x,
        'y': ?y,
        'x2': ?x2,
        'y2': ?y2,
        'ms': ?ms,
      });
      if (inputError != null) setState(() => inputError = null);
      return;
    }
    // Older Thor Monitor without the input channel: use the control channel.
    final message = await widget.controller.sendRemoteInput(
      screen == 0 ? 'top' : 'bottom',
      action,
      x: x,
      y: y,
      x2: x2,
      y2: y2,
      ms: ms,
    );
    if (mounted) setState(() => inputError = message);
  }

  /// Back and Home act on the single focused screen, or the bottom launcher in Both.
  int get keyScreen => focus == 2 ? 1 : focus;

  Widget video(int screen) {
    final feed = feeds[screen]!, size = feed.size;
    if (feed.texture == null || size == null) {
      return AspectRatio(
        aspectRatio: screen == 0 ? 16 / 9 : 31 / 27,
        child: Center(
          child: starting
              ? const CircularProgressIndicator()
              : Text(
                  error ?? 'Waiting for the device…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final area = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            onTapUp: (d) => send(screen, 0, from: d.localPosition, box: area),
            onPanStart: (d) {
              panStart = panLast = d.localPosition;
              panAt = DateTime.now();
            },
            onPanUpdate: (d) => panLast = d.localPosition,
            onPanEnd: (_) {
              final from = panStart, to = panLast, at = panAt;
              if (from == null || to == null || at == null) return;
              final ms = DateTime.now()
                  .difference(at)
                  .inMilliseconds
                  .clamp(50, 3000);
              send(screen, 1, from: from, to: to, box: area, ms: ms);
            },
            child: Semantics(
              label:
                  'Live view of the device ${screen == 0 ? 'top' : 'bottom'} screen. Tap or drag to control it.',
              child: Texture(textureId: feed.texture!),
            ),
          );
        },
      ),
    );
  }

  /// Both screens stack like the Thor when upright and sit side by side when sideways.
  Widget screens(bool landscape) {
    final shown = liveScreens(focus);
    if (shown.length == 1) return Center(child: video(shown.single));
    return Flex(
      direction: landscape ? Axis.horizontal : Axis.vertical,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final s in shown) ...[
          if (s == 1) const SizedBox(width: 4, height: 4),
          Flexible(child: Center(child: video(s))),
        ],
      ],
    );
  }

  void setFocus(int value) {
    setState(() => focus = value);
    if (network.ready) unawaited(start());
  }

  Widget focusPicker() => SegmentedButton<int>(
    segments: const [
      ButtonSegment(value: 0, label: Text('Top')),
      ButtonSegment(value: 1, label: Text('Bottom')),
      ButtonSegment(value: 2, label: Text('Both')),
    ],
    selected: {focus},
    showSelectedIcon: false,
    onSelectionChanged: (choice) => setFocus(choice.single),
  );

  Future<void> togglePad() async {
    setState(() => pad = !pad);
    if (pad && network.ready && (livePad == null || livePad!.closed)) {
      await _openPad();
      if (mounted) setState(() {});
    }
  }

  GamepadOverlay overlay() => GamepadOverlay(
    onButton: (key, down) => livePad?.button(key, down),
    onAxes: (axes) => livePad?.axes(axes),
  );

  String? get inputProblem => livePad?.error ?? inputError;

  List<Widget> actions({Color? color}) => [
    IconButton(
      tooltip: pad ? 'Hide controller' : 'Show controller',
      onPressed: togglePad,
      color: color,
      icon: Icon(pad ? Icons.videogame_asset : Icons.videogame_asset_outlined),
    ),
    IconButton(
      tooltip: 'Back',
      onPressed: () => send(keyScreen, 2),
      color: color,
      icon: const Icon(Icons.arrow_back),
    ),
    IconButton(
      tooltip: 'Home',
      onPressed: () => send(keyScreen, 3),
      color: color,
      icon: const Icon(Icons.home_outlined),
    ),
    IconButton(
      tooltip: 'Restart',
      onPressed: network.ready && !starting ? start : null,
      color: color,
      icon: const Icon(Icons.refresh),
    ),
    if (MediaQuery.orientationOf(context) == Orientation.portrait)
      IconButton(
        tooltip: full ? 'Exit full screen' : 'Full screen',
        onPressed: () => setState(() => full = !full),
        color: color,
        icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen),
      ),
  ];

  void setImmersive(bool value) {
    if (immersive == value) return;
    immersive = value;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  /// Full screen: always when sideways, and on request when upright.
  Widget fullView(bool landscape) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(child: SafeArea(child: screens(landscape))),
        if (pad) Positioned.fill(child: SafeArea(child: overlay())),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (landscape)
                    IconButton(
                      tooltip: 'Close live view',
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  PopupMenuButton<int>(
                    tooltip: 'Screens',
                    iconColor: Colors.white,
                    icon: const Icon(Icons.splitscreen_outlined),
                    initialValue: focus,
                    onSelected: setFocus,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 0, child: Text('Top')),
                      PopupMenuItem(value: 1, child: Text('Bottom')),
                      PopupMenuItem(value: 2, child: Text('Both')),
                    ],
                  ),
                  ...actions(color: Colors.white),
                ],
              ),
            ),
          ),
        ),
        if (inputProblem != null || error != null)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  inputProblem ?? error!,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // No scrolling here: drags on the video must reach the Thor, not the page.
  Widget portraitView() => Scaffold(
    appBar: AppBar(title: const Text('Live view'), actions: actions()),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!network.ready) ...[
            NetworkConnectionCard(link: network, disabled: starting),
            const SizedBox(height: 12),
          ],
          if (!widget.controller.singleScreen) ...[
            focusPicker(),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(color: Colors.black, child: screens(false)),
            ),
          ),
          if (error != null && feeds.values.any((f) => f.size != null)) ...[
            const SizedBox(height: 12),
            notice('Live view', error!, warning: true),
          ],
          if (inputProblem != null) ...[
            const SizedBox(height: 12),
            notice('Input', inputProblem!, warning: true),
          ],
          if (pad) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: Colors.black,
                child: SizedBox(height: 260, child: overlay()),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: network,
    builder: (context, _) {
      final landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      setImmersive(landscape || full);
      return landscape || full ? fullView(landscape) : portraitView();
    },
  );
}
