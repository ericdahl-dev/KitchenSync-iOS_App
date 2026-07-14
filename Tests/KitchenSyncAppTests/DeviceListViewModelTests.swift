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
