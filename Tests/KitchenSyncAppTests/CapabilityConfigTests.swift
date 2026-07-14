import XCTest
@testable import KitchenSyncApp

/// TDD: written before `KsConfig` can decode a device that doesn't have everything.
///
/// **A device must not report hardware it does not have** (`link-devices` ESP-030). Absent
/// hardware is ABSENT from `/config.json`, never reported `false` — emitting `led:false` on a
/// board with no strip is the same class of lie as the firmware's `sync:1` over a wire that had
/// been dead for 138 seconds, and this app would dutifully draw an LED section for a device that
/// cannot light anything.
///
/// So the app must decode an HONEST document. Today `KsConfig` requires every field, so it throws
/// on one — which would mean the firmware told the truth and the app called it broken.
///
/// And capability belongs to the BUILD, not the product: solder a strip onto that Touch, flip one
/// firmware flag, and the LED section must appear here **with no app change at all.**
final class CapabilityConfigTests: XCTestCase {
    /// The REAL Touch's `/config.json`, captured verbatim from `kstouch-dfd0` on 2026-07-14.
    /// No metronome, no LED, no follow-beat, one clock output, three WiFi slots.
    static let realTouchConfigJSON = """
    {"clock_out":true,
     "wifi":[{"ssid":"Bench-2G","pass_set":true},{"ssid":"","pass_set":false},{"ssid":"","pass_set":false}],
     "clock":[{"en":true,"cable":0,"ppqn":24,"phase":0,"swing":0,"follow":false}]}
    """.data(using: .utf8)!

    func test_a_device_without_a_speaker_or_strip_still_decodes() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Self.realTouchConfigJSON)

        XCTAssertTrue(config.clockOutEnabled)
        XCTAssertEqual(config.wifi.count, 3)
        XCTAssertEqual(config.wifi[0].ssid, "Bench-2G")
        XCTAssertTrue(config.wifi[0].passwordIsSet)
    }

    /// Absent means ABSENT — not `false`. `false` would mean "there is a metronome and it is
    /// switched off", which is a different (and untrue) statement.
    func test_hardware_the_device_lacks_reads_as_absent_not_false() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Self.realTouchConfigJSON)

        XCTAssertNil(config.metronome, "no speaker is fitted — this is not 'a metronome, off'")
        XCTAssertNil(config.led, "no strip is wired")
        XCTAssertNil(config.followBeatEnabled, "no mic is fitted")
    }

    /// The clock array's LENGTH is the device's real output count. The Touch has ONE.
    func test_the_output_count_comes_from_the_array_not_a_constant() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Self.realTouchConfigJSON)

        XCTAssertEqual(config.clock.count, 1, "one DIN jack — render one card, not four")
    }
}
