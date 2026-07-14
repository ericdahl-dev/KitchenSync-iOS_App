import XCTest
@testable import KitchenSyncApp

/// The test this codebase never had, and it is the reason a bug survived a "verified"
/// firmware fix: CLAUDE.md says it out loud — "Nothing has ever spoken to a real
/// device. Every network test runs against a stub."
///
/// Every fixture in this suite was WRITTEN BY ME from a reading of the firmware. That
/// makes them a test of my reading, not of the device. These bytes are different: they
/// are a VERBATIM capture from a KitchenSync Touch (MAC a4:cb:8f:da:df:d0, fw 2.2.0)
/// on 2026-07-14, `curl http://192.168.0.101/status`. Nothing has been prettified,
/// reordered, or filled in.
///
/// The user's report — "play and stop not working... app UI not changing per
/// play/stop" — is exactly what a silently failing `/status` decode looks like from the
/// outside: the buttons still POST (so the device obeys), but `status` stays nil, and
/// `DeviceDetailView` falls back to `.stopped` for every output. The transport works
/// and the screen lies about it.
@MainActor
final class RealTouchStatusTests: XCTestCase {

    /// Captured from the device WHILE STOPPED. Note `launch:[0]` — one output, not four.
    private static let stoppedJSON = """
    {"bpm":123.0,"min":0.0,"peers":1,"usb":false,"tx":935,"fw":"2.2.0","follow_enabled":false,\
    "follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,"launch":[0],"playing":false,\
    "link_owns":false,"drop":0,"burst":0,"gap":1470,"work":215,"over":0,"core":1,"w_beats":47,\
    "w_clock":78,"reprime":0,"clk":"locked","pulses":935,"sync":1,"clock":1,"transport":0,\
    "cue":0,"tfail":0,"tzero":1,"ccancel":0,"wtport":90,"beats":1913.15,"locked":1,\
    "bsactive":1,"btn":-1,"btnlows":0,"btnpress":0}
    """.data(using: .utf8)!

    /// The SAME device, captured mid-song: `launch:[2]`, `playing:true`.
    private static let runningJSON = """
    {"bpm":123.0,"min":0.0,"peers":1,"usb":false,"tx":1137,"fw":"2.2.0","follow_enabled":false,\
    "follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,"launch":[2],"playing":true,\
    "link_owns":false,"drop":0,"burst":0,"gap":1472,"work":222,"over":0,"core":1,"w_beats":43,\
    "w_clock":86,"reprime":0,"clk":"locked","pulses":1137,"sync":1,"clock":1,"transport":2,\
    "cue":0,"tfail":0,"tzero":1,"ccancel":0,"wtport":93,"beats":1921.56,"locked":1,\
    "bsactive":1,"btn":-1,"btnlows":0,"btnpress":0}
    """.data(using: .utf8)!

    /// The BROKEN bytes, kept deliberately. This is what the device sent before the fix:
    /// `link_owns:true` while its transport obeyed every play and stop it was given.
    /// A regression here means the fleet has started lying again.
    private static let lyingLinkOwnsJSON = """
    {"bpm":123.0,"min":0.0,"peers":1,"usb":false,"tx":6372,"fw":"2.2.0","follow_enabled":false,\
    "follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,"launch":[0],"playing":false,\
    "link_owns":true,"drop":0,"burst":0,"gap":1477,"work":234,"over":0,"core":1,"w_beats":42,\
    "w_clock":87,"reprime":0,"clk":"locked","pulses":6372,"sync":1,"clock":1,"transport":0,\
    "cue":0,"tfail":0,"tzero":1,"ccancel":0,"wtport":105,"beats":456.14,"locked":1,\
    "bsactive":1,"btn":-1,"btnlows":0,"btnpress":0}
    """.data(using: .utf8)!

    /// If this throws, the app is BLIND to a real device — and blind in the worst way:
    /// `apply`/`transport` still POST, so the hardware obeys while the screen never moves.
    func test_the_real_touch_status_decodes_at_all() throws {
        XCTAssertNoThrow(try JSONDecoder().decode(KsStatus.self, from: Self.stoppedJSON))
    }

