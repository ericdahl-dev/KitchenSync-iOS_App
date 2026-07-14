import XCTest
@testable import KitchenSyncApp

final class FormURLEncodingTests: XCTestCase {
    func test_simple_pair_encodes_unquoted() {
        let data = FormURLEncoding.encode(["clock_out": "1"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "clock_out=1")
    }

    func test_multiple_pairs_are_sorted_by_key_and_joined_with_ampersand() {
        let data = FormURLEncoding.encode(["b": "2", "a": "1"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "a=1&b=2")
    }

    /// A literal space becomes %20, never a bare `+` — the firmware decoder
    /// (`ks_form.c`'s `url_decode`) treats `+` as space, so emitting a raw `+`
    /// for a value that already contains one (e.g. a WiFi password) would
    /// silently turn it into a space on the device. %XX side-steps the
    /// ambiguity entirely.
    func test_space_encodes_as_percent20() {
        let data = FormURLEncoding.encode(["wifi_ssid": "My Network"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "wifi_ssid=My%20Network")
    }

    func test_plus_in_value_is_percent_encoded_not_left_literal() {
        let data = FormURLEncoding.encode(["wifi_pass": "a+b"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "wifi_pass=a%2Bb")
    }

    func test_hash_in_color_value_is_percent_encoded() {
        let data = FormURLEncoding.encode(["led_beat": "#00B400"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "led_beat=%2300B400")
    }

    func test_empty_fields_encode_to_empty_data() {
        let data = FormURLEncoding.encode([:])
        XCTAssertEqual(data, Data())
    }
}
