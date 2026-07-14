import XCTest
@testable import KitchenSyncApp

/// `DeviceListViewModel` had no tests. T-005 builds the view on top of it, and it
/// carries a real footgun that the view must not trip: `removeManualDevices(at:)`
/// takes `IndexSet` offsets into the FILTERED manual-only list, not into `devices`.
/// Bind a `ForEach` over all devices to it and you delete the wrong row.
///
/// These tests pin the contract so the view can be built against it safely.
@MainActor
final class DeviceListViewModelTests: XCTestCase {
    private func makeVM() -> DeviceListViewModel {
        // A private suite, so the test never touches the user's real defaults.
        let defaults = UserDefaults(suiteName: "DeviceListViewModelTests.\(UUID().uuidString)")!
        return DeviceListViewModel(store: ManualDeviceStore(defaults: defaults))
    }

    func test_manual_device_is_added_and_marked_manual() {
        let vm = makeVM()

        vm.addManualDevice(host: "192.168.1.42")

        XCTAssertEqual(vm.devices.map(\.host), ["192.168.1.42"])
        XCTAssertTrue(vm.devices[0].addedManually)
    }

    func test_manual_host_is_trimmed_and_blank_is_ignored() {
        let vm = makeVM()

        vm.addManualDevice(host: "  kitchensync-a4f2.local  ")
        vm.addManualDevice(host: "   ")

        XCTAssertEqual(vm.devices.map(\.host), ["kitchensync-a4f2.local"])
    }

    func test_the_same_host_is_not_added_twice() {
        let vm = makeVM()

        vm.addManualDevice(host: "a.local")
        vm.addManualDevice(host: "a.local")

        XCTAssertEqual(vm.devices.count, 1)
    }

    func test_discovered_devices_are_merged_and_not_marked_manual() {
        let vm = makeVM()

        vm.merge(discovered: ["kitchensync-a4f2"])

        XCTAssertEqual(vm.devices.map(\.host), ["kitchensync-a4f2.local"])
        XCTAssertFalse(vm.devices[0].addedManually)
    }

    /// A manually-added host that Bonjour then also discovers must not appear twice.
    func test_discovery_does_not_duplicate_a_manually_added_host() {
        let vm = makeVM()
        vm.addManualDevice(host: "kitchensync-a4f2.local")

        vm.merge(discovered: ["kitchensync-a4f2"])

        XCTAssertEqual(vm.devices.count, 1)
        XCTAssertTrue(vm.devices[0].addedManually)
    }

    /// THE FOOTGUN. Offsets index the manual-only list. With a discovered device
    /// sitting at index 0 of `devices`, offset 0 must still delete the first MANUAL
    /// device — not the discovered one, which isn't deletable at all.
    func test_remove_offsets_index_the_manual_list_not_the_whole_list() {
        let vm = makeVM()
        vm.merge(discovered: ["kitchensync-discovered"])   // devices[0], not manual
        vm.addManualDevice(host: "manual-one.local")       // devices[1], manual[0]
        vm.addManualDevice(host: "manual-two.local")       // devices[2], manual[1]

        vm.removeManualDevices(at: IndexSet(integer: 0))

        XCTAssertEqual(vm.devices.map(\.host),
                       ["kitchensync-discovered.local", "manual-two.local"],
                       "offset 0 must delete the first MANUAL device, not the discovered one")
    }

    // MARK: Reachability (T-010)
    //
    // refreshAll() used to swallow every polling failure with `try?` and keep the last
    // known status, so a device that had dropped off the network looked FINE — showing
    // its last bpm and peer count indefinitely, indistinguishable from a live one.
    //
    // For an app whose whole job is telling you the state of hardware on stage, that is
    // the wrong default.

    private static let statusJSON = """
    {"bpm":128.0,"min":0.0,"peers":4,"usb":true,"tx":1,"fw":"1.2.3",
     "follow_enabled":false,"follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,
     "launch":[0,0,0,0],"playing":false,"link_owns":false}
    """.data(using: .utf8)!

