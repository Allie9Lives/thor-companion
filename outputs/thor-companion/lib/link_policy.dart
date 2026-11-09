enum ControlRoute { bluetooth, network }

/// Separate signal from routing: no network route without a recent successful probe.
class LinkPolicy {
  ControlRoute route = ControlRoute.bluetooth;
  double? bleMs, networkMs;
  int? rssi;
  int weak = 0, strong = 0, networkGood = 0;
  DateTime? verifiedAt, switchedAt;
  void bluetooth({Duration? elapsed, int? signal, bool failed = false}) {
    if (signal != null) rssi = signal;
    if (elapsed != null) {
      bleMs = bleMs == null
          ? elapsed.inMilliseconds.toDouble()
          : bleMs! * .65 + elapsed.inMilliseconds * .35;
    }
    final poor =
        failed ||
        (rssi != null && rssi! <= -82) ||
        (bleMs != null && bleMs! > 700);
    weak = poor ? weak + 1 : 0;
    strong =
        !poor &&
            (rssi == null || rssi! >= -74) &&
            (bleMs == null || bleMs! < 500)
        ? strong + 1
        : 0;
  }

  void network(Duration elapsed, DateTime now) {
    networkMs = networkMs == null
        ? elapsed.inMilliseconds.toDouble()
        : networkMs! * .65 + elapsed.inMilliseconds * .35;
    verifiedAt = now;
    networkGood++;
  }

  void networkFailed() {
    verifiedAt = null;
    networkGood = 0;
    networkMs = null;
  }

  bool ready(DateTime now) =>
      verifiedAt != null &&
      now.difference(verifiedAt!) < const Duration(seconds: 15);
  ControlRoute choose(DateTime now, {required bool bleAvailable}) {
    final old = route;
    if (!ready(now)) {
      route = ControlRoute.bluetooth;
    } else if (!bleAvailable) {
      route = ControlRoute.network;
    } else if (switchedAt == null ||
        now.difference(switchedAt!) >= const Duration(seconds: 15)) {
      if (route == ControlRoute.bluetooth &&
          networkGood >= 2 &&
          (weak >= 2 ||
              (networkGood >= 3 &&
                  bleMs != null &&
                  bleMs! > 100 &&
                  networkMs! < bleMs! * .65))) {
        route = ControlRoute.network;
      } else if (route == ControlRoute.network &&
          strong >= 3 &&
          (bleMs == null || networkMs! > bleMs! * .8)) {
        route = ControlRoute.bluetooth;
      }
    }
    if (old != route) switchedAt = now;
    return route;
  }
}
