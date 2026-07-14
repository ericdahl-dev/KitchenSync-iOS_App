import XCTest
@testable import KitchenSyncApp

/// Locks `KsLiveEdit.formField` to the exact key grammar `ks_config_set()`
/// (`link-devices/KitchenSync/main/ks_config.c`) parses. A typo here is
/// invisible until it silently fails to apply on a real device — a form key
/// the firmware doesn't recognize is a no-op, not an error.
final class KsLiveEditTests: XCTestCase {
    func test_top_level_boolean_fields() {
        XCTAssertTrue(KsLiveEdit.clockOutEnabled(true).formField == ("clock_out", "1"))
        XCTAssertTrue(KsLiveEdit.clockOutEnabled(false).formField == ("clock_out", "0"))
        XCTAssertTrue(KsLiveEdit.metronomeAccent(true).formField == ("metro_accent", "1"))
        XCTAssertTrue(KsLiveEdit.ledEnabled(false).formField == ("led", "0"))
    }

    func test_top_level_value_fields() {
        XCTAssertTrue(KsLiveEdit.metronomeVolume(80).formField == ("metro_vol", "80"))
        XCTAssertTrue(KsLiveEdit.metronomeVoice(2).formField == ("metro_voice", "2"))
        XCTAssertTrue(KsLiveEdit.ledBrightness(60).formField == ("led_bright", "60"))
        XCTAssertTrue(KsLiveEdit.ledMode(1).formField == ("led_mode", "1"))
        XCTAssertTrue(KsLiveEdit.ledFade(55).formField == ("led_fade", "55"))
    }

    // ks_config_set() parses "#rrggbb" (leading '#' required by the firmware's
    // own writer, though its reader also accepts a bare hex string).
    func test_led_colors_encode_as_hash_prefixed_uppercase_hex() {
        XCTAssertTrue(KsLiveEdit.ledBeatColor(0x00B400).formField == ("led_beat", "#00B400"))
        XCTAssertTrue(KsLiveEdit.ledAccentColor(0xDC6E00).formField == ("led_accent", "#DC6E00"))
    }

    // Per-output fields: "clk<N>_en|cable|ppqn|phase|swing|follow".
    func test_per_output_fields_use_clkN_prefix() {
        XCTAssertTrue(KsLiveEdit.outputEnabled(index: 0, true).formField == ("clk0_en", "1"))
        XCTAssertTrue(KsLiveEdit.outputCable(index: 2, 3).formField == ("clk2_cable", "3"))
        XCTAssertTrue(KsLiveEdit.outputPPQN(index: 1, 24).formField == ("clk1_ppqn", "24"))
        XCTAssertTrue(KsLiveEdit.outputPhase(index: 3, -100).formField == ("clk3_phase", "-100"))
        XCTAssertTrue(KsLiveEdit.outputSwing(index: 0, 125).formField == ("clk0_swing", "125"))
        XCTAssertTrue(KsLiveEdit.outputFollowsLink(index: 1, false).formField == ("clk1_follow", "0"))
    }
}
