import XCTest
@testable import KitchenSyncApp

/// Fixture matches `ks_config_json()`'s exact output shape
/// (`link-devices/KitchenSync/main/ks_config_json.c`) — three wifi slots, four
/// clock outputs, hash-prefixed hex colors, passwords never present.
private let sampleConfigJSON = """
{"clock_out":true,"metronome":false,"metro_accent":true,"metro_vol":80,\
"metro_voice":0,"led":false,"led_bright":60,"led_mode":0,"led_fade":55,\
"led_beat":"#00B400","led_accent":"#DC6E00","follow_beat":false,\
"wifi":[{"ssid":"TestNet","pass_set":true},{"ssid":"","pass_set":false},{"ssid":"","pass_set":false}],\
"clock":[{"en":true,"cable":0,"ppqn":24,"phase":0,"swing":0,"follow":true},\
{"en":false,"cable":1,"ppqn":24,"phase":0,"swing":0,"follow":true},\
{"en":false,"cable":2,"ppqn":24,"phase":0,"swing":0,"follow":true},\
{"en":false,"cable":3,"ppqn":24,"phase":0,"swing":0,"follow":true}]}
"""

final class KsConfigDecodingTests: XCTestCase {
    func test_decodes_top_level_fields() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        XCTAssertTrue(config.clockOutEnabled)
        XCTAssertEqual(config.metronome?.enabled, false)
        XCTAssertEqual(config.metronome?.accent, true)
        XCTAssertEqual(config.metronome?.volume, 80)
        XCTAssertEqual(config.metronome?.voice, 0)
        XCTAssertEqual(config.led?.enabled, false)
        XCTAssertEqual(config.led?.brightness, 60)
        XCTAssertEqual(config.led?.mode, 0)
        XCTAssertEqual(config.led?.fade, 55)
        XCTAssertEqual(config.followBeatEnabled, false)
    }

    // ESP-037: the stored free-run tempo. A clock box emits `bpm`; the app shows THIS
    // number (distinct from the Link-driven KsStatus.bpm).
    func test_decodes_the_stored_tempo_from_bpm() throws {
        let json = #"{"clock_out":true,"bpm":128.500,"wifi":[],"clock":[]}"#
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.tempo ?? 0, 128.5, accuracy: 0.001)
    }

    // A listener-only board (X32Link) omits `bpm` entirely — tempo is nil, not 0, so the
    // app knows to hide the tempo control rather than show a fake 0 BPM.
    func test_a_config_without_bpm_has_nil_tempo() throws {
        let json = #"{"clock_out":false,"wifi":[],"clock":[]}"#
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(json.utf8))
        XCTAssertNil(config.tempo)
    }

    func test_decodes_hash_prefixed_hex_colors() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        XCTAssertEqual(config.led?.beatColor, 0x00B400)
        XCTAssertEqual(config.led?.accentColor, 0xDC6E00)
    }

    func test_decodes_wifi_slots_in_order_without_ever_seeing_a_password() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        XCTAssertEqual(config.wifi.count, 3)
        XCTAssertEqual(config.wifi[0].ssid, "TestNet")
        XCTAssertTrue(config.wifi[0].passwordIsSet)
        XCTAssertEqual(config.wifi[1].ssid, "")
        XCTAssertFalse(config.wifi[1].passwordIsSet)
    }

    func test_decodes_four_clock_outputs_in_order() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        XCTAssertEqual(config.clock.count, 4)
        XCTAssertTrue(config.clock[0].enabled)
        XCTAssertEqual(config.clock[0].cable, 0)
        XCTAssertFalse(config.clock[1].enabled)
        XCTAssertEqual(config.clock[3].cable, 3)
    }
}

final class KsConfigSaveFormFieldsTests: XCTestCase {
    func test_every_boolean_is_sent_explicitly_not_omitted() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        let fields = config.saveFormFields(wifiEdits: [])
        // Unlike an HTML form, this client never relies on "absent checkbox
        // means off" -- ks_config_set() parses booleans by value, so every
        // boolean field must appear with an explicit "0" or "1".
        XCTAssertEqual(fields["metronome"], "0")   // false, but still present
        XCTAssertEqual(fields["clock_out"], "1")
        XCTAssertEqual(fields["clk1_en"], "0")
    }

    func test_wifi_password_omitted_when_edit_leaves_it_blank() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        let edits = [WifiCredentialEdit(id: 0, ssid: "TestNet", password: "")]
        let fields = config.saveFormFields(wifiEdits: edits)
        XCTAssertEqual(fields["wifi_ssid"], "TestNet")
        XCTAssertNil(fields["wifi_pass"])   // blank means "keep current" on the firmware
    }

    func test_wifi_password_included_when_edit_sets_one() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        let edits = [WifiCredentialEdit(id: 0, ssid: "TestNet", password: "hunter2")]
        let fields = config.saveFormFields(wifiEdits: edits)
        XCTAssertEqual(fields["wifi_pass"], "hunter2")
    }

    // Slot 0 keeps the unsuffixed key names; slots 1/2 are suffixed.
    func test_wifi_slot_suffix_convention() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        let edits = [
            WifiCredentialEdit(id: 0, ssid: "Net0"),
            WifiCredentialEdit(id: 1, ssid: "Net1"),
            WifiCredentialEdit(id: 2, ssid: "Net2"),
        ]
        let fields = config.saveFormFields(wifiEdits: edits)
        XCTAssertEqual(fields["wifi_ssid"], "Net0")
        XCTAssertEqual(fields["wifi_ssid1"], "Net1")
        XCTAssertEqual(fields["wifi_ssid2"], "Net2")
    }

    func test_per_output_fields_present_for_all_four_outputs() throws {
        let config = try JSONDecoder().decode(KsConfig.self, from: Data(sampleConfigJSON.utf8))
        let fields = config.saveFormFields(wifiEdits: [])
        for index in 0..<KsConfig.maxOutputCount {
            XCTAssertNotNil(fields["clk\(index)_en"])
            XCTAssertNotNil(fields["clk\(index)_cable"])
            XCTAssertNotNil(fields["clk\(index)_ppqn"])
            XCTAssertNotNil(fields["clk\(index)_phase"])
            XCTAssertNotNil(fields["clk\(index)_swing"])
            XCTAssertNotNil(fields["clk\(index)_follow"])
        }
    }
}
