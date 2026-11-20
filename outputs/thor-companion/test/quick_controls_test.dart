import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/quick_controls.dart';
import 'package:thor_companion/ui.dart';
import 'package:thor_companion/control_symbol.dart';
import 'package:thor_companion/control_symbol_paths.dart';
import 'package:thor_companion/controls.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/main.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.environment['THOR_QUICK_ICON_PREVIEW'] != null) {
    final loader = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '../../work/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            ).readAsBytes(),
          ),
        ),
      );
    await loader.load();
  }

  testWidgets(
    'nine compact actions keep live modes and toggle/clean behavior',
    (tester) async {
      final actions = <(String, int)>[];
      final values = <String, dynamic>{
        'hz': 60,
        'performance': 0,
        'fan': 4,
        'focus': 0,
        'bypass': 0,
        'vibration': 1,
        'style': 1,
        'led': 1,
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 330,
                child: QuickControls(
                  values: values,
                  enabled: true,
                  onSet: (k, v) => actions.add((k, v)),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(InkWell), findsNWidgets(9));
      for (final key in ['hz', 'fan', 'style', 'clean']) {
        expect(
          tester.getSize(find.byKey(ValueKey('quick-$key'))).width,
          closeTo((330 - 16) / 3, .1),
        );
      }
      await tester.tap(find.byKey(const ValueKey('quick-vibration')));
      await tester.tap(find.byKey(const ValueKey('quick-clean')));
      expect(actions, [('vibration', 0), ('clean', 0)]);
      await tester.tap(find.byKey(const ValueKey('quick-fan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sports'));
      await tester.pumpAndSettle();
      expect(actions.last, ('fan', 5));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('two-option controls cycle without opening a menu', (
    tester,
  ) async {
    final actions = <(String, int)>[];
    final values = <String, dynamic>{
      'hz': 60,
      'bypass': 0,
      'vibration': 1,
      'led': 1,
      'fan': 4,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => QuickControls(
              values: values,
              enabled: true,
              onSet: (k, v) {
                actions.add((k, v));
                update(() => values[k] = v);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('quick-hz')));
    await tester.pumpAndSettle();
    expect(actions.last, ('hz', 120));
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quick-hz')));
    await tester.pumpAndSettle();
    expect(actions.last, ('hz', 60));
    await tester.tap(find.byKey(const ValueKey('quick-bypass')));
    await tester.pumpAndSettle();
    expect(actions.last, ('bypass', 1));
    await tester.tap(find.byKey(const ValueKey('quick-fan')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });
  test('client vector paths match the Web Ops icon source', () {
    final data =
        jsonDecode(
              File(
                '../thor-monitor-prototype/assets/web-ops/control-symbols.json',
              ).readAsStringSync(),
            )
            as Map;
    for (final entry in data.entries) {
      expect(controlSymbolPaths[entry.key], entry.value['paths']);
      expect(
        ControlSymbolPainter.paths[entry.key]!.every(
          (p) => !p.getBounds().isEmpty,
        ),
        true,
      );
    }
  });
  for (final appearance in [
    AppAppearance.dark,
    AppAppearance.light,
    AppAppearance.clearPurple,
    AppAppearance.rainbow,
  ]) {
    testWidgets('unavailable icons remain visible: ${appearance.name}', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.dark, appearance: appearance),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: Container(
                  width: 350,
                  padding: const EdgeInsets.all(12),
                  color: appTheme(
                    Brightness.dark,
                    appearance: appearance,
                  ).extension<AppPalette>()!.card,
                  child: QuickControls(
                    values: const {
                      'vibration': 1,
                      'led': 1,
                      'hz': -1,
                      'performance': -1,
                      'fan': -1,
                      'focus': -1,
                      'bypass': -1,
                      'style': -1,
                    },
                    enabled: false,
                    onSet: (_, _) => fail('disabled'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ControlSymbol), findsNWidgets(9));
      final p = AppPalette.of(tester.element(find.byType(QuickControls)));
      final symbols = tester.widgetList<ControlSymbol>(
        find.byType(ControlSymbol),
      );
      expect(
        symbols.firstWhere((s) => s.name == 'vibration').color,
        p.onAccent,
      );
      expect(symbols.firstWhere((s) => s.name == 'led').color, p.onAccent);
      expect(symbols.firstWhere((s) => s.name == 'fan').color, p.secondaryText);
      final output = Platform.environment['THOR_QUICK_ICON_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output-${appearance.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('demo and unloaded controls show all nine symbols', (
    tester,
  ) async {
    final c = CompanionController.demo();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ControlsPage(controller: c)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ControlSymbol), findsNWidgets(9));
    c.controls = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ControlsPage(key: UniqueKey(), controller: c),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ControlSymbol), findsNWidgets(9));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'large text uses two columns without overflow and disabled actions stay inert',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 300,
                  child: QuickControls(
                    values: const {},
                    enabled: false,
                    onSet: (_, _) => fail('disabled'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<InkWell>(find.byKey(const ValueKey('quick-fan'))).onTap,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('controls the handheld lacks are hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickControls(
            values: const {'vibration': 1, 'screens': 1},
            enabled: true,
            onSet: (_, _) {},
          ),
        ),
      ),
    );
    expect(
      tester
          .widgetList<ControlSymbol>(find.byType(ControlSymbol))
          .map((s) => s.name),
      ['vibration', 'clean'],
    );
  });

  testWidgets('Controls page shows only the controls the handheld reports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(860, 1864);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = CompanionController.demo();
    await tester.pumpWidget(ThorCompanionApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controls').last);
    await tester.pumpAndSettle();
    c.controls = ThorControlState.fromBytes(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'settings': true,
          'screens': 1,
          'fan': 0,
          'style': 1,
          'vibration': 1,
        }),
      ),
    );
    c.notifyListeners();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('quick-clean')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    for (final key in ['fan', 'style', 'vibration', 'clean']) {
      expect(find.byKey(ValueKey('quick-$key')), findsOneWidget, reason: key);
    }
    for (final key in ['hz', 'performance', 'focus', 'bypass', 'led']) {
      expect(find.byKey(ValueKey('quick-$key')), findsNothing, reason: key);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
