import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/focused_apps.dart';
import 'package:thor_companion/apps_page.dart';
import 'package:thor_companion/ftp_page.dart';
import 'controls_test.dart' show ControlBle;

class DesktopBle extends ControlBle {
  Map<String, dynamic>? response;
  bool ftp = false;
  @override
  Future<List<int>> read(String id, String characteristic) async =>
      characteristic == controlId && response != null
      ? utf8.encode(jsonEncode(response))
      : super.read(id, characteristic);
  @override
  Future<void> writeControl(String id, List<int> bytes) async {
    final command = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final key = command['set'];
    if ([
      'apps',
      'apps_open',
      'app_open',
      'app_close',
      'ftp_start',
      'ftp_stop',
      'ftp_status',
    ].contains(key)) {
      commands.add(command);
      writes++;
      response = {'ack': command['id'], 'error': ''};
      if (key == 'apps') {
        final first = command['value'] == 0;
        response!.addAll({
          'apps': [
            if (first)
              {'p': 'com.example.first', 'name': 'First app'}
            else
              {'p': 'com.example.second', 'name': 'Second app'},
          ],
          'next': first ? 1 : -1,
        });
      } else if (key == 'apps_open') {
        response!.addAll({
          'apps': [
            {
              'p': 'com.example.first',
              'name': 'First app',
              'displays': [4],
              'can_stop': true,
            },
          ],
          'next': -1,
        });
      } else if ('$key'.startsWith('ftp_')) {
        if (key == 'ftp_start') ftp = true;
        if (key == 'ftp_stop') ftp = false;
        response!.addAll({
          'running': ftp,
          'allowed': true,
          if (ftp) ...{
            'user': 'thor',
            'password': 'test-session-only',
            'port': 47221,
            'hosts': ['192.0.2.1'],
            'pin': 'test fingerprint',
          },
        });
      }
      return;
    }
    response = null;
    await super.writeControl(id, bytes);
  }
}

void main() {
  test(
    'app list paginates and app actions preserve package and selected screen',
    () async {
      final ble = DesktopBle();
      final controller = CompanionController(
        transport: ble,
        rememberDevice: false,
      );
      await controller.connect(const NearbyThor('thor', 'Thor', -50));
      ble.links.add(LinkState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final apps = await controller.installedApps();
      expect(apps.map((app) => app['name']), ['First app', 'Second app']);
      await controller.appAction('com.example.second', target: 'bottom');
      final command = ble.commands.last;
      expect(command['set'], 'app_open');
      expect(command['target'], 'bottom');
      expect(command['value'], 'com.example.second');
      await expectLater(
        controller.appAction('com.example.app;reboot', target: 'top'),
        throwsArgumentError,
      );
      await controller.appAction(
        'com.example.first',
        target: 'top',
        close: true,
      );
      expect(ble.commands.last['set'], 'app_close');
      controller.dispose();
      await ble.close();
    },
  );
  testWidgets('drawer separates open apps and hides Stop for closed apps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ble = DesktopBle();
    final c = CompanionController(transport: ble, rememberDevice: false);
    await c.connect(const NearbyThor('thor', 'Thor', -50));
    ble.links.add(LinkState.connected);
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: AppsPage(controller: c, initialTarget: 'bottom'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First app'), findsOneWidget);
    expect(find.text('Second app'), findsOneWidget);
    expect(find.text('Open on Bottom screen'), findsOneWidget);
    await tester.tap(find.byTooltip('Second app options'));
    await tester.pumpAndSettle();
    expect(find.text('Stop app'), findsNothing);
    await tester.tap(find.text('Show on Bottom screen'));
    await tester.pumpAndSettle();
    expect(
      ble.commands.where((e) => e['set'] == 'app_open').last['target'],
      'bottom',
    );
    await tester.tap(find.byTooltip('First app options'));
    await tester.pumpAndSettle();
    expect(find.text('Stop app'), findsOneWidget);
    await tester.tap(find.text('Stop app'));
    await tester.pumpAndSettle();
    expect(find.text('Stop First app?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ble.commands.where((e) => e['set'] == 'app_close'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await ble.close();
  });
  testWidgets('tapping each focused screen selects that drawer target', (
    tester,
  ) async {
    final targets = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusedApps(
            apps: const [
              {'d': 0, 'name': 'Top app'},
              {'d': 4, 'name': 'Bottom app'},
            ],
            onOpenDrawer: targets.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('focused-top-screen')));
    await tester.tap(find.byKey(const ValueKey('focused-bottom-screen')));
    expect(targets, ['top', 'bottom']);
  });
  testWidgets(
    'focused screens retain top/bottom mapping even when bottom arrives first',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FocusedApps(
              apps: [
                {'d': 4, 'name': 'Bottom app', 'cpu': 2},
                {'d': 0, 'name': 'Top app', 'cpu': 1},
              ],
            ),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('focused-top-screen')),
          matching: find.text('Top app'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('focused-bottom-screen')),
          matching: find.text('Bottom app'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Top app')).dy,
        lessThan(tester.getTopLeft(find.text('Bottom app')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'FTP starts and stops without exposing saved credentials after stop',
    (tester) async {
      final ble = DesktopBle();
      final c = CompanionController(transport: ble, rememberDevice: false);
      await c.connect(const NearbyThor('thor', 'Thor', -50));
      ble.links.add(LinkState.connected);
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(MaterialApp(home: FtpServerPage(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start server'));
      await tester.pumpAndSettle();
      expect(find.text('Server running'), findsOneWidget);
      expect(find.text('••••••••••••'), findsOneWidget);
      expect(find.text('test-session-only'), findsNothing);
      await tester.tap(find.text('Stop server'));
      await tester.pumpAndSettle();
      expect(find.text('Server stopped'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await ble.close();
    },
  );
}
