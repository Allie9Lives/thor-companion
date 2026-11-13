import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'companion_controller.dart';
import 'app_icons.dart';
import 'ui.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({
    super.key,
    required this.controller,
    this.initialTarget = 'top',
  });
  final CompanionController controller;
  final String initialTarget;
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  List<Map<String, dynamic>> apps = [], opened = [];
  final search = TextEditingController();
  late AppIconCache icons;
  String target = 'top';
  String? error, openError, active;
  bool loading = false, previousControls = false, openKnown = false;
  Timer? timer;
  Future<void>? openRequest;
  @override
  void initState() {
    super.initState();
    target = widget.initialTarget == 'bottom' ? 'bottom' : 'top';
    icons = AppIconCache(widget.controller.selected?.id ?? 'preview');
    previousControls = widget.controller.controlsVisible;
    widget.controller.controlsVisible = false;
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!loading && active == null && widget.controller.connected) {
        unawaited(refreshOpen());
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    icons.close();
    search.dispose();
    widget.controller.controlsVisible = previousControls;
    super.dispose();
  }

  Future<void> refreshOpen({bool force = false}) async {
    if (openRequest != null) {
      await openRequest;
      if (!force || !mounted) return;
    }
    final done = Completer<void>();
    openRequest = done.future;
    try {
      final next = await widget.controller.installedApps(openOnly: true);
      if (mounted) {
        setState(() {
          opened = next;
          openKnown = true;
          openError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          openKnown = false;
          openError = e is StateError
              ? e.message
              : 'Open-app status unavailable. Check the Thor connection.';
        });
      }
    } finally {
      openRequest = null;
      done.complete();
    }
  }

  Future<void> load() async {
    if (loading || active != null) return;
    icons.close();
    icons = AppIconCache(widget.controller.selected?.id ?? 'preview');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.controller.installedApps();
      if (!mounted) return;
      setState(() => apps = next);
      await refreshOpen(force: true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Couldn’t load apps. Check the Thor connection.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<int> screens(Map<String, dynamic> app) =>
      (app['displays'] as List? ?? []).whereType<int>().toList();
  String screenLabel(Map<String, dynamic> app) {
    final values = screens(app);
    return values.contains(0) && values.contains(4)
        ? 'Open on both screens'
        : values.contains(4)
        ? 'Open on Bottom screen'
        : 'Open on Top screen';
  }

  String existingTarget(Map<String, dynamic> app) {
    final values = screens(app);
    return values.contains(target == 'top' ? 0 : 4)
        ? target
        : values.contains(0)
        ? 'top'
        : 'bottom';
  }

  Future<void> run(
    Map<String, dynamic> app, {
    bool close = false,
    String? screen,
  }) async {
    if (active != null || loading) return;
    final name = '${app['name']}', package = '${app['p']}';
    if (close) {
      if (!openKnown || app['can_stop'] != true) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Stop $name?'),
          content: const Text('Unsaved progress may be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Stop app'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      active = package;
      error = null;
    });
    try {
      await widget.controller.appAction(
        package,
        target: screen ?? target,
        close: close,
      );
      await refreshOpen(force: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              close
                  ? '$name stopped'
                  : '$name is on the ${screen ?? target} screen',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Couldn’t open the app. Check the Thor connection.',
        );
      }
    } finally {
      if (mounted) setState(() => active = null);
    }
  }

  Widget tile(Map<String, dynamic> app, {required bool isOpen}) {
    final palette = AppPalette.of(context), package = '${app['p']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: surface(
        padding: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: FutureBuilder<Uint8List?>(
              future: icons.get(package, app['icon'] as String?),
              builder: (context, snapshot) {
                final fallback = Text(
                  ('${app['name']}'.isEmpty
                          ? '?'
                          : '${app['name']}'.characters.first)
                      .toUpperCase(),
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                  ),
                );
                return snapshot.data == null
                    ? fallback
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          snapshot.data!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                      );
              },
            ),
          ),
          title: Text(
            '${app['name']}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            isOpen ? screenLabel(app) : package,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: active != null || loading
              ? null
              : () => run(app, screen: isOpen ? existingTarget(app) : target),
          trailing: active == package
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : PopupMenuButton<String>(
                  tooltip: '${app['name']} options',
                  enabled: active == null && !loading,
                  onSelected: (choice) => run(
                    app,
                    close: choice == 'close',
                    screen: choice == 'close' ? null : choice,
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'top',
                      child: Text('Show on Top screen'),
                    ),
                    const PopupMenuItem(
                      value: 'bottom',
                      child: Text('Show on Bottom screen'),
                    ),
                    if (isOpen && openKnown && app['can_stop'] == true)
                      const PopupMenuItem(
                        value: 'close',
                        child: Text('Stop app'),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.toLowerCase();
    bool matches(Map<String, dynamic> app) =>
        '${app['name']} ${app['p']}'.toLowerCase().contains(query);
    final openPackages = opened.map((app) => app['p']).toSet(),
        openRows = opened.where(matches).toList();
    final others = apps
        .where((app) => !openPackages.contains(app['p']) && matches(app))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps on your Thor'),
        actions: [
          IconButton(
            tooltip: 'Refresh app list',
            onPressed: loading || active != null ? null : load,
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
                const Text(
                  'Open apps on',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'top',
                      icon: Icon(Icons.monitor),
                      label: Text('Top'),
                    ),
                    ButtonSegment(
                      value: 'bottom',
                      icon: Icon(Icons.monitor_outlined),
                      label: Text('Bottom'),
                    ),
                  ],
                  selected: {target},
                  onSelectionChanged: active != null
                      ? null
                      : (choice) => setState(() => target = choice.single),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search apps',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          if (error != null) ...[
            notice('Apps', error!, warning: true),
            const SizedBox(height: 12),
          ],
          if (loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          const Text(
            'Open apps',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          const Text('Tap to switch. Use the menu to move or stop.'),
          const SizedBox(height: 12),
          if (openError != null) ...[
            notice('Open apps', openError!, warning: true),
            const SizedBox(height: 12),
          ],
          for (final app in openRows) tile(app, isOpen: true),
          if (!loading && openRows.isEmpty)
            Text(
              query.isEmpty
                  ? 'No open launcher apps.'
                  : 'No matching open apps.',
            ),
          const SizedBox(height: 18),
          Text(
            opened.isEmpty ? 'Installed apps' : 'Other apps',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final app in others) tile(app, isOpen: false),
          if (!loading && others.isEmpty) const Text('No matching apps.'),
          const SizedBox(height: 16),
          const Text(
            'Icons are cached on this phone.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
