import Foundation

@main
struct BatterySnapshotTests {
  static func main() throws {
    let at = Date(timeIntervalSince1970: 1_700_000_000)
    let value = BatterySnapshot(percent: 69, updatedAt: at, charging: true, connected: true)
    assert(value.isFresh(at: at.addingTimeInterval(89)))
    assert(!value.isFresh(at: at.addingTimeInterval(91)))
    let later = BatterySnapshot(percent: 69, updatedAt: at.addingTimeInterval(30), charging: true, connected: true)
    assert(later != value) // New receive time changes Live Activity content even at the same percentage.
    let offline = BatterySnapshot(percent: 69, updatedAt: at, charging: false, connected: false)
    assert(!offline.isFresh(at: at))
    let roundtrip = try JSONDecoder().decode(BatterySnapshot.self, from: JSONEncoder().encode(value))
    assert(roundtrip.percent == 69 && roundtrip.charging && roundtrip.updatedAt == at)
    for (percent, symbol) in [(0, "battery.0"), (12, "battery.0"), (13, "battery.25"), (37, "battery.25"), (38, "battery.50"), (62, "battery.50"), (63, "battery.75"), (87, "battery.75"), (88, "battery.100"), (100, "battery.100")] {
      let snapshot = BatterySnapshot(percent: percent, updatedAt: at, charging: false, connected: true)
      assert(snapshot.levelSymbol == symbol)
      assert(snapshot.fraction == Double(percent) / 100)
      let charging = BatterySnapshot(percent: percent, updatedAt: at, charging: true, connected: true)
      assert(charging.levelSymbol == symbol) // Charging never falsely fills the battery.
    }
    assert(BatterySnapshot(percent: -1, updatedAt: at, charging: false, connected: true).fraction == 0)
    assert(BatterySnapshot(percent: 101, updatedAt: at, charging: false, connected: true).fraction == 1)
    assert(BatteryStore.sharedGroup(declared: "OLDSIGNER0.com.alan.thorCompanion.battery", defaultGroup: "NEWSIGNER1.com.alan.thorCompanion") == "NEWSIGNER1.com.alan.thorCompanion.battery")
    assert(BatteryStore.sharedGroup(declared: "OLDSIGNER0.com.alan.thorCompanion.battery", defaultGroup: "NEWSIGNER1.com.alan.thorCompanion.ThorBatteryExtension") == "NEWSIGNER1.com.alan.thorCompanion.battery")
    assert(BatteryStore.sharedGroup(declared: "OLDSIGNER0.com.alan.thorCompanion.battery", defaultGroup: nil) == "OLDSIGNER0.com.alan.thorCompanion.battery")
    assert(BatteryStore.sharedGroup(declared: "OLDSIGNER0.com.alan.thorCompanion.battery", defaultGroup: "invalid.group") == "OLDSIGNER0.com.alan.thorCompanion.battery")
    print("Widget snapshot checks passed: recent, stale, disconnected, cache roundtrip, level symbols and ring fractions.")
  }
}
