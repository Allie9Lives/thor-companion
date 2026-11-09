import 'dart:convert';

// Fit each complete JSON write within the existing 180-byte BLE protocol,
// including worst-case request ID and escaping. Never split a UTF-16 pair.
List<String> splitKeyboardText(String text) {
  if (text.isEmpty) throw const FormatException('Enter some text first.');
  if (text.runes.length > 2000) {
    throw const FormatException('Send up to 2,000 characters at a time.');
  }
  if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text)) {
    throw const FormatException(
      'This text contains unsupported control characters.',
    );
  }
  final chunks = <String>[];
  var chunk = '';
  for (final rune in text.runes) {
    final next = chunk + String.fromCharCode(rune);
    final packet = utf8.encode(
      jsonEncode({'id': 'x' * 32, 'set': 'text', 'value': next}),
    );
    if (utf8.encode(next).length > 120 || packet.length > 180) {
      chunks.add(chunk);
      chunk = String.fromCharCode(rune);
    } else {
      chunk = next;
    }
  }
  if (chunk.isNotEmpty) chunks.add(chunk);
  return chunks;
}
