import XCTest
@testable import KitchenSyncApp

/// TDD: written before `KsConfig.seededWifiEdits()` exists.
///
/// The settings sheet has to turn the device's WiFi slots into editable rows. That
/// conversion is where a password can get leaked, erased, or written to the wrong
/// network — so it's logic, and it belongs on the model with tests, not inlined in a
/// sheet's `onAppear`.
///
/// Three invariants, all of which the firmware forces:
/// 1. A password is NEVER readable. `/config.json` omits it; `WifiSlot` only knows
///    `passwordIsSet`. So a seeded edit's password is always empty.
/// 2. Empty password means "keep the saved one" — `saveFormFields` omits the field
///    entirely, which is `ks_config_set`'s documented no-op. So seeding blank is not
///    a data-loss bug; it's the correct default.
/// 3. Edits are keyed by SLOT ID, never array position. `saveFormFields` picks the
///    `wifi_ssid` / `wifi_ssid1` / `wifi_ssid2` suffix off the id, and getting that
///    wrong silently overwrites the wrong saved network.
final class WifiEditSeedingTests: XCTestCase {
    private func config(ssids: [String], passSet: [Bool]) throws -> KsConfig {
        let slots = zip(ssids, passSet)
            .map { "{\"ssid\":\"\($0)\",\"pass_set\":\($1)}" }
            .joined(separator: ",")
        let json = """
        {"clock_out":true,"metronome":false,"metro_accent":true,"metro_vol":80,\
        "metro_voice":0,"led":false,"led_bright":60,"led_mode":0,"led_fade":55,\
        "led_beat":"#00B400","led_accent":"#DC6E00","follow_beat":false,\
        "wifi":[\(slots)],\
        "clock":[{"en":true,"cable":0,"ppqn":24,"phase":0,"swing":0,"follow":true},\
        {"en":false,"cable":1,"ppqn":24,"phase":0,"swing":0,"follow":true},\
        {"en":false,"cable":2,"ppqn":24,"phase":0,"swing":0,"follow":true},\
        {"en":false,"cable":3,"ppqn":24,"phase":0,"swing":0,"follow":true}]}
        """
        return try JSONDecoder().decode(KsConfig.self, from: Data(json.utf8))
    }

    func test_seeds_one_edit_per_slot_keyed_by_slot_id() throws {
        let c = try config(ssids: ["Backline", "Green", ""], passSet: [true, false, false])

        let edits = c.seededWifiEdits()

        XCTAssertEqual(edits.map(\.id), [0, 1, 2])
        XCTAssertEqual(edits.map(\.ssid), ["Backline", "Green", ""])
    }

    /// The one that matters. A seeded password is ALWAYS empty — the real one was
    /// never on the wire and cannot be.
    func test_seeded_passwords_are_always_empty_even_when_one_is_set() throws {
        let c = try config(ssids: ["Backline", "Green", ""], passSet: [true, true, false])

        let edits = c.seededWifiEdits()

        XCTAssertEqual(edits.map(\.password), ["", "", ""])
    }

    /// Round-trip: seed, change nothing, save. No `wifi_pass` field may be sent —
    /// which is what makes "blank means keep" work rather than wiping the password.
    func test_saving_untouched_seeded_edits_does_not_send_any_password() throws {
        let c = try config(ssids: ["Backline", "Green", ""], passSet: [true, false, false])

        let fields = c.saveFormFields(wifiEdits: c.seededWifiEdits())

        XCTAssertNil(fields["wifi_pass"])
        XCTAssertNil(fields["wifi_pass1"])
        XCTAssertNil(fields["wifi_pass2"])
        // The SSIDs still ride along — they're readable, so they round-trip.
        XCTAssertEqual(fields["wifi_ssid"], "Backline")
        XCTAssertEqual(fields["wifi_ssid1"], "Green")
    }

    /// Typing a new password into slot 1 must land on slot 1's key, not slot 0's.
    func test_a_typed_password_lands_on_its_own_slot() throws {
        let c = try config(ssids: ["Backline", "Green", ""], passSet: [true, true, false])
        var edits = c.seededWifiEdits()
        edits[1].password = "newpassword"

        let fields = c.saveFormFields(wifiEdits: edits)

        XCTAssertNil(fields["wifi_pass"], "slot 0's password must be untouched")
        XCTAssertEqual(fields["wifi_pass1"], "newpassword")
    }
}
