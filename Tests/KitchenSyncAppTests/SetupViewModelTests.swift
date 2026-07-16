import XCTest
@testable import KitchenSyncApp

/// T-026: the first-run setup flow's decision logic — confirm a device is on its setup AP,
/// then hand it the user's WiFi. Driven through the real client against `StubURLProtocol`.
@MainActor
final class SetupViewModelTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }

    private static let configJSON = """
    {"clock_out":true,
     "wifi":[{"ssid":"","pass_set":false}],
     "clock":[{"en":true,"cable":0,"ppqn":24,"phase":0,"swing":0,"follow":true}]}
    """.data(using: .utf8)!

    private func vm() -> SetupViewModel {
        SetupViewModel(session: StubURLProtocol.session())
    }

    // A device on its setup AP answers /config.json — that's how the app confirms it's ours
    // before offering setup (rather than showing a setup screen for an empty AP).
    func test_search_confirms_a_device_when_config_answers() async {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        let vm = vm()
        await vm.search()
        XCTAssertEqual(vm.phase, .foundDevice)
    }

    // Nothing at 192.168.4.1 (or not ours) → say so, don't pretend a device is there.
    func test_search_reports_no_device_when_nothing_answers() async {
        StubURLProtocol.routes["GET /config.json"] = .init(status: 404)
        let vm = vm()
        await vm.search()
        XCTAssertEqual(vm.phase, .noDevice)
    }

    // Provisioning hands the device the creds and lands in `provisioned` — the device is now
    // rebooting to join; the list view takes over the reconnect + rediscovery.
    func test_provision_success_posts_wifi_and_advances() async throws {
        StubURLProtocol.routes["POST /save"] = .init()
        let vm = vm()
        await vm.provision(ssid: "StudioNet", password: "downbeat99")
        XCTAssertEqual(vm.phase, .provisioned)

        let req = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(req.url.path, "/save")
    }

    // A failed /save must surface — the user needs to know it didn't take, not sit on a spinner.
    func test_provision_failure_reports_it() async {
        StubURLProtocol.routes["POST /save"] = .init(status: 500)
        let vm = vm()
        await vm.provision(ssid: "X", password: "Y")
        guard case .failed = vm.phase else {
            return XCTFail("expected .failed, got \(vm.phase)")
        }
    }

    // A blank SSID is not a provisioning attempt — don't fire a request or lie about success.
    func test_blank_ssid_does_not_provision() async {
        let vm = vm()
        await vm.provision(ssid: "", password: "pw")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertNotEqual(vm.phase, .provisioned)
    }
}
