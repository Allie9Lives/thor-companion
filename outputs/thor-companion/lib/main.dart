import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble_transport.dart';
import 'adaptive_transport.dart';
import 'battery_widget.dart';
import 'package:flutter/services.dart';
import 'companion_controller.dart';
import 'dashboard.dart';
import 'controls.dart';
import 'ui.dart';
import 'settings_sheet.dart';
import 'about_page.dart';
import 'battery_pages.dart';
import 'files_page.dart';
import 'connection_health_page.dart';

void main() => runApp(ThorCompanionApp());

class ThorCompanionApp extends StatefulWidget {
  const ThorCompanionApp({
    super.key,
    this.controller,
    this.initialThemeMode = ThemeMode.system,
    this.initialAppearance,
  });
  final CompanionController? controller;
  final ThemeMode initialThemeMode;
  final AppAppearance? initialAppearance;
  @override
  State<ThorCompanionApp> createState() => _ThorCompanionAppState();
}

class _ThorCompanionAppState extends State<ThorCompanionApp> {
  late CompanionController controller;
  AppAppearance appearance = AppAppearance.system;
  bool get ownsController => widget.controller == null;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? createController();
    appearance =
        widget.initialAppearance ??
        appearanceFromName(widget.initialThemeMode.name);
    if (ownsController) unawaited(loadAppearance());
    if (ownsController &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      const channel = MethodChannel('com.alan.thorCompanion/backgroundRefresh');
      channel.setMethodCallHandler((call) async {
        if (call.method == 'refresh') {
          return controller.backgroundRefresh().timeout(
            const Duration(seconds: 23),
            onTimeout: () => false,
          );
        }
        throw MissingPluginException();
      });
      unawaited(channel.invokeMethod<void>('ready'));
    }
  }

  Future<void> loadAppearance() async {
    try {
      final saved = await SharedPreferencesAsync().getString('appearance');
      if (!mounted || saved == null) return;
      setState(() => appearance = appearanceFromName(saved));
    } catch (_) {}
  }

  void setAppearance(AppAppearance mode) {
    setState(() => appearance = mode);
    if (ownsController) unawaited(saveAppearance(mode));
  }

  Future<void> saveAppearance(AppAppearance mode) async {
    try {
      await SharedPreferencesAsync().setString('appearance', mode.name);
    } catch (_) {}
  }

  CompanionController createController() =>
      kIsWeb || const bool.fromEnvironment('THOR_DEMO')
      ? CompanionController.demo()
      : CompanionController(
          transport: AdaptiveTransport(ReactiveBleTransport()),
          backgroundReconnect: defaultTargetPlatform == TargetPlatform.iOS,
        );
  void switchDemo(bool demo) {
    if (!ownsController) return;
    controller.dispose();
    setState(
      () => controller = demo ? CompanionController.demo() : createController(),
    );
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Thor Companion',
    debugShowCheckedModeBanner: false,
    themeMode:
        appearance == AppAppearance.dark ||
            appearance == AppAppearance.clearPurple
        ? ThemeMode.dark
        : appearance == AppAppearance.system
        ? ThemeMode.system
        : ThemeMode.light,
    theme: appTheme(
      Brightness.light,
      appearance: appearance == AppAppearance.rainbow
          ? appearance
          : AppAppearance.light,
    ),
    darkTheme: appTheme(
      Brightness.dark,
      appearance: appearance == AppAppearance.clearPurple
          ? appearance
          : AppAppearance.dark,
    ),
    home: CompanionHome(
      key: ObjectKey(controller),
      controller: controller,
      appearance: appearance,
      onAppearanceChanged: setAppearance,
      onDemo: () => switchDemo(true),
      onExitDemo: kIsWeb ? null : () => switchDemo(false),
    ),
  );
}

