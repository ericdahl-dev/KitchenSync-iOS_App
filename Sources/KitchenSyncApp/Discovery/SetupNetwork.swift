import Foundation

/// A device that has never joined the user's network comes up in **SoftAP setup mode**,
/// broadcasting its own open WiFi and serving its config web server at a fixed address. This is
/// where first-run provisioning happens (T-026): the app reaches the device *on its own AP*,
/// confirms it's ours, and hands it the user's WiFi credentials.
///
/// Pure constants + an SSID test, so the setup UI and any `NEHotspotConfiguration` join can be
/// asserted without standing up a radio — the same split `DeviceMatch` uses for LAN discovery.
enum SetupNetwork {
    /// The address the firmware serves its web server on in SoftAP mode — fixed across the
    /// fleet (`wifi_link.c` / `KitchenSyncTouch.ino`, both at `192.168.4.1`).
    static let host = "192.168.4.1"

    /// The setup SSIDs the fleet broadcasts, by product:
    ///   - `KitchenSync-Setup` — the P4 (`wifi_link.c` `AP_SSID`)
    ///   - `KSTouch-Config`    — the Touch (`KitchenSyncTouch.ino` `WiFi.softAP`)
    /// Matched as a **family of prefixes**, not one string, so a new product's setup AP is
    /// recognised without an app change — the same reason `DeviceMatch` matches host prefixes.
    static let ssidPrefixes = ["kitchensync-setup", "kstouch-config"]

    /// True if `ssid` is one of our devices' setup APs. Case-insensitive: a WiFi SSID's case is
    /// not meaningful, and iOS reports it however the radio saw it.
    static func isSetupAP(ssid: String) -> Bool {
        let lower = ssid.lowercased()
        return ssidPrefixes.contains { lower.hasPrefix($0) }
    }
}
