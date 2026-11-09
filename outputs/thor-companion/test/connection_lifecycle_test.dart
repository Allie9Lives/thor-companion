import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/connection_lifecycle.dart';

void main() {
  test('cancellation waits for native disconnect acknowledgement', () async {
    final nativeCancel = Completer<void>();
    final source = StreamController<bool>(onCancel: nativeCancel.complete);
    final lifecycle = StreamController<bool>.broadcast();
    var completed = false;
    final sub = settleConnection(
      source: source.stream,
      lifecycle: lifecycle.stream,
      isDisconnected: (connected) => !connected,
      onTimeout: () => fail('Expected disconnect acknowledgement'),
    ).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    lifecycle.add(true);
    source.add(true);
    await Future<void>.delayed(Duration.zero);
    final cancel = sub.cancel().then((_) => completed = true);
    await nativeCancel.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    lifecycle.add(false);
    await cancel;
    expect(completed, isTrue);
    expect(lifecycle.hasListener, isFalse);
    await source.close();
    await lifecycle.close();
  });

  test('an already disconnected link needs no extra acknowledgement', () async {
    final source = StreamController<bool>();
    final lifecycle = StreamController<bool>.broadcast();
    final sub = settleConnection(
      source: source.stream,
      lifecycle: lifecycle.stream,
      isDisconnected: (connected) => !connected,
      onTimeout: () => fail('Link already disconnected'),
    ).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    lifecycle.add(false);
    source.add(false);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(lifecycle.hasListener, isFalse);
    await source.close();
    await lifecycle.close();
  });
}
