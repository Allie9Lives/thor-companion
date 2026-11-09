import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/keyboard_input.dart';

void main() {
  test('Unicode and escaped text stay intact within BLE payload limits', () {
    final text = ('café 👾 中文 👩‍👩‍👧‍👦 \\"\n\t\$() `%s ' * 25);
    final chunks = splitKeyboardText(text);
    expect(chunks.length, greaterThan(1));
    expect(chunks.join(), text);
    for (final chunk in chunks) {
      expect(chunk, isNotEmpty);
      expect(utf8.encode(chunk).length, lessThanOrEqualTo(120));
      expect(
        utf8
            .encode(jsonEncode({'id': 'x' * 32, 'set': 'text', 'value': chunk}))
            .length,
        lessThanOrEqualTo(180),
      );
    }
  });
  test('empty, oversized and unsupported control text fail before sending', () {
    for (final text in ['', 'a' * 2001, 'hello\u0000world']) {
      expect(() => splitKeyboardText(text), throwsFormatException);
    }
  });
}
