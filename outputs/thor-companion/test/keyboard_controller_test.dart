import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'controls_test.dart' show ControlBle;

class KeyboardBle extends ControlBle {
  KeyboardBle() {
    state['keyboard'] = true;
    state['keyboard_selected'] = true;
  }
  final input = <Map<String, dynamic>>[];
  bool loseAck = false;
  @override
  Future<void> writeControl(String id, List<int> bytes) async {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(bytes.length, lessThanOrEqualTo(180));
    input.add(j);
    state['ack'] = loseAck ? 'unknown' : j['id'];
    state['error'] = '';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KeyboardBle ble;
  late CompanionController c;
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
  setUp(() async {
    ble = KeyboardBle();
    c = CompanionController(transport: ble, rememberDevice: false);
    await settle();
    await c.connect(const NearbyThor('thor', 'Thor', -50));
    ble.links.add(LinkState.connected);
    await settle();
  });
  tearDown(() async {
    c.dispose();
    await ble.close();
  });
  test(
    'long Unicode text sends in order with unique correlated requests',
    () async {
      final text = 'Hello 👾 — café 中文 " \\ \n' * 20;
      expect(await c.sendKeyboardText(text), isTrue);
      expect(ble.input.length, greaterThan(1));
      expect(ble.input.map((m) => m['value']).join(), text);
      expect(ble.input.map((m) => m['id']).toSet().length, ble.input.length);
      expect(c.keyboardBusy, isFalse);
      expect(c.controlBusy, isFalse);
      expect(c.keyboardError, isNull);
    },
  );
  test(
    'uncertain acknowledgement stops text without retry or replay',
    () async {
      ble.loseAck = true;
      expect(await c.sendKeyboardText('test ' * 100), isFalse);
      expect(ble.input.length, 1);
      expect(c.keyboardError, contains('Check the Thor'));
      await c.refresh();
      expect(ble.input.length, 1);
    },
  );
  test('background or disconnected state never types queued input', () async {
    c.setForeground(false);
    expect(await c.sendKeyboardText('do not send'), isFalse);
    expect(ble.input, isEmpty);
    c.setForeground(true);
    await settle();
    await c.disconnect();
    expect(await c.sendKeyboardKey('enter'), isFalse);
    expect(ble.input, isEmpty);
  });
  test(
    'only allowed keys are sent and blank text never generates a write',
    () async {
      expect(await c.sendKeyboardText(''), isFalse);
      expect(await c.sendKeyboardKey('home'), isFalse);
      expect(ble.input, isEmpty);
      expect(await c.sendKeyboardKey('backspace'), isTrue);
      expect(ble.input.single['set'], 'key');
      expect(ble.input.single['value'], 'backspace');
    },
  );
}
