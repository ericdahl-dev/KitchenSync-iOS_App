import XCTest
@testable import KitchenSyncApp

/// TDD: written before `DeviceMatch` exists.
///
/// **This is the bug a real device found.** On 2026-07-14 a KitchenSync Touch was put on the LAN.
/// It advertises as `kstouch-dfd0`. `KitchenSyncDiscovery` filtered with
/// `hasPrefix("kitchensync-")`, so the device was not shown wrong or shown offline — it was
/// **invisible**. The prefix heuristic failed on the first real hardware the app ever met.
///
/// The decision lives here, as a pure function over (serviceName, txt), so it can be asserted
/// without standing up Bonjour. The `NWBrowser` glue stays dumb.
final class DeviceMatchTests: XCTestCase {
    func test_a_touch_is_matched_by_its_hostname_when_there_is_no_txt_record() {
        XCTAssertTrue(DeviceMatch.isKitchenSync(serviceName: "kstouch-dfd0", txt: nil),
                      "a real Touch on the bench was invisible to the app because of this")
    }

    /// **A real P4 found this.** The ESP32-P4 advertises its Bonjour INSTANCE NAME as
    /// "KitchenSync" (capital K, a friendly name), not the lowercase hostname the Touch
    /// and X32Link use. hasPrefix is case-sensitive, so `"KitchenSync".hasPrefix(
    /// "kitchensync")` is false and the P4 was invisible. A Bonjour name's case is not
    /// meaningful; the match must be case-insensitive.
    func test_the_p4_is_matched_despite_a_capitalised_instance_name() {
        XCTAssertTrue(DeviceMatch.isKitchenSync(serviceName: "KitchenSync", txt: nil))
        XCTAssertTrue(DeviceMatch.isKitchenSync(serviceName: "KSTouch-DFD0", txt: nil))
    }

    /// Units already in the field have no TXT record and won't until they're reflashed. Breaking
    /// them would be a worse bug than the one being fixed.
    func test_the_existing_devices_still_match_on_hostname() {
        XCTAssertTrue(DeviceMatch.isKitchenSync(serviceName: "kitchensync-a4f2", txt: nil))
        XCTAssertTrue(DeviceMatch.isKitchenSync(serviceName: "kitchensync", txt: nil),
                      "the delegated single-board alias")
    }

    func test_someone_elses_http_responder_is_not_adopted() {
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "brother-printer", txt: nil))
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "", txt: nil))
    }

    // MARK: TXT beats the hostname (link-devices ESP-031)
    //
    // Once firmware advertises `dev=kitchensync`, identity is a FACT rather than a guess. The
    // hostname stops being evidence at all.

    func test_txt_identifies_a_device_whatever_it_is_called() {
        XCTAssertTrue(DeviceMatch.isKitchenSync(serviceName: "some-renamed-box",
                                                txt: ["dev": "kitchensync"]),
                      "TXT is the truth; the hostname is not consulted when it's present")
    }

    /// **The failure the prefix heuristic can't prevent.** At a venue, a stranger's box named
    /// `kitchensync-whatever` gets adopted straight into the fleet. Once TXT exists, it must not.
    func test_a_stranger_named_like_us_is_rejected_once_txt_is_available() {
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "kitchensync-imposter",
                                                 txt: ["dev": "some-other-product"]),
                       "a TXT record that says it ISN'T ours must beat a hostname that says it is")
    }

    /// X32Link is a SEPARATE product with its own app — this KitchenSync app must NOT show
    /// it, by hostname OR by its (now `dev=x32link`) TXT. It was briefly included (ESP-035)
    /// before the product line was clarified.
    func test_the_x32link_is_not_shown_in_the_kitchensync_app() {
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "x32link-7a1c", txt: nil))
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "X32Link", txt: nil))
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "x32link-6160",
                                                 txt: ["dev": "x32link", "model": "x32link"]))
    }

    /// The prefix is still a HEURISTIC, and it must not swallow the whole network. A
    /// stranger's box at a venue is not ours.
    func test_a_stranger_is_still_not_one_of_ours() {
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "brother-printer", txt: nil))
        XCTAssertFalse(DeviceMatch.isKitchenSync(serviceName: "x32-mixer", txt: nil))
    }
}
