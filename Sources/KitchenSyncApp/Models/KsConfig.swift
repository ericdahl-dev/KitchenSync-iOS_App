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
/// The metronome, when a speaker is actually fitted. `nil` on a device without one —
/// and `nil` is NOT the same statement as "a metronome that is switched off".
struct MetronomeConfig: Equatable {
    var enabled: Bool
    var accent: Bool
    var volume: Int      // 0...100
    var voice: Int       // 0=Tone 1=Click 2=Wood
}

/// The LED strip, when one is actually wired. `nil` on a device without one.
struct LedConfig: Equatable {
    var enabled: Bool
    var brightness: Int   // 0...100
    var mode: Int         // 0=chase 1=flash 2=fill
    var fade: Int         // 0...100
    var beatColor: UInt32     // 0xRRGGBB
    var accentColor: UInt32
}

struct KsConfig: Decodable, Equatable {
    /// The MAXIMUM a device can have, not an assumption about any given one — the real
    /// count is `clock.count`, which the firmware sets to what is actually FITTED
    /// (`link-devices` ESP-030). One DIN jack on a Touch, four on a P4.
    static let maxOutputCount = 4   // KS_CLOCK_OUTPUTS
    static let wifiSlotCount = 3    // KS_WIFI_SLOTS

    var clockOutEnabled: Bool

    /// **`nil` means the hardware ISN'T FITTED — not that it's switched off.**
    ///
    /// A device must not report hardware it doesn't have, so absent hardware is absent
    /// from `/config.json` entirely (`link-devices` ESP-030). `metronome: false` would
    /// claim "there is a speaker and it's off", which on a Touch is simply untrue — and
    /// this app would draw a volume slider for a speaker that doesn't exist.
    ///
    /// Capability is a property of the BUILD, not the product: solder a strip onto a
    /// Touch, flip one firmware flag, and `led` starts arriving — and the LED section
    /// appears here with no change to this app.
    var metronome: MetronomeConfig?
    var led: LedConfig?
    var followBeatEnabled: Bool?

    var wifi: [WifiSlot]
    var clock: [ClockOutputConfig]

    /// The device's STORED free-run tempo, BPM. **`nil` means this build can't set a
    /// tempo** — it's listener-only (X32Link), so `/config.json` omits `bpm`
    /// (`link-devices` ESP-037, gated by `KsCaps.settable_tempo`), same capability rule
    /// as `metronome`/`led`.
    ///
    /// This is the tempo you SET — distinct from `KsStatus.bpm`, the tempo the device is
    /// currently CLOCKING (Link's, when a session is driving). The tempo control shows
    /// this one; it doesn't jump around when Link takes over.
    var tempo: Double?

    private enum CodingKeys: String, CodingKey {
        case clockOutEnabled = "clock_out", metronomeEnabled = "metronome"
        case metronomeAccent = "metro_accent", metronomeVolume = "metro_vol"
        case metronomeVoice = "metro_voice", ledEnabled = "led"
        case ledBrightness = "led_bright", ledMode = "led_mode", ledFade = "led_fade"
        case ledBeatColor = "led_beat", ledAccentColor = "led_accent"
        case followBeatEnabled = "follow_beat", tempo = "bpm", wifi, clock
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clockOutEnabled = try c.decode(Bool.self, forKey: .clockOutEnabled)

        // The presence of the ENABLE key is what says the hardware is fitted. Once it's
        // there, the rest of its group must be too — a half-reported metronome is a
        // firmware bug, and decoding it into defaults would hide that.
        if let enabled = try c.decodeIfPresent(Bool.self, forKey: .metronomeEnabled) {
            metronome = MetronomeConfig(
                enabled: enabled,
                accent: try c.decode(Bool.self, forKey: .metronomeAccent),
                volume: try c.decode(Int.self, forKey: .metronomeVolume),
                voice: try c.decode(Int.self, forKey: .metronomeVoice)
            )
        } else {
            metronome = nil
        }

        if let enabled = try c.decodeIfPresent(Bool.self, forKey: .ledEnabled) {
            let beat = try c.decode(String.self, forKey: .ledBeatColor)
            let accent = try c.decode(String.self, forKey: .ledAccentColor)
            led = LedConfig(
                enabled: enabled,
                brightness: try c.decode(Int.self, forKey: .ledBrightness),
                mode: try c.decode(Int.self, forKey: .ledMode),
                fade: try c.decode(Int.self, forKey: .ledFade),
                beatColor: try Self.parseHexColor(beat, forKey: .ledBeatColor, in: c),
                accentColor: try Self.parseHexColor(accent, forKey: .ledAccentColor, in: c)
            )
        } else {
            led = nil
        }

