import XCTest
@testable import KitchenSyncApp

/// TDD, and written straight out of a bug report: "nudge and swing buttons not working".
///
/// They were not working because the Touch had no `/live` endpoint — every POST came
/// back 404. But that is NOT why the user couldn't tell what was wrong. `apply()` was
/// `try? await client.postLive(edit)`: the 404 was CAUGHT AND DROPPED. The app showed
/// a stepper that moved, no error, and a device that never changed.
///
/// This is the same error class as T-018 and T-009 — two situations collapsed into one
/// signal. Here it's worse than a wrong signal: it's NO signal. The device said "I have
/// never heard of that endpoint" as loudly as HTTP can, and the app said nothing.
///
/// Two rules, and the failure case is the one that actually earns its keep:
///   success → the displayed value becomes the value we sent (or the UI looks frozen)
///   failure → the user is TOLD, and the display stays at the device's truth. Never
///             leave a stepper showing a number the device does not have.
@MainActor
final class LiveEditFeedbackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeVM() -> DeviceDetailViewModel {
        DeviceDetailViewModel(
            client: KitchenSyncClient(host: "kstouch-dfd0.local",
                                      session: StubURLProtocol.session())
        )
    }

    /// A one-output device, phase and swing at zero — the Touch, as shipped.
    /// Dummy SSID: a fixture is a public artifact (repo, CI log, PR diff), and the real
    /// network's name has no business in one.
    private static let configJSON = """
    {"clock_out":false,
     "wifi":[{"ssid":"Bench-2G","pass_set":true}],
     "clock":[{"en":false,"cable":0,"ppqn":24,"phase":0,"swing":0,"follow":true}]}
    """.data(using: .utf8)!

    private func loadedVM() async -> DeviceDetailViewModel {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        let vm = makeVM()
        await vm.loadConfig()
        return vm
    }

    // MARK: - THE BUG

    /// The exact shape of the reported bug: firmware with no `/live` route. The app
    /// must not shrug this off.
    func test_a_404_from_live_is_reported_not_swallowed() async {
        let vm = await loadedVM()
        StubURLProtocol.routes["POST /live"] = .init(status: 404)

        await vm.apply(.outputPhase(index: 0, -40))

        XCTAssertNotNil(vm.liveEditFailure,
                        "a 404 from /live must surface — swallowing it is what made this bug invisible")
    }

    /// ...and the stepper must not sit there displaying a nudge the device never took.
    func test_a_failed_live_edit_leaves_the_displayed_value_at_the_devices_truth() async {
        let vm = await loadedVM()
        StubURLProtocol.routes["POST /live"] = .init(status: 404)

        await vm.apply(.outputPhase(index: 0, -40))

        XCTAssertEqual(vm.config?.clock[0].phaseMilliBeats, 0,
                       "the device is still at 0; showing -40 would be a lie")
    }

    /// A transport error (device unplugged mid-edit) is a failure too. The user does
    /// not care WHICH way it failed — they care that it did.
    func test_a_transport_error_from_live_is_reported() async {
        let vm = await loadedVM()
        StubURLProtocol.routes["POST /live"] = .init(status: 500)

        await vm.apply(.outputSwing(index: 0, 90))

        XCTAssertNotNil(vm.liveEditFailure)
        XCTAssertEqual(vm.config?.clock[0].swingMilliBeats, 0)
    }

    // MARK: - THE HAPPY PATH

    /// Even a WORKING /live looked broken: nothing updated the local config, so the
    /// value on screen never moved. The edit we just made must be reflected.
    func test_a_successful_live_edit_updates_the_displayed_value() async {
        let vm = await loadedVM()
        StubURLProtocol.routes["POST /live"] = .init()

        await vm.apply(.outputPhase(index: 0, -40))

        XCTAssertEqual(vm.config?.clock[0].phaseMilliBeats, -40)
        XCTAssertNil(vm.liveEditFailure)
    }

    func test_a_successful_live_edit_updates_swing_too() async {
        let vm = await loadedVM()
        StubURLProtocol.routes["POST /live"] = .init()

        await vm.apply(.outputSwing(index: 0, 90))

        XCTAssertEqual(vm.config?.clock[0].swingMilliBeats, 90)
    }

    /// A success after a failure must CLEAR the failure. Otherwise the error banner is
    /// permanent — the T-018 mistake (a lifetime counter shown as a live fault) all
    /// over again.
    func test_a_successful_edit_clears_a_previous_failure() async {
        let vm = await loadedVM()
        StubURLProtocol.routes["POST /live"] = .init(status: 404)
        await vm.apply(.outputPhase(index: 0, -40))
        XCTAssertNotNil(vm.liveEditFailure)

        StubURLProtocol.routes["POST /live"] = .init()
        await vm.apply(.outputPhase(index: 0, -40))

        XCTAssertNil(vm.liveEditFailure, "the device is answering again; stop shouting")
    }

    /// An edit aimed at an output this device does not have must not crash or invent
    /// one. The Touch has ONE output; the app's `maxOutputCount` is 4.
    func test_an_edit_to_an_output_that_does_not_exist_is_ignored_locally() async {
        let vm = await loadedVM()
        StubURLProtocol.routes["POST /live"] = .init()

        await vm.apply(.outputPhase(index: 3, -40))

        XCTAssertEqual(vm.config?.clock.count, 1, "never grow the array to fit an edit")
    }
}
