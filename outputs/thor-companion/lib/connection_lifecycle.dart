import 'dart:async';

// Cancelling a native BLE request only starts disconnecting. Keep observing
// until the peripheral actually disconnects before allowing the next request.
Stream<T> settleConnection<T>({
  required Stream<T> source,
  required Stream<T> lifecycle,
  required bool Function(T) isDisconnected,
  required void Function() onTimeout,
  Duration timeout = const Duration(seconds: 5),
}) async* {
  var disconnected = false;
  Completer<void>? waiting;
  final observer = lifecycle.listen((event) {
    disconnected = isDisconnected(event);
    if (disconnected && waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
  }, onError: (Object _) {});
  try {
    yield* source;
  } finally {
    if (!disconnected) {
      waiting = Completer<void>();
      await waiting.future.timeout(timeout, onTimeout: onTimeout);
    }
    await observer.cancel();
  }
}
