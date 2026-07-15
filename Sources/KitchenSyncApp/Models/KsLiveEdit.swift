import Foundation

/// One field this app can `POST /live` (apply immediately, no reboot).
/// Deliberately a **closed set** matching `ks_config_live_safe_copy()`
/// (`KitchenSync/main/ks_config.c`) — `metronome`/`follow_beat` *enable* and
/// WiFi credentials are reboot-only (`ks_web.cpp`'s `save_handler` comment:
/// the ES8311 codec/I2S only come up at boot) and have no case here on
/// purpose, so a caller can't accidentally try to live-edit something `/live`
/// silently ignores. Those live in `KsConfig.saveFormFields` instead.
enum KsLiveEdit {
    case clockOutEnabled(Bool)
    case metronomeAccent(Bool)
    case metronomeVolume(Int)
    case metronomeVoice(Int)
    case ledEnabled(Bool)
    case ledBrightness(Int)
    case ledMode(Int)
    case ledFade(Int)
    case ledBeatColor(UInt32)
    case ledAccentColor(UInt32)
    case outputEnabled(index: Int, Bool)
    case outputCable(index: Int, Int)
    case outputPPQN(index: Int, Int)
    case outputPhase(index: Int, Int)
    case outputSwing(index: Int, Int)
    case outputFollowsLink(index: Int, Bool)

    /// ESP-037: the device-global free-run tempo, BPM. Drives the clock when the device
    /// is solo; a Link session still wins. Tap, numeric entry, and the ± steppers ALL
    /// resolve to this one number — tap is computed in the app (local timing, no WiFi
    /// jitter), never sent as tap events over the network.
    case setTempo(Double)

    /// The one `(key, value)` pair this edit POSTs. `/live` is a PARTIAL patch
    /// (`ks_form_apply` on the firmware) — fields not present keep their
    /// current value, so sending exactly one pair per edit is correct, not a
    /// shortcut.
    var formField: (key: String, value: String) {
        switch self {
        case .clockOutEnabled(let v): return ("clock_out", boolValue(v))
        case .metronomeAccent(let v): return ("metro_accent", boolValue(v))
        case .metronomeVolume(let v): return ("metro_vol", String(v))
        case .metronomeVoice(let v): return ("metro_voice", String(v))
        case .ledEnabled(let v): return ("led", boolValue(v))
        case .ledBrightness(let v): return ("led_bright", String(v))
        case .ledMode(let v): return ("led_mode", String(v))
        case .ledFade(let v): return ("led_fade", String(v))
        case .ledBeatColor(let v): return ("led_beat", colorValue(v))
        case .ledAccentColor(let v): return ("led_accent", colorValue(v))
        case .outputEnabled(let i, let v): return ("clk\(i)_en", boolValue(v))
        case .outputCable(let i, let v): return ("clk\(i)_cable", String(v))
        case .outputPPQN(let i, let v): return ("clk\(i)_ppqn", String(v))
        case .outputPhase(let i, let v): return ("clk\(i)_phase", String(v))
        case .outputSwing(let i, let v): return ("clk\(i)_swing", String(v))
        case .outputFollowsLink(let i, let v): return ("clk\(i)_follow", boolValue(v))
        case .setTempo(let v): return ("bpm", bpmValue(v))
        }
    }

    private func boolValue(_ v: Bool) -> String { v ? "1" : "0" }
    private func colorValue(_ v: UInt32) -> String { String(format: "#%06X", v & 0xFFFFFF) }
    /// Milli-BPM precision, locale-independent (the "." must not become a "," on a
    /// European phone — the firmware parses with atof, which is C-locale).
    private func bpmValue(_ v: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), v)
    }
}