    private func makeStubbedVM() -> DeviceListViewModel {
        let defaults = UserDefaults(suiteName: "DeviceListViewModelTests.\(UUID().uuidString)")!
        return DeviceListViewModel(store: ManualDeviceStore(defaults: defaults),
                                   session: StubURLProtocol.session())
    }

    func test_a_device_that_answers_is_reachable() async {
        StubURLProtocol.reset()
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makeStubbedVM()
        vm.addManualDevice(host: "a.local")

        await vm.refreshNow()

        XCTAssertEqual(vm.reachability(of: "a.local"), .reachable)
        XCTAssertEqual(vm.statuses["a.local"]?.bpm, 128.0)
    }

    /// One dropped request on a busy LAN is NOISE, not a disconnection. At a 2s poll,
    /// flapping a red badge on every missed packet would be worse than the old
    /// behaviour. A single miss keeps the device reachable and keeps its last status.
    func test_a_single_missed_poll_does_not_declare_the_device_gone() async {
        StubURLProtocol.reset()
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makeStubbedVM()
        vm.addManualDevice(host: "a.local")
        await vm.refreshNow()

        StubURLProtocol.routes = [:]   // device stops answering
        await vm.refreshNow()

        XCTAssertEqual(vm.reachability(of: "a.local"), .reachable)
        XCTAssertNotNil(vm.statuses["a.local"], "the last known status is still the best we have")
    }

    func test_three_consecutive_misses_declares_the_device_unreachable() async {
        StubURLProtocol.reset()
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makeStubbedVM()
        vm.addManualDevice(host: "a.local")
        await vm.refreshNow()

        StubURLProtocol.routes = [:]
        await vm.refreshNow()
        await vm.refreshNow()
        await vm.refreshNow()

        XCTAssertEqual(vm.reachability(of: "a.local"), .unreachable)
    }

    /// The stale status must NOT keep being served as fact once the device is gone.
    func test_an_unreachable_devices_status_is_dropped() async {
        StubURLProtocol.reset()
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makeStubbedVM()
        vm.addManualDevice(host: "a.local")
        await vm.refreshNow()

        StubURLProtocol.routes = [:]
        for _ in 0..<3 { await vm.refreshNow() }

        XCTAssertNil(vm.statuses["a.local"],
                     "a device that is gone must not still be reporting 128 bpm")
    }

    /// Recovery is automatic — no user action, no manual clear.
    func test_a_device_that_comes_back_is_reachable_again() async {
        StubURLProtocol.reset()
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makeStubbedVM()
        vm.addManualDevice(host: "a.local")
        await vm.refreshNow()
        StubURLProtocol.routes = [:]
        for _ in 0..<3 { await vm.refreshNow() }
        XCTAssertEqual(vm.reachability(of: "a.local"), .unreachable)

        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        await vm.refreshNow()

        XCTAssertEqual(vm.reachability(of: "a.local"), .reachable)
        XCTAssertEqual(vm.statuses["a.local"]?.bpm, 128.0)
    }

    /// A single success resets the miss counter — three misses spread across a flaky
    /// hour with successes between them is a working device, not a dead one.
    func test_a_success_resets_the_miss_counter() async {
        StubURLProtocol.reset()
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makeStubbedVM()
        vm.addManualDevice(host: "a.local")
        await vm.refreshNow()

        for _ in 0..<2 {
            StubURLProtocol.routes = [:]
            await vm.refreshNow()                                   // miss
            StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
            await vm.refreshNow()                                   // recover
        }
        StubURLProtocol.routes = [:]
        await vm.refreshNow()                                       // one more miss

        XCTAssertEqual(vm.reachability(of: "a.local"), .reachable)
    }

    func test_removing_a_manual_device_persists() {
        let defaults = UserDefaults(suiteName: "DeviceListViewModelTests.\(UUID().uuidString)")!
        let store = ManualDeviceStore(defaults: defaults)
        let vm = DeviceListViewModel(store: store)
        vm.addManualDevice(host: "a.local")
        vm.addManualDevice(host: "b.local")

        vm.removeManualDevices(at: IndexSet(integer: 0))

        XCTAssertEqual(store.load().map(\.host), ["b.local"])
    }
}
