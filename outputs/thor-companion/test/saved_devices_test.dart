import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/saved_devices.dart';
import 'package:thor_companion/telemetry.dart';

void main() {
  test('device list round-trips, dedupes and upserts in place', () {
    var list = [
      const SavedDevice('AA:BB:CC:DD:EE:FF', 'Device', product: 'AYN Thor Max'),
    ];
    list = upsertDevice(
      list,
      const SavedDevice('1234-abcd', 'Retroid', screens: 1),
    );
    list = upsertDevice(list, list.first.copyWith(name: 'Living room device'));
    final again = decodeDevices(encodeDevices(list));
    expect(again.map((d) => d.name), ['Living room device', 'Retroid']);
    expect(again.last.screens, 1);
    expect(again.first.product, 'AYN Thor Max');
    expect(
      decodeDevices(
        '[{"id":"x","name":"a"},{"id":"x","name":"b"},3,{}]',
      ).map((d) => d.name),
      ['a'],
    );
    expect(decodeDevices('not json'), isEmpty);
  });

  test('native credential slots are alphanumeric and bounded', () {
    expect(const SavedDevice('AA:BB:CC:DD:EE:FF', '').slot, 'AABBCCDDEEFF');
    expect(
      const SavedDevice('0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0', '').slot,
      '0F1E2D3C4B5A69788796A5B4C3D2E1F0',
    );
    expect(const SavedDevice('::', '').slot, 'device');
    expect(SavedDevice('a' * 80, '').slot.length, 64);
  });

  test('hardware reports product and screen count; old hosts are Thors', () {
    final retroid = DeviceHardware.fromBytes(
      utf8.encode(
        jsonEncode({
          'model': 'Retroid Pocket Classic',
          'product': 'Retroid Pocket Classic',
          'family': 'retroid',
          'screens': 1,
          'variant': '6 GB',
          'storage_capacity_bytes': 64000000000,
        }),
      ),
    );
    expect(retroid.screens, 1);
    expect(retroid.displayModel, 'Retroid Pocket Classic 6 GB');
    expect(retroid.storageConfiguration, '64 GB');
    final oldThor = DeviceHardware.fromBytes(
      utf8.encode(jsonEncode({'model': 'AYN Thor', 'variant': 'Max'})),
    );
    expect(oldThor.screens, 2);
    expect(oldThor.displayModel, 'AYN Thor Max');
  });
  test('storage type and marketed card size', () {
    final emmc = DeviceHardware.fromBytes(
      utf8.encode(
        jsonEncode({'storage_standard': 'eMMC 5.1', 'ufs_version': 'unknown'}),
      ),
    );
    expect(emmc.storageLabel, 'eMMC 5.1');
    final oldUfs = DeviceHardware.fromBytes(
      utf8.encode(jsonEncode({'ufs_version': '4.0'})),
    );
    expect(oldUfs.storageLabel, 'UFS 4.0');
    expect(cardSize(255858704384), '256 GB');
    expect(cardSize(1000204886016), '1 TB');
    expect(cardSize(100000000000), isNull);
  });
}
