import Foundation

/// One configurable clock output (`ClockOutputCfg` in `ks_config.h`), routed to
/// a USB-MIDI virtual cable. Division/phase/swing are the E-RM-Multiclock-style
/// controls; `followsLinkTransport` picks which single thing owns this output's
/// Start/Stop (`follow_link` — exactly one master per output, never two).
struct ClockOutputConfig: Decodable, Equatable {
    var enabled: Bool
    var cable: Int             // 0...3 — USB-MIDI virtual cable (Midihub USB A..D)
    var ppqn: Int               // pulses per beat: 1/2/4=quarter/eighth/sixteenth, 24=MIDI clock, 48=×2
    var phaseMilliBeats: Int    // -250...250 — latency-comp nudge
    var swingMilliBeats: Int    // 0...250 — 0 straight
    var followsLinkTransport: Bool

    private enum CodingKeys: String, CodingKey {
        case enabled = "en", cable, ppqn, phaseMilliBeats = "phase"
        case swingMilliBeats = "swing", followsLinkTransport = "follow"
    }

    static let disabled = ClockOutputConfig(
        enabled: false, cable: 0, ppqn: 24, phaseMilliBeats: 0, swingMilliBeats: 0, followsLinkTransport: true
    )
}

/// One saved WiFi network slot (`KS_WIFI_SLOTS` = 3). The password is never
/// readable — `GET /config.json` (P4-041) deliberately omits it, mirroring the
/// web UI's own HTML form, which never echoes a saved password back either
/// (`ks_web.cpp`'s `build_wifi()`). `passwordIsSet` is all a client ever learns.
struct WifiSlot: Decodable, Equatable {
    var ssid: String
    var passwordIsSet: Bool

    private enum CodingKeys: String, CodingKey {
        case ssid, passwordIsSet = "pass_set"
    }

    static let empty = WifiSlot(ssid: "", passwordIsSet: false)
}

/// Decodes `GET /config.json` (P4-041, `ks_config_json.c`) — the device's
/// ACTUAL current settings, as opposed to `/status`'s telemetry. Field names
/// mirror the `POST /save` / `POST /live` form grammar 1:1
/// (`ks_config_set()` in `ks_config.c`); `saveFormFields()` below is the
/// encode-side mirror of this decode.
struct KsConfig: Decodable, Equatable {
    static let outputCount = 4     // KS_CLOCK_OUTPUTS
    static let wifiSlotCount = 3   // KS_WIFI_SLOTS

    var clockOutEnabled: Bool
    var metronomeEnabled: Bool
    var metronomeAccent: Bool
    var metronomeVolume: Int        // 0...100
    var metronomeVoice: Int         // 0=Tone 1=Click 2=Wood
    var ledEnabled: Bool
    var ledBrightness: Int          // 0...100
    var ledMode: Int                // 0=chase 1=flash 2=fill
    var ledFade: Int                // 0...100
    var ledBeatColor: UInt32        // 0xRRGGBB
    var ledAccentColor: UInt32
    var followBeatEnabled: Bool
    var wifi: [WifiSlot]
    var clock: [ClockOutputConfig]

    private enum CodingKeys: String, CodingKey {
        case clockOutEnabled = "clock_out", metronomeEnabled = "metronome"
        case metronomeAccent = "metro_accent", metronomeVolume = "metro_vol"
        case metronomeVoice = "metro_voice", ledEnabled = "led"
        case ledBrightness = "led_bright", ledMode = "led_mode", ledFade = "led_fade"
        case ledBeatColor = "led_beat", ledAccentColor = "led_accent"
        case followBeatEnabled = "follow_beat", wifi, clock
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clockOutEnabled = try c.decode(Bool.self, forKey: .clockOutEnabled)
        metronomeEnabled = try c.decode(Bool.self, forKey: .metronomeEnabled)
        metronomeAccent = try c.decode(Bool.self, forKey: .metronomeAccent)
        metronomeVolume = try c.decode(Int.self, forKey: .metronomeVolume)
        metronomeVoice = try c.decode(Int.self, forKey: .metronomeVoice)
        ledEnabled = try c.decode(Bool.self, forKey: .ledEnabled)
        ledBrightness = try c.decode(Int.self, forKey: .ledBrightness)
        ledMode = try c.decode(Int.self, forKey: .ledMode)
        ledFade = try c.decode(Int.self, forKey: .ledFade)
        let beatColorString = try c.decode(String.self, forKey: .ledBeatColor)
        ledBeatColor = try Self.parseHexColor(beatColorString, forKey: .ledBeatColor, in: c)
        let accentColorString = try c.decode(String.self, forKey: .ledAccentColor)
        ledAccentColor = try Self.parseHexColor(accentColorString, forKey: .ledAccentColor, in: c)
        followBeatEnabled = try c.decode(Bool.self, forKey: .followBeatEnabled)
        wifi = try c.decode([WifiSlot].self, forKey: .wifi)
        clock = try c.decode([ClockOutputConfig].self, forKey: .clock)
    }

