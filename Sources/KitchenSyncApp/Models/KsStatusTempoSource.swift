import Foundation

extension KsStatus {
    /// Where the session tempo is actually coming from.
    enum TempoSource: Equatable {
        case link
        case midiClockIn
        case followBeat
    }

    /// The device's web UI hardcodes "Ableton Link" here. That's a lie whenever the
    /// tempo is really arriving over MIDI clock in, or off the mic's follow-beat.
    ///
    /// Precedence: Link peers outrank everything — if someone is in the session,
    /// that's the master, and a stray MIDI cable must not relabel the display. With
    /// no peers, an incoming MIDI clock is the source. Failing that, a *locked*
    /// follow-beat is. An enabled-but-unlocked follow-beat is NOT a source: the mic
    /// is listening, it just hasn't heard a beat it trusts.
    ///
    /// Alone with nothing incoming is still Link — the device is running its own
    /// session with nobody else in it.
    var tempoSource: TempoSource {
        if peers > 0 { return .link }
        if midiClockInBPM > 0 { return .midiClockIn }
        if followBeatEnabled && followBeatValid { return .followBeat }
        return .link
    }

    /// The firmware's own three strings (`ks_web.cpp`), verbatim.
    var followBeatSummary: String {
        guard followBeatEnabled else { return "off" }
        guard followBeatValid else { return "listening…" }
        return String(format: "%.1f BPM", followBeatBPM)
    }
}
