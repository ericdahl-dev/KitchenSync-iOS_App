import XCTest
@testable import KitchenSyncApp

/// Fixtures are hand-built to match `ks_status_json()`'s exact snprintf format
/// string (`link-devices/KitchenSync/main/ks_status.c`), not just "plausible
/// JSON" — a field this decoder gets wrong fails silently (Codable just throws
/// on the whole payload, or worse, decodes the wrong key into the wrong field).
final class KsStatusDecodingTests: XCTestCase {
    func test_decodes_all_fields_without_tick_or_phase_health() throws {
        let json = """
        {"bpm":132.0,"min":120.5,"peers":1,"usb":true,"tx":583,"fw":"2.2.0",\
        "follow_enabled":true,"follow_bpm":128.3,"follow_confidence":3.1,"follow_valid":true,\
        "launch":[2,1,0,0],"playing":true,"link_owns":false}
        """
        let status = try JSONDecoder().decode(KsStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.bpm, 132.0)
        XCTAssertEqual(status.midiClockInBPM, 120.5)   // the "min" key
        XCTAssertEqual(status.peers, 1)
        XCTAssertTrue(status.usbConnected)
        XCTAssertEqual(status.clockPulseCount, 583)
        XCTAssertEqual(status.firmwareVersion, "2.2.0")
        XCTAssertTrue(status.followBeatEnabled)
        XCTAssertEqual(status.followBeatBPM, 128.3)
        XCTAssertEqual(status.followBeatConfidence, 3.1)
        XCTAssertTrue(status.followBeatValid)
        XCTAssertEqual(status.launch, [.running, .armed, .stopped, .stopped])
        XCTAssertTrue(status.playing)
        XCTAssertFalse(status.linkOwnsTransport)
        XCTAssertNil(status.tickHealth)
        XCTAssertNil(status.phaseHealth)
    }

    func test_decodes_tick_and_phase_health_when_present() throws {
        let json = """
        {"bpm":0.0,"min":0.0,"peers":0,"usb":false,"tx":0,"fw":"2.2.0",\
        "follow_enabled":false,"follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,\
        "launch":[0,0,0,0],"playing":false,"link_owns":false,\
        "drop":1,"burst":2,"gap":300,"work":40,"over":5,"core":1,"w_beats":600,"w_clock":700,"reprime":8,\
        "xf":9,"xf_step":1000,"xf_max":2000,"rtt_min":10,"rtt_max":210}
        """
        let status = try JSONDecoder().decode(KsStatus.self, from: Data(json.utf8))
        let tick = try XCTUnwrap(status.tickHealth)
        XCTAssertEqual(tick.droppedTicks, 1)
        XCTAssertEqual(tick.bursts, 2)
        XCTAssertEqual(tick.maxGapMicros, 300)
        XCTAssertEqual(tick.maxWorkMicros, 40)
        XCTAssertEqual(tick.overruns, 5)
        XCTAssertEqual(tick.core, 1)
        XCTAssertEqual(tick.beatsWritten, 600)
        XCTAssertEqual(tick.clockPulsesWritten, 700)
        XCTAssertEqual(tick.reprimes, 8)

        let phase = try XCTUnwrap(status.phaseHealth)
        XCTAssertEqual(phase.commits, 9)
        XCTAssertEqual(phase.lastStepMicros, 1000)
        XCTAssertEqual(phase.maxStepMicros, 2000)
        XCTAssertEqual(phase.rttMinMicros, 10)
        XCTAssertEqual(phase.rttMaxMicros, 210)
    }

    // ESP-011: launch is per-output quantized state, 0 stopped / 1 armed / 2
    // running — an unrecognized value should never crash the app, just fall
    // back to a safe "stopped" render rather than propagating a decode failure
    // that would take the whole status payload down with it.
    func test_unknown_launch_value_falls_back_to_stopped() throws {
        let json = """
        {"bpm":0.0,"min":0.0,"peers":0,"usb":false,"tx":0,"fw":"2.2.0",\
        "follow_enabled":false,"follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,\
        "launch":[9,0,0,0],"playing":false,"link_owns":false}
        """
        let status = try JSONDecoder().decode(KsStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.launch.first, .stopped)
    }
}
