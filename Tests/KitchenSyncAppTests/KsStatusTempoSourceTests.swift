import XCTest
@testable import KitchenSyncApp

/// TDD: written before `KsStatus.tempoSource` / `followBeatSummary` exist.
///
/// The device's own web UI hardcodes "Ableton Link" as the tempo source. That is a
/// lie whenever the tempo is actually coming from MIDI clock in, or from the mic's
/// follow-beat. `KsStatus` carries enough to know the difference, so the app tells
/// the truth. A tempo display that lies about its source is worse than one with no
/// label at all — you cannot debug a drifting clock if the screen misattributes it.
final class KsStatusTempoSourceTests: XCTestCase {
    private func status(
        peers: Int = 0,
        midiIn: Double = 0,
        followEnabled: Bool = false,
        followValid: Bool = false,
        followBPM: Double = 0
    ) throws -> KsStatus {
        let json = """
        {"bpm":128.0,"min":\(midiIn),"peers":\(peers),"usb":true,"tx":1,"fw":"1.2.3",
         "follow_enabled":\(followEnabled),"follow_bpm":\(followBPM),
         "follow_confidence":0.9,"follow_valid":\(followValid),
         "launch":[0,0,0,0],"playing":false,"link_owns":false}
        """
        return try JSONDecoder().decode(KsStatus.self, from: Data(json.utf8))
    }

    func test_peers_present_means_the_tempo_comes_from_link() throws {
        let s = try status(peers: 3)
        XCTAssertEqual(s.tempoSource, .link)
    }

    func test_no_peers_but_midi_clock_in_means_midi() throws {
        let s = try status(peers: 0, midiIn: 120.0)
        XCTAssertEqual(s.tempoSource, .midiClockIn)
    }

    func test_no_peers_and_valid_follow_beat_means_follow_beat() throws {
        let s = try status(peers: 0, followEnabled: true, followValid: true, followBPM: 94.0)
        XCTAssertEqual(s.tempoSource, .followBeat)
    }

    /// Link is the fallback: with no peers, no MIDI in, and no valid follow-beat,
    /// the device is running its own Link session with nobody else in it. Still Link.
    func test_alone_with_nothing_incoming_is_still_link() throws {
        let s = try status(peers: 0)
        XCTAssertEqual(s.tempoSource, .link)
    }

    /// Link peers OUTRANK a MIDI clock signal. If someone is in the session, that's
    /// the master; a stray MIDI cable must not relabel the display.
    func test_link_peers_outrank_midi_clock_in() throws {
        let s = try status(peers: 2, midiIn: 120.0)
        XCTAssertEqual(s.tempoSource, .link)
    }

    /// An ENABLED but not-yet-locked follow-beat is not a tempo source. The mic is
    /// listening; it hasn't heard a beat it trusts.
    func test_follow_beat_enabled_but_not_valid_is_not_the_source() throws {
        let s = try status(peers: 0, followEnabled: true, followValid: false)
        XCTAssertEqual(s.tempoSource, .link)
    }

    // MARK: Follow-beat summary — the firmware's own three strings.

    func test_follow_beat_summary_off() throws {
        let s = try status(followEnabled: false)
        XCTAssertEqual(s.followBeatSummary, "off")
    }

    func test_follow_beat_summary_listening_when_enabled_but_not_locked() throws {
        let s = try status(followEnabled: true, followValid: false)
        XCTAssertEqual(s.followBeatSummary, "listening…")
    }

    func test_follow_beat_summary_shows_bpm_when_locked() throws {
        let s = try status(followEnabled: true, followValid: true, followBPM: 94.5)
        XCTAssertEqual(s.followBeatSummary, "94.5 BPM")
    }
}