class CompanionHome extends StatefulWidget {
  const CompanionHome({
    super.key,
    required this.controller,
    required this.onDemo,
    required this.appearance,
    required this.onAppearanceChanged,
    this.onExitDemo,
  });
  final CompanionController controller;
  final VoidCallback onDemo;
  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final VoidCallback? onExitDemo;
  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome>
    with WidgetsBindingObserver {
  int tab = 0;
  Color get background => AppPalette.of(context).background;
  Color get accent => AppPalette.of(context).accent;
  Color get onAccent => AppPalette.of(context).onAccent;
  Color get secondaryText => AppPalette.of(context).secondaryText;
  CompanionController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.setForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      c.setForeground(false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      bottomNavigationBar: c.stats == null
          ? null
          : NavigationBar(
              backgroundColor: background,
              indicatorColor: accent.withValues(alpha: 0.12),
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard),
                  label: 'Overview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.developer_board_outlined),
                  selectedIcon: Icon(Icons.developer_board),
                  label: 'Device',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune),
                  label: 'Controls',
                ),
              ],
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 620),
            child: RefreshIndicator(
              onRefresh: c.refresh,
              child: ListView(
                key: PageStorageKey(
                  c.stats == null ? 'setup-scroll' : 'tab-scroll-$tab',
                ),
                padding: EdgeInsets.fromLTRB(24, 18, 24, 24),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 25,
                            height: 25,
                            child: CustomPaint(
                              painter: HandheldPainter(color: onAccent),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Thor Companion',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Appearance and settings',
                        onPressed: settings,
                        icon: Icon(
                          Icons.settings_outlined,
                          color: secondaryText,
                          size: 23,
                        ),
                      ),
                    ],
                  ),
                  if (AppPalette.of(context).isRainbow) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Row(
                        children: AppPalette.of(context).rainbowColors
                            .map(
                              (color) => Expanded(
                                child: Container(height: 3, color: color),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                  if (c.isDemo) ...[
                    SizedBox(height: 18),
                    notice(
                      'Demo data',
                      'No device connected.',
                      trailing: widget.onExitDemo == null
                          ? null
                          : TextButton(
                              onPressed: widget.onExitDemo,
                              child: Text('Exit'),
                            ),
                    ),
                  ],
                  if (c.error != null) ...[
                    SizedBox(height: 18),
                    notice('Connection', c.error!, warning: true),
                  ],
                  if (c.retryAt != null) ...[
                    SizedBox(height: 12),
                    notice(
                      'Reconnecting',
                      'Retrying in ${c.retryAt!.difference(DateTime.now()).inSeconds.clamp(0, 60)} s.',
                    ),
                  ],
                  SizedBox(height: 26),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(c.stats == null ? 'setup' : 'tab-$tab'),
                    tween: Tween(begin: .94, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    builder: (context, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                    child: c.stats == null
                        ? setup()
                        : tab == 0
                        ? Dashboard(controller: c)
                        : tab == 1
                        ? DevicePage(controller: c)
                        : ControlsPage(controller: c),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget setup() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(height: 18),
      Text(
        'Connect your Thor',
        style: TextStyle(
          fontSize: 30,
          height: 1.06,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
        ),
      ),
      SizedBox(height: 16),
      Text(
        'View battery and storage information over Bluetooth.',
        style: TextStyle(color: secondaryText, fontSize: 16),
      ),
      SizedBox(height: 30),
      surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Setup',
              style: TextStyle(
                fontSize: 14,
                letterSpacing: 0,
                color: secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 20),
            step(
              '01',
              'Start monitoring',
              'Start a monitoring session in the Thor app.',
            ),
            SizedBox(height: 18),
            step(
              '02',
              'Enable Bluetooth',
              'Turn on Bluetooth on both devices.',
            ),
            SizedBox(height: 18),
            step('03', 'Pair the devices', 'Confirm pairing on both devices.'),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.busy || c.reading
                    ? null
                    : () => c.connected
                          ? c.refresh()
                          : c.phase == CompanionPhase.scanning
                          ? c.stopScan()
                          : c.startScan(),
                icon: c.busy || c.reading || c.phase == CompanionPhase.scanning
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: background,
                        ),
                      )
                    : Icon(Icons.bluetooth_searching, size: 20),
                label: Text(
                  c.reading
                      ? 'Reading device…'
                      : c.connected
                      ? 'Refresh'
                      : c.busy
                      ? 'Connecting…'
                      : c.phase == CompanionPhase.scanning
                      ? 'Stop scanning'
                      : 'Find Thor',
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              c.radioMessage,
              style: TextStyle(fontSize: 14, color: secondaryText),
            ),
          ],
        ),
      ),
      if (c.busy || c.connected) ...[
        SizedBox(height: 16),
        notice(
          'Pairing',
          'Keep the Thor open for first pairing. Check its notification shade for a Pairing request.',
        ),
        TextButton(onPressed: c.disconnect, child: Text('Cancel connection')),
      ],
      if (c.remembered != null && !c.busy) ...[
        SizedBox(height: 16),
        surface(
          child: Row(
            children: [
              Icon(Icons.bookmark_border, color: accent),
              SizedBox(width: 12),
              Expanded(child: Text(c.remembered!.name)),
              TextButton(
                onPressed: c.busy ? null : () => c.connect(c.remembered!),
                child: Text('Reconnect'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Saved device options',
                icon: Icon(Icons.more_horiz),
                onSelected: (_) => unawaited(c.forget()),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'forget',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bookmark_remove_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Forget Thor'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (c.nearby.isNotEmpty) ...[
        SizedBox(height: 24),
        Text(
          'Nearby devices',
          style: TextStyle(
            fontSize: 14,
            color: secondaryText,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 12),
        ...c.nearby.values.map(
          (d) => Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: surface(
              child: Row(
                children: [
                  Icon(Icons.sports_esports_outlined, color: accent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name),
                        Text(
                          'Bluetooth · ${d.rssi} dBm',
                          style: TextStyle(color: secondaryText, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: c.busy ? null : () => c.connect(d),
                    child: Text('Connect'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      SizedBox(height: 20),
      TextButton(
        onPressed: widget.onDemo,
        child: Text('View demo', style: TextStyle(color: secondaryText)),
      ),
    ],
  );
  Widget step(String number, String title, String description) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        number,
        style: TextStyle(
          color: accent.withValues(alpha: 0.6),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
            SizedBox(height: 3),
            Text(
              description,
              style: TextStyle(color: secondaryText, fontSize: 14),
            ),
          ],
        ),
      ),
    ],
  );

  void settings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * .9,
      ),
      child: SettingsSheet(
        controller: c,
        appearance: widget.appearance,
        onAppearanceChanged: widget.onAppearanceChanged,
        onAction: (action) {
          Navigator.pop(sheetContext);
          switch (action) {
            case 'widgets':
              widgetHelp();
            case 'files':
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FilesPage(controller: c),
                ),
              );
            case 'alerts':
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BatteryAlertsPage(controller: c),
                ),
              );
            case 'insights':
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BatteryInsightsPage(controller: c),
                ),
              );
            case 'health':
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConnectionHealthPage(controller: c),
                ),
              );
            case 'help':
              help();
            case 'about':
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutPage()),
              );
            case 'credits':
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sound credits'),
                  content: const SelectableText(
                    'Tranquility by Helton Yan and Roberto Araujo.\nhttps://heltonyan.itch.io/tranquility\nCC BY 4.0 — https://creativecommons.org/licenses/by/4.0/\nModified: single-variation extraction, conversion, trimming, normalization and fades.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
          }
        },
      ),
    ),
  );
  void widgetHelp() {
    String? status;
    var working = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) {
          Future<void> live(bool enabled) async {
            updateSheet(() => working = true);
            try {
              await setLiveBattery(enabled);
              if (!context.mounted) return;
              updateSheet(
                () => status = enabled
                    ? 'Live battery started. Lock your iPhone to see it.'
                    : 'Live battery stopped.',
              );
            } on PlatformException catch (e) {
              if (context.mounted) {
                updateSheet(
                  () => status = e.message ?? 'Could not change Live battery.',
                );
              }
            } finally {
              if (context.mounted) updateSheet(() => working = false);
            }
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Battery widgets',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Live battery',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Shows incoming battery readings on the Lock Screen and Dynamic Island. The Thor must be monitoring. iOS limits each Live Activity to eight hours.',
                    style: TextStyle(color: secondaryText, height: 1.5),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: working ? null : () => live(true),
                      child: Text('Start live battery'),
                    ),
                  ),
                  TextButton(
                    onPressed: working ? null : () => live(false),
                    child: Text('Stop live battery'),
                  ),
                  if (status != null) ...[SizedBox(height: 8), Text(status!)],
                  SizedBox(height: 20),
                  Text(
                    'Home & Lock Screen widgets',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Home Screen: long-press → Edit → Add Widget → search Thor → add Thor Battery.\n\nLock Screen: long-press your Lock Screen → Customize → Lock Screen → tap the widget area → search Thor → add Thor Battery.\n\nThis widget shows a saved snapshot. “As of” is the snapshot time; iOS may delay its refresh. Use Live battery for more frequent updates.',
                    style: TextStyle(color: secondaryText, height: 1.5),
                  ),
                  if (c.widgetError != null) ...[
                    SizedBox(height: 12),
                    Text(c.widgetError!),
                  ],
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void help() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Connection help',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 18),
            Text(
              'Start monitoring on the Thor, then tap Find Thor and select your device.\n\nFor first pairing, keep the Thor open and confirm the pairing request on both devices. The request may appear in the Thor’s notifications.\n\nIf Bluetooth connects but readings are denied, open Thor Monitor → Settings → Repair phone connection and approve this phone. If iOS says pairing information was removed, forget the Thor in Settings → Bluetooth and connect again.\n\nAutomatic reconnect resumes after interruptions. Disconnect pauses retries. iOS controls background execution; reopen the app if updates pause. Readings are marked out of date after 90 seconds without an update.\n\nAll readings are transferred directly over Bluetooth.',
              style: TextStyle(color: secondaryText, height: 1.6),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Done'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
