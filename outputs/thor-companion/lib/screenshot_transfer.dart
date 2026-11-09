import 'dart:async';
import 'dart:typed_data';

const maxScreenshotBytes = 12 * 1024 * 1024;
bool isScreenshotPacket(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 84 &&
    bytes[1] == 83 &&
    bytes[2] == 48 &&
    bytes[3] == 49;

final _crcTable = List<int>.generate(256, (value) {
  var crc = value;
  for (var i = 0; i < 8; i++) {
    crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
  }
  return crc;
});
int screenshotCrc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = (crc >>> 8) ^ _crcTable[(crc ^ byte) & 0xff];
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

class ScreenshotReceiver {
  ScreenshotReceiver(this.token, int length, this.crc, this.progress)
    : bytes = Uint8List(
        length > 0 && length <= maxScreenshotBytes
            ? length
            : throw const FormatException('Invalid screenshot size.'),
      );
  final int token, crc;
  final Uint8List bytes;
  final void Function(double) progress;
  final done = Completer<Uint8List>();
  int received = 0;
  Timer? _idle;
  void start() => _resetIdle();
  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(
      const Duration(seconds: 12),
      () =>
          fail('Screenshot transfer stopped. Try again with the Thor nearby.'),
    );
  }

  void add(List<int> packet) {
    if (done.isCompleted || !isScreenshotPacket(packet)) return;
    try {
      if (packet.length <= 16) {
        throw const FormatException('Incomplete screenshot packet.');
      }
      final p = Uint8List.fromList(packet), data = ByteData.sublistView(p);
      if (data.getUint32(4) != token) {
        return; // Ignore late packets from a cancelled capture.
      }
      final offset = data.getUint32(8),
          total = data.getUint32(12),
          count = packet.length - 16;
      if (total != bytes.length ||
          offset > received ||
          offset + count > bytes.length) {
        throw const FormatException(
          'Screenshot transfer was interrupted. Capture again.',
        );
      }
      if (offset < received) return;
      bytes.setRange(offset, offset + count, p, 16);
      received += count;
      progress(received / bytes.length);
      if (received == bytes.length) {
        _idle?.cancel();
        if (screenshotCrc(bytes) != crc) {
          throw const FormatException(
            'Screenshot integrity check failed. Capture again.',
          );
        }
        done.complete(bytes);
      } else {
        _resetIdle();
      }
    } on FormatException catch (e) {
      fail(e.message);
    }
  }

  void fail(String message) {
    _idle?.cancel();
    if (!done.isCompleted) done.completeError(StateError(message));
  }
}

Map<int, Uint8List> screenshotImages(Uint8List container, int mode) {
  if (container.length < 10 ||
      container[0] != 84 ||
      container[1] != 72 ||
      container[2] != 83 ||
      container[3] != 49) {
    throw const FormatException('Invalid screenshot image.');
  }
  final expected = mode == 2 ? {0, 1} : {mode};
  if (container[4] != expected.length) {
    throw const FormatException('Missing screen image.');
  }
  final result = <int, Uint8List>{};
  var offset = 5;
  final data = ByteData.sublistView(container);
  for (var i = 0; i < container[4]; i++) {
    if (offset + 5 > container.length) {
      throw const FormatException('Incomplete screenshot image.');
    }
    final screen = container[offset], length = data.getUint32(offset + 1);
    offset += 5;
    if (!expected.contains(screen) ||
        result.containsKey(screen) ||
        length < 24 ||
        offset + length > container.length) {
      throw const FormatException('Invalid screen image.');
    }
    final png = Uint8List.sublistView(container, offset, offset + length);
    if (png[0] != 137 || png[1] != 80 || png[2] != 78 || png[3] != 71) {
      throw const FormatException('Screen image is not PNG.');
    }
    final header = ByteData.sublistView(png);
    final width = header.getUint32(16), height = header.getUint32(20);
    if (width < 1 || height < 1 || width > 4096 || height > 4096) {
      throw const FormatException('Unsupported image dimensions.');
    }
    result[screen] = png;
    offset += length;
  }
  if (offset != container.length) {
    throw const FormatException('Unexpected screenshot data.');
  }
  return result;
}
