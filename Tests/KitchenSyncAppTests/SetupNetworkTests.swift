import XCTest
@testable import KitchenSyncApp

/// T-026: a device in SoftAP setup mode isn't on the LAN, so the app recognises it by its
/// setup SSID (to guide/join the AP) and reaches it at the fixed setup address.
final class SetupNetworkTests: XCTestCase {
    func test_the_fleet_setup_aps_are_recognised() {
        XCTAssertTrue(SetupNetwork.isSetupAP(ssid: "KitchenSync-Setup"))  // the P4
        XCTAssertTrue(SetupNetwork.isSetupAP(ssid: "KSTouch-Config"))     // the Touch
    }

    /// A WiFi SSID's case is not meaningful and iOS reports it however the radio saw it.
    func test_matching_is_case_insensitive() {
        XCTAssertTrue(SetupNetwork.isSetupAP(ssid: "kstouch-config"))
        XCTAssertTrue(SetupNetwork.isSetupAP(ssid: "KITCHENSYNC-SETUP"))
    }

    /// The user's own networks — and a stranger's — must never be mistaken for a device AP.
    func test_a_normal_network_is_not_a_setup_ap() {
        XCTAssertFalse(SetupNetwork.isSetupAP(ssid: "Skeyelab"))
        XCTAssertFalse(SetupNetwork.isSetupAP(ssid: "linksys"))
        XCTAssertFalse(SetupNetwork.isSetupAP(ssid: ""))
    }

    func test_the_setup_host_is_the_fixed_softap_address() {
        XCTAssertEqual(SetupNetwork.host, "192.168.4.1")
    }
}
