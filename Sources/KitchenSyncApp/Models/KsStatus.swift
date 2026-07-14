import Foundation

/// The 1 ms clock task's own health (P4-038, `ks_tick_health.h`), published as
/// plain scalars and never logged on-device (an `ESP_LOGx` in a 1 ms RT task is
/// a blocking UART write). Lifetime counters, not windowed — a worst-case that
/// scrolled past is not a measurement.
struct TickHealth: Decodable, Equatable {
    var droppedTicks: UInt32
    var bursts: UInt32
    var maxGapMicros: UInt32
    var maxWorkMicros: UInt32
    var overruns: UInt32
    var core: Int
    var beatsWritten: UInt32
    var clockPulsesWritten: UInt32
    var reprimes: UInt32
}

/// The GhostXForm origin-step gauge (P4-038) — `maxStepMicros` is how far a
/// commit has ever thrown the beat origin, the number whose absence cost 138
/// seconds of silent DIN clock in ESP-027.
struct PhaseHealth: Decodable, Equatable {
    var commits: UInt32
    var lastStepMicros: UInt32
    var maxStepMicros: UInt32
    var rttMinMicros: UInt32
    var rttMaxMicros: UInt32
}

/// Decodes KitchenSync's `GET /status` JSON (`KitchenSync/main/ks_status.c`).
/// Telemetry only — bpm, peers, launch/playing state — never the device's
/// actual settings; see `KsConfig` (from `GET /config.json`, P4-041) for that.
///
/// Field names are decoded from the firmware's verbatim wire keys, including
/// the oddity that MIDI-clock-in BPM is reported under `"min"`, not
/// `"midi_bpm"` — don't "fix" that mapping, it has to match the wire format.
struct KsStatus: Decodable, Equatable {
    var bpm: Double
    var midiClockInBPM: Double
    var peers: Int
    var usbConnected: Bool
    var clockPulseCount: UInt32
    var firmwareVersion: String

    var followBeatEnabled: Bool
    var followBeatBPM: Double
    var followBeatConfidence: Double
    var followBeatValid: Bool

    /// One state per clock output (`KsConfig.maxOutputCount` == 4).
    var launch: [TransportLaunchState]
    var playing: Bool
    var linkOwnsTransport: Bool

    var tickHealth: TickHealth?
    var phaseHealth: PhaseHealth?

    private enum CodingKeys: String, CodingKey {
        case bpm
        case midiClockInBPM = "min"
        case peers
        case usbConnected = "usb"
        case clockPulseCount = "tx"
        case firmwareVersion = "fw"
        case followBeatEnabled = "follow_enabled"
        case followBeatBPM = "follow_bpm"
        case followBeatConfidence = "follow_confidence"
        case followBeatValid = "follow_valid"
        case launch
        case playing
        case linkOwnsTransport = "link_owns"
        // Tick/phase health keys below live in the SAME flat JSON object (the
        // firmware appends them onto one buffer, not a nested object) — decoded
        // via decodeIfPresent from this same container, not a sub-container.
        case droppedTicks = "drop", bursts = "burst", maxGapMicros = "gap"
        case maxWorkMicros = "work", overruns = "over", core
        case beatsWritten = "w_beats", clockPulsesWritten = "w_clock", reprimes = "reprime"
        case commits = "xf", lastStepMicros = "xf_step", maxStepMicros = "xf_max"
        case rttMinMicros = "rtt_min", rttMaxMicros = "rtt_max"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try c.decode(Double.self, forKey: .bpm)
        midiClockInBPM = try c.decode(Double.self, forKey: .midiClockInBPM)
        peers = try c.decode(Int.self, forKey: .peers)
        usbConnected = try c.decode(Bool.self, forKey: .usbConnected)
        clockPulseCount = try c.decode(UInt32.self, forKey: .clockPulseCount)
        firmwareVersion = try c.decode(String.self, forKey: .firmwareVersion)
        followBeatEnabled = try c.decode(Bool.self, forKey: .followBeatEnabled)
        followBeatBPM = try c.decode(Double.self, forKey: .followBeatBPM)
        followBeatConfidence = try c.decode(Double.self, forKey: .followBeatConfidence)
        followBeatValid = try c.decode(Bool.self, forKey: .followBeatValid)
        launch = try c.decode([Int].self, forKey: .launch).map { TransportLaunchState(rawValue: $0) ?? .stopped }
        playing = try c.decode(Bool.self, forKey: .playing)
        linkOwnsTransport = try c.decode(Bool.self, forKey: .linkOwnsTransport)

        // ks_status_json() only appends the tick/phase blocks when the caller
        // passed non-null pointers — never publish a row of zeroes standing in
        // for "not measured", so treat any single missing key as "block absent".
        if let dropped = try c.decodeIfPresent(UInt32.self, forKey: .droppedTicks) {
            tickHealth = TickHealth(
                droppedTicks: dropped,
                bursts: try c.decode(UInt32.self, forKey: .bursts),
                maxGapMicros: try c.decode(UInt32.self, forKey: .maxGapMicros),
                maxWorkMicros: try c.decode(UInt32.self, forKey: .maxWorkMicros),
                overruns: try c.decode(UInt32.self, forKey: .overruns),
                core: try c.decode(Int.self, forKey: .core),
                beatsWritten: try c.decode(UInt32.self, forKey: .beatsWritten),
                clockPulsesWritten: try c.decode(UInt32.self, forKey: .clockPulsesWritten),
                reprimes: try c.decode(UInt32.self, forKey: .reprimes)
            )
        } else {
            tickHealth = nil
        }

        if let commits = try c.decodeIfPresent(UInt32.self, forKey: .commits) {
            phaseHealth = PhaseHealth(
                commits: commits,
                lastStepMicros: try c.decode(UInt32.self, forKey: .lastStepMicros),
                maxStepMicros: try c.decode(UInt32.self, forKey: .maxStepMicros),
                rttMinMicros: try c.decode(UInt32.self, forKey: .rttMinMicros),
                rttMaxMicros: try c.decode(UInt32.self, forKey: .rttMaxMicros)
            )
        } else {
            phaseHealth = nil
        }
    }
}
