import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/battery_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Live battery start and stop use the native ActivityKit bridge',
    () async {
      const channel = MethodChannel('com.alan.thorCompanion/batteryWidget');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await setLiveBattery(true);
      await setLiveBattery(false);
      expect(calls, ['startLive', 'stopLive']);
    },
  );
}