    func test_a_stopped_touch_decodes_as_stopped() throws {
        let s = try JSONDecoder().decode(KsStatus.self, from: Self.stoppedJSON)

        XCTAssertEqual(s.bpm, 123.0)
        XCTAssertEqual(s.peers, 1)
        XCTAssertEqual(s.launch, [.stopped])   // ONE output. The Touch has one jack.
        XCTAssertFalse(s.playing)
    }

    /// THE ONE THAT MATTERS. Press play, and the app must SEE it.
    func test_a_running_touch_decodes_as_running() throws {
        let s = try JSONDecoder().decode(KsStatus.self, from: Self.runningJSON)

        XCTAssertEqual(s.launch, [.running])
        XCTAssertTrue(s.playing)
    }

    /// The Touch reports one output; `maxOutputCount` is 4. The array's LENGTH is the
    /// truth (ESP-030) — nothing may pad it out to four and invent three dead jacks.
    func test_the_launch_array_is_not_padded_to_the_max_output_count() throws {
        let s = try JSONDecoder().decode(KsStatus.self, from: Self.stoppedJSON)
        XCTAssertEqual(s.launch.count, 1)
    }

    // MARK: - "play and stop not working"

    /// THE BUG, reduced to one assertion.
    ///
    /// `link_owns` is a LIVE claim. `ks_status.h`: "when link_owns is true the manual
    /// PLAY/STOP buttons are ignored, so the UI greys them". The app obeys that contract
    /// — `TransportAppearance.acceptsTap = !linkOwned` — and so it refused to even SEND
    /// the tap.
    ///
    /// But the Touch was passing `link_proto_start_stop_seen()`, which is STICKY: "has a
    /// peer EVER published a StartStopState", latched true until the last peer leaves.
    /// And `ktouch_transport.c` never consults Link start/stop at all — measured on the
    /// bench, the device obeys POST /transport every single time, stopped -> armed ->
    /// running, with link_owns true throughout.
    ///
    /// So the device claimed "I ignore your play button" while cheerfully obeying it, and
    /// the app believed the claim. A HISTORICAL flag published as a LIVE state — the same
    /// bug as T-018 (lifetime droppedTicks shown as a live fault) and ESP-028 (sync:1
    /// over a wire that had been dead for 138 seconds).
    func test_the_app_can_start_a_stopped_touch() throws {
        let s = try JSONDecoder().decode(KsStatus.self, from: Self.stoppedJSON)

        let button = TransportAppearance.appearance(for: s.launch[0],
                                                    linkOwned: s.linkOwnsTransport)

        XCTAssertTrue(button.acceptsTap,
                      "the device obeys play/stop — a UI that greys the button is lying to the user")
    }

    /// ...and it must be able to stop it again.
    func test_the_app_can_stop_a_running_touch() throws {
        let s = try JSONDecoder().decode(KsStatus.self, from: Self.runningJSON)

        let button = TransportAppearance.appearance(for: s.launch[0],
                                                    linkOwned: s.linkOwnsTransport)

        XCTAssertTrue(button.acceptsTap)
        XCTAssertEqual(button.label, "PLAYING")
    }

    /// The app's contract-following is NOT the bug, and must not be "fixed" away.
    ///
    /// If a device genuinely does defer to Link — the P4 does, via ks_tick arbitration —
    /// then `link_owns:true` is true, its manual buttons really are ignored, and greying
    /// them is correct: a button that does nothing is worse than a button that says so.
    /// The Touch's mistake was CLAIMING that while obeying anyway.
    func test_a_device_that_really_does_defer_to_link_still_greys_the_button() throws {
        let s = try JSONDecoder().decode(KsStatus.self, from: Self.lyingLinkOwnsJSON)

        let button = TransportAppearance.appearance(for: s.launch[0],
                                                    linkOwned: s.linkOwnsTransport)

        XCTAssertFalse(button.acceptsTap,
                       "link_owns is a LIVE claim; honouring it is right. The fix belongs in whoever LIES.")
    }

    /// The Touch has no Link-phase block (`xf*`), so `phaseHealth` must be nil rather
    /// than a row of flattering zeroes — and its ABSENCE must not fail the whole decode,
    /// which is the trap that would take the entire screen down with it.
    func test_a_missing_phase_block_does_not_sink_the_decode() throws {
        let s = try JSONDecoder().decode(KsStatus.self, from: Self.stoppedJSON)
        XCTAssertNil(s.phaseHealth)
        XCTAssertNotNil(s.tickHealth, "the Touch DOES send the tick block")
    }
}
