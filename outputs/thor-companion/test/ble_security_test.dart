import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';

void main() {
  BleSecurityFailure of(String message) =>
      classifyBleSecurityFailure(StateError(message));

  test('Android RxAndroidBle GATT statuses are recognized', () {
    const prefix = 'GATT exception from MAC address XX:XX:XX:XX:XX:XX,';
    expect(
      of(
        '$prefix status 5 (GATT_INSUF_AUTHENTICATION), type BleGattOperation{description=\'CHARACTERISTIC_READ\'}.',
      ),
      BleSecurityFailure.notSecurelyPaired,
    );
    expect(
      of(
        '$prefix status 8 (GATT_INSUF_AUTHORIZATION or GATT_CONN_TIMEOUT), type BleGattOperation{description=\'CHARACTERISTIC_READ\'}.',
      ),
      BleSecurityFailure.notApproved,
    );
    expect(
      of('$prefix status 15 (GATT_INSUF_ENCRYPTION), type read.'),
      BleSecurityFailure.notSecurelyPaired,
    );
    expect(
      of('$prefix status 137 (GATT_AUTH_FAIL), type read.'),
      BleSecurityFailure.notSecurelyPaired,
    );
  });

  test('CoreBluetooth errors are recognized', () {
    expect(
      of('CBATTErrorDomain Code=5 Authentication is insufficient.'),
      BleSecurityFailure.notSecurelyPaired,
    );
    expect(
      of('CBATTErrorDomain Code=8 Authorization is insufficient.'),
      BleSecurityFailure.notApproved,
    );
    expect(
      of('Peer removed pairing information'),
      BleSecurityFailure.pairingRemoved,
    );
  });

  test('ordinary failures are not treated as pairing problems', () {
    expect(of('TimeoutException after 0:00:45'), BleSecurityFailure.none);
    expect(
      of(
        'GATT exception from MAC address X, status 133 (GATT_ERROR), type read.',
      ),
      BleSecurityFailure.none,
    );
  });
}
