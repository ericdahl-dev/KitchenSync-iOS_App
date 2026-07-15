import Foundation

/// Decides whether a Bonjour result is one of ours.
///
/// Pure, so it can be tested without standing up an `NWBrowser` — the browser glue in
/// `KitchenSyncDiscovery` stays dumb and this gets the tests.
enum DeviceMatch {
    /// The TXT key the firmware will publish (`link-devices` ESP-031).
    static let identityKey = "dev"
    static let identityValue = "kitchensync"

    /// **TXT is the truth; the hostname is a guess.**
    ///
    /// When a TXT record is present, identity is a FACT and the hostname is not consulted at all —
    /// including when the hostname *would* have passed. A stranger's box at a venue named
    /// `kitchensync-whatever` is exactly the false positive the prefix heuristic cannot prevent
    /// and TXT can.
    ///
    /// When TXT is ABSENT we fall back to the hostname, because units in the field have no TXT
    /// record and won't until they're reflashed. Matching on TXT alone would make every existing
    /// device vanish — a worse bug than the one this fixes.
    static func isKitchenSync(serviceName: String, txt: [String: String]?) -> Bool {
        if let txt, let dev = txt[identityKey] {
            return dev == identityValue
        }
        return matchesKnownHostname(serviceName)
    }

    /// The FALLBACK. A heuristic, and deliberately labelled as one — it exists to keep un-updated
    /// units working, not because it is correct.
    ///
    /// The firmware advertises generic `_http._tcp` with no TXT record, so the hostname is all a
    /// client has. The hostname is `<product>-<last two MAC bytes>`: `kitchensync-a4f2` on the
    /// P4, `kstouch-dfd0` on the Touch. Missing `kstouch` made a real device invisible once.
    private static func matchesKnownHostname(_ name: String) -> Bool {
        let lower = name.lowercased()   // a Bonjour instance name's case is not meaningful —
                                        // the P4 advertises "KitchenSync", the Touch "kstouch-…"
        return knownHostPrefixes.contains { lower.hasPrefix($0) }
    }

    /// KitchenSync ONLY — the P4 and its Touch / Super Mini versions. X32Link is a SEPARATE
    /// product (it happens to speak Link too) with its own app, so it is deliberately NOT
    /// here, and the firmware publishes `dev=x32link` so the TXT path excludes it as well.
    /// `x32link` was briefly in this list (ESP-035); removed once it became clear this app is
    /// KitchenSync's, not the fleet's.
    private static let knownHostPrefixes = ["kitchensync", "kstouch"]
}