        followBeatEnabled = try c.decodeIfPresent(Bool.self, forKey: .followBeatEnabled)
        tempo = try c.decodeIfPresent(Double.self, forKey: .tempo)   // ESP-037: nil = listener-only
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

    /// Turn the device's WiFi slots into editable rows for the settings sheet.
    ///
    /// The password is ALWAYS seeded empty, because it was never on the wire and
    /// cannot be — `/config.json` omits it and `WifiSlot` only carries
    /// `passwordIsSet`. That is not data loss: an empty password means "keep the
    /// saved one" (`saveFormFields` omits the field entirely, which is
    /// `ks_config_set`'s documented no-op), so blank is the correct default.
    ///
    /// Keyed by slot index, never by array position — `saveFormFields` picks the
    /// `wifi_ssid` / `wifi_ssid1` / `wifi_ssid2` suffix off `id`, and a caller that
    /// filters or reorders these must carry the `id` with them or it will silently
    /// overwrite the wrong saved network.
    func seededWifiEdits() -> [WifiCredentialEdit] {
        wifi.enumerated().map { index, slot in
            WifiCredentialEdit(id: index, ssid: slot.ssid, password: "")
        }
    }

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
        ]

        // Only send what the device HAS. Posting `metronome=0` to a board with no speaker
        // would be writing a setting for hardware that isn't there — and, worse, this app
        // would have had to invent a value for it, which is exactly the fabricated-defaults
        // clobbering that `/config.json` exists to prevent. Absent stays absent, in both
        // directions.
        if let m = metronome {
            fields["metronome"] = Self.boolField(m.enabled)
            fields["metro_accent"] = Self.boolField(m.accent)
            fields["metro_vol"] = String(m.volume)
            fields["metro_voice"] = String(m.voice)
        }
        if let l = led {
            fields["led"] = Self.boolField(l.enabled)
            fields["led_bright"] = String(l.brightness)
            fields["led_mode"] = String(l.mode)
            fields["led_fade"] = String(l.fade)
            fields["led_beat"] = Self.colorField(l.beatColor)
            fields["led_accent"] = Self.colorField(l.accentColor)
        }
        if let followBeatEnabled {
            fields["follow_beat"] = Self.boolField(followBeatEnabled)
        }
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

    /// Fold one ACCEPTED live edit into the local config, mirroring what `/live` just
    /// did on the device. Call this ONLY after the POST returned 2xx: this is not an
    /// optimistic guess, it is bookkeeping for a change that already happened.
    ///
    /// Without it a working `/live` still LOOKS broken — the POST succeeds, the device
    /// obeys, and the number on screen never moves, because `/config.json` is only
    /// re-fetched on demand.
    ///
    /// A capability that isn't fitted (`metronome == nil`, `led == nil`) stays nil. An
    /// edit can't bring hardware into existence, and an index past the outputs this
    /// device actually has is dropped rather than grown into — the array's length IS
    /// the output count (ESP-030), so appending to it would invent a jack.
    mutating func apply(_ edit: KsLiveEdit) {
        switch edit {
        case .clockOutEnabled(let v): clockOutEnabled = v

        case .metronomeAccent(let v): metronome?.accent = v
        case .metronomeVolume(let v): metronome?.volume = v
        case .metronomeVoice(let v):  metronome?.voice = v

        case .ledEnabled(let v):      led?.enabled = v
        case .ledBrightness(let v):   led?.brightness = v
        case .ledMode(let v):         led?.mode = v
        case .ledFade(let v):         led?.fade = v
        case .ledBeatColor(let v):    led?.beatColor = v
        case .ledAccentColor(let v):  led?.accentColor = v

        case .outputEnabled(let i, let v):      withOutput(i) { $0.enabled = v }
        case .outputCable(let i, let v):        withOutput(i) { $0.cable = v }
        case .outputPPQN(let i, let v):         withOutput(i) { $0.ppqn = v }
        case .outputPhase(let i, let v):        withOutput(i) { $0.phaseMilliBeats = v }
        case .outputSwing(let i, let v):        withOutput(i) { $0.swingMilliBeats = v }
        case .outputFollowsLink(let i, let v):  withOutput(i) { $0.followsLinkTransport = v }

        // ESP-037: only reflect the set tempo if this device HAS a settable one. On a
        // listener-only config (tempo == nil) a set is meaningless and must not conjure
        // a value the device doesn't keep — the same nil-means-not-fitted rule as the
        // capability sections above.
        case .setTempo(let v):  if tempo != nil { tempo = v }
        }
    }

    private mutating func withOutput(_ index: Int, _ change: (inout ClockOutputConfig) -> Void) {
        guard clock.indices.contains(index) else { return }
        change(&clock[index])
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
