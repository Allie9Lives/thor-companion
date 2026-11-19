import 'dart:convert';

/// A handheld this phone has paired with. One is active at a time; the others
/// keep their Wi-Fi/VPN credentials in a native per-device slot.
class SavedDevice {
  const SavedDevice(this.id, this.name, {this.product, this.screens = 2});
  final String id, name;
  final String? product;
  final int screens;

  /// Native credential slot name: letters and digits only (BLE ids contain ':' or '-').
  String get slot {
    final s = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (s.isEmpty) return 'device';
    return s.length > 64 ? s.substring(0, 64) : s;
  }

  SavedDevice copyWith({String? name, String? product, int? screens}) =>
      SavedDevice(
        id,
        name ?? this.name,
        product: product ?? this.product,
        screens: screens ?? this.screens,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    if (product != null) 'product': product,
    'screens': screens,
  };

  static SavedDevice? fromMap(Object? raw) {
    if (raw is! Map || raw['id'] is! String || (raw['id'] as String).isEmpty) {
      return null;
    }
    return SavedDevice(
      raw['id'] as String,
      raw['name'] is String ? raw['name'] as String : 'Handheld',
      product: raw['product'] is String ? raw['product'] as String : null,
      screens: raw['screens'] == 1 ? 1 : 2,
    );
  }
}

List<SavedDevice> decodeDevices(String? text) {
  if (text == null) return [];
  try {
    final list = jsonDecode(text);
    if (list is! List) return [];
    final seen = <String>{};
    return [
      for (final item in list.map(SavedDevice.fromMap))
        if (item != null && seen.add(item.id)) item,
    ];
  } catch (_) {
    return [];
  }
}

String encodeDevices(List<SavedDevice> devices) =>
    jsonEncode([for (final d in devices) d.toMap()]);

/// Adds [device] or updates the entry with its id, keeping list order.
List<SavedDevice> upsertDevice(List<SavedDevice> devices, SavedDevice device) {
  final i = devices.indexWhere((d) => d.id == device.id);
  if (i < 0) return [...devices, device];
  return [...devices]..[i] = device;
}