    /// Parses `"#rrggbb"` (the form firmware sends `led_beat`/`led_accent`
    /// as — `ks_config_json.c`, `#%06X`). Also accepts no leading `#`.
    private static func parseHexColor(
        _ s: String, forKey key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UInt32 {
        let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard let value = UInt32(hex, radix: 16) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "not a hex color: \(s)")
        }
        return value
    }
}

extension KsConfig {
    /// The form fields that CANNOT be applied live — changing any of them requires a
    /// full `POST /save`, which persists to NVS and **reboots the device**.
    ///
    /// This is the complement of `KsLiveEdit`'s case list, and the two are held
    /// disjoint-and-exhaustive by `LiveRebootPartitionTests`. Add a field to
    /// `saveFormFields` without classifying it and that test fails — which is the
    /// point, because an unclassified field is a control that might silently restart
    /// a device mid-set.
    ///
    /// Why these three (verified in `ks_web.cpp` — they lack the `class="live"`
    /// attribute that every live field carries):
    /// - `metronome` / `follow_beat` ENABLE: the ES8311 codec and I2S only come up at
    ///   boot, so `/live` silently ignores them. Note the trap — `metro_accent`,
    ///   `metro_vol` and `metro_voice` ARE live; only the *enable* is not.
    /// - WiFi credentials: applied by the network stack at association time.
    ///
    /// The settings sheet (T-007) generates its `REBOOTS` tags from this set, so an
    /// untagged reboot-required control there is impossible by construction.
    static let rebootRequiredFormKeys: Set<String> = {
        var keys: Set<String> = ["metronome", "follow_beat"]
        for slot in 0..<wifiSlotCount {
            let suffix = slot == 0 ? "" : String(slot)
            keys.insert("wifi_ssid\(suffix)")
            keys.insert("wifi_pass\(suffix)")
        }
        return keys
    }()

    /// Every field explicit, for `POST /save` (`ks_form_resolve` on the
    /// firmware). A real HTML form omits an unchecked checkbox and relies on
    /// the firmware's pre-clear to read that as "off"; this client isn't an
    /// HTML form, so it just sends "0" or "1" for every boolean —
    /// `ks_config_set()` parses booleans by value (`atoi`), not by presence, so
    /// the two are equivalent and this way nothing depends on the firmware's
    /// pre-clear list staying in sync with this app's field list.
    ///
    /// `wifiEdits` carries the Settings screen's SSID/password inputs
    /// separately (`KsConfig` itself never holds a real password — see
    /// `WifiSlot`). An empty password field means "keep current"
    /// (`ks_config_set`'s documented no-op for a blank `wifi_pass`), so it's
    /// only included when the user actually typed one.
    func saveFormFields(wifiEdits: [WifiCredentialEdit]) -> [String: String] {
        var fields: [String: String] = [
            "clock_out": Self.boolField(clockOutEnabled),
            "metronome": Self.boolField(metronomeEnabled),
            "metro_accent": Self.boolField(metronomeAccent),
            "metro_vol": String(metronomeVolume),
            "metro_voice": String(metronomeVoice),
            "led": Self.boolField(ledEnabled),
            "led_bright": String(ledBrightness),
            "led_mode": String(ledMode),
            "led_fade": String(ledFade),
            "led_beat": Self.colorField(ledBeatColor),
            "led_accent": Self.colorField(ledAccentColor),
            "follow_beat": Self.boolField(followBeatEnabled),
        ]
        // Keyed by `edit.id` (the slot number), not array position — a caller
        // that filters or reorders `wifiEdits` must not silently relabel which
        // saved network gets touched.
        for edit in wifiEdits where (0..<Self.wifiSlotCount).contains(edit.id) {
            let suffix = edit.id == 0 ? "" : String(edit.id)
            fields["wifi_ssid\(suffix)"] = edit.ssid
            if !edit.password.isEmpty {
                fields["wifi_pass\(suffix)"] = edit.password
            }
        }
        for (index, output) in clock.enumerated() {
            fields["clk\(index)_en"] = Self.boolField(output.enabled)
            fields["clk\(index)_cable"] = String(output.cable)
            fields["clk\(index)_ppqn"] = String(output.ppqn)
            fields["clk\(index)_phase"] = String(output.phaseMilliBeats)
            fields["clk\(index)_swing"] = String(output.swingMilliBeats)
            fields["clk\(index)_follow"] = Self.boolField(output.followsLinkTransport)
        }
        return fields
    }

    fileprivate static func boolField(_ value: Bool) -> String { value ? "1" : "0" }

    fileprivate static func colorField(_ value: UInt32) -> String {
        String(format: "#%06X", value & 0xFFFFFF)
    }
}

/// The Settings screen's per-slot WiFi input — SSID plus an optionally-typed
/// new password. Seeded from `WifiSlot.ssid` (real) and an empty password
/// (never known), per `saveFormFields`'s "empty means keep current" rule.
struct WifiCredentialEdit: Identifiable, Equatable {
    var id: Int   // slot index
    var ssid: String
    var password: String = ""
}
