import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/recording_session.dart';

void main() {
  Map<String, dynamic> fixture() => {
    'state': 'ready',
    'token': 'a' * 24,
    'mode': 2,
    'tracks': [
      for (final screen in [0, 1])
        <String, dynamic>{
          'screen': screen,
          'bytes': 1024,
          'offset_ms': screen * 40,
          'duration_ms': 2500,
          'width': 1280,
          'height': 720,
        },
    ],
  };
  test('accepts finalized dual recordings and idle cleanup', () {
    expect(validateRecordingStatus(fixture())['state'], 'ready');
    expect(validateRecordingStatus({'state': 'idle', 'token': 'old'}), {
      'state': 'idle',
    });
  });
  test('rejects duplicate screens, malformed token and unbounded clips', () {
    final duplicate = fixture();
    (duplicate['tracks'] as List)[1]['screen'] = 0;
    expect(() => validateRecordingStatus(duplicate), throwsFormatException);
    final token = fixture()..['token'] = '../../clip';
    expect(() => validateRecordingStatus(token), throwsFormatException);
    for (final entry in {
      'bytes': 513 * 1024 * 1024,
      'duration_ms': 200000,
      'width': 9999,
      'offset_ms': double.nan,
    }.entries) {
      final next = fixture();
      (next['tracks'] as List)[0][entry.key] = entry.value;
      expect(() => validateRecordingStatus(next), throwsFormatException);
    }
  });
}
