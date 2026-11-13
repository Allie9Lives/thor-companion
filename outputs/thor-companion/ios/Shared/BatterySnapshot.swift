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
  private static var installedDefaultGroup: String?

  // A sideloading tool may rewrite signing entitlements without rewriting our
  // custom Info.plist key. Ask Keychain Services for this install's real prefix.
  static func sharedGroup(declared: String?, defaultGroup: String?) -> String? {
    let suffix = "com.alan.thorCompanion.battery"
    if let prefix = defaultGroup?.split(separator: ".").first,
       prefix.count == 10, prefix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
      return "\(prefix).\(suffix)"
    }
    return declared
  }

  private static func defaultGroup() -> String? {
    if let installedDefaultGroup { return installedDefaultGroup }
    let marker: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "ThorBatterySigningPrefix", kSecAttrAccount as String: "installation"]
    var lookup = marker
    lookup[kSecReturnAttributes as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    var status = SecItemCopyMatching(lookup as CFDictionary, &item)
    if status == errSecItemNotFound {
      var add = marker
      add[kSecValueData as String] = Data([1]) // Non-secret marker, no battery or credentials.
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      add[kSecReturnAttributes as String] = true
      status = SecItemAdd(add as CFDictionary, &item)
      if status == errSecDuplicateItem { status = SecItemCopyMatching(lookup as CFDictionary, &item) }
    }
    if status == errSecSuccess,
       let attributes = item as? [String: Any],
       let group = attributes[kSecAttrAccessGroup as String] as? String {
      installedDefaultGroup = group
      return group
    }
    return nil // Retry after unlock; don't cache a locked-keychain failure.
  }

  private static var query: [String: Any] {
    var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "ThorBatterySnapshot", kSecAttrAccount as String: "current"]
    let declared = Bundle.main.object(forInfoDictionaryKey: "ThorSharedKeychainGroup") as? String
    if let group = sharedGroup(declared: declared, defaultGroup: defaultGroup()) {
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
      NSLocalizedDescriptionKey: status == errSecMissingEntitlement ? "The sideloaded app and widget cannot share battery data. Re-sign both with the same shared keychain group and keep the widget extension enabled." : (SecCopyErrorMessageString(status, nil) as String? ?? "Battery cache unavailable")])
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
