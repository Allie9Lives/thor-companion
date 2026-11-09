import Foundation
import Security

struct BatterySnapshot: Codable, Hashable {
  let percent: Int
  let updatedAt: Date
  let charging: Bool
  let connected: Bool

  // SF Symbols supplies quarter-filled batteries. Round to the nearest level;
  // the numeric percentage and Home Screen ring retain the exact reading.
  var levelSymbol: String {
    let level = min(100, max(0, percent))
    return "battery.\(min(100, ((level + 12) / 25) * 25))"
  }

  var fraction: Double { Double(min(100, max(0, percent))) / 100 }

  func isFresh(at date: Date) -> Bool {
    connected && max(0, date.timeIntervalSince(updatedAt)) <= 90
  }
}

enum BatteryStore {
  private static var query: [String: Any] {
    var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "ThorBatterySnapshot", kSecAttrAccount as String: "current"]
    if let group = Bundle.main.object(forInfoDictionaryKey: "ThorSharedKeychainGroup") as? String {
      q[kSecAttrAccessGroup as String] = group
    }
    return q
  }

  static func read() -> BatterySnapshot? {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data, let value = try? JSONDecoder().decode(BatterySnapshot.self, from: data),
      (0...100).contains(value.percent) else { return nil }
    return value
  }

  static func write(_ snapshot: BatterySnapshot?) throws {
    if snapshot == nil {
      let status = SecItemDelete(query as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound { throw failure(status) }
      return
    }
    let data = try JSONEncoder().encode(snapshot!)
    let attributes = [kSecValueData as String: data]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      // Makes the explicitly requested battery widget readable while locked,
      // after the phone has been unlocked once since boot. No credentials stored.
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(item as CFDictionary, nil)
    }
    if status != errSecSuccess { throw failure(status) }
  }

  private static func failure(_ status: OSStatus) -> NSError {
    NSError(domain: "ThorBatteryStore", code: Int(status), userInfo: [
      NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Battery cache unavailable"])
  }
}

#if os(iOS)
import ActivityKit

@available(iOS 16.2, *)
struct ThorBatteryAttributes: ActivityAttributes {
  typealias ContentState = BatterySnapshot
  let name: String
}
#endif
