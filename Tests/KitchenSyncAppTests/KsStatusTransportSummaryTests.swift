import XCTest
@testable import KitchenSyncApp

/// TDD: written before `KsStatus.transportSummary` exists.
///
/// The fleet list needs one word per device: is it stopped, arming, or playing?
/// Deriving that is real logic — it depends on WHO owns transport — so it lives on
/// the model where it can be asserted, not inside a `View`. The device's own web UI
/// derives it the same way (`ks_web.cpp`).
///
/// It matters because an ARMING device must be identifiable from the fleet screen
/// without drilling in: a quantized start is pending and hasn't fired yet.
final class KsStatusTransportSummaryTests: XCTestCase {
    private func status(launch: [Int], playing: Bool, linkOwns: Bool) throws -> KsStatus {
        let json = """
        {"bpm":128.0,"min":0.0,"peers":2,"usb":true,"tx":1,"fw":"1.2.3",
         "follow_enabled":false,"follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,
         "launch":\(launch),"playing":\(playing),"link_owns":\(linkOwns)}
        """
        return try JSONDecoder().decode(KsStatus.self, from: Data(json.utf8))
    }

    func test_all_outputs_stopped_reads_stopped() throws {
        let s = try status(launch: [0, 0, 0, 0], playing: false, linkOwns: false)
        XCTAssertEqual(s.transportSummary, .stopped)
    }

    func test_any_running_output_reads_playing() throws {
        let s = try status(launch: [0, 0, 2, 0], playing: false, linkOwns: false)
        XCTAssertEqual(s.transportSummary, .playing)
    }

    func test_any_armed_output_reads_arming() throws {
        let s = try status(launch: [0, 1, 0, 0], playing: false, linkOwns: false)
        XCTAssertEqual(s.transportSummary, .arming)
    }

    /// Running WINS over arming. A device with one output already playing and
    /// another still waiting for the bar line is playing — the list must not
    /// report it as merely pending.
    func test_running_beats_arming() throws {
        let s = try status(launch: [1, 2, 0, 0], playing: false, linkOwns: false)
        XCTAssertEqual(s.transportSummary, .playing)
    }

    // MARK: Link owns transport
    //
    // When Link drives transport, the session's `playing` flag is the truth for
    // the device as a whole, and it takes precedence over the per-output launch
    // array. The device's own web UI derives it in exactly this order.

    func test_link_owned_and_playing_reads_playing() throws {
        let s = try status(launch: [0, 0, 0, 0], playing: true, linkOwns: true)
        XCTAssertEqual(s.transportSummary, .playing)
    }

    func test_link_owned_and_not_playing_reads_stopped() throws {
        let s = try status(launch: [0, 0, 0, 0], playing: false, linkOwns: true)
        XCTAssertEqual(s.transportSummary, .stopped)
    }

    /// The precedence test. Link owns transport and is NOT playing, but an output
    /// still shows as running. Link's flag wins — the launch array is stale or
    /// belongs to an output that isn't following Link, and reporting "playing" off
    /// it would contradict the session.
    func test_link_ownership_takes_precedence_over_the_launch_array() throws {
        let s = try status(launch: [2, 0, 0, 0], playing: false, linkOwns: true)
        XCTAssertEqual(s.transportSummary, .stopped)
    }
}
