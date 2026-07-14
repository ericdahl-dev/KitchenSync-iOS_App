import XCTest
@testable import KitchenSyncApp

/// TDD: written before the app can tell "I can't understand this device" apart from
/// "this device is gone".
///
/// **Found on real hardware, 2026-07-14.** With discovery fixed (T-014), the app finally sees a
/// real KitchenSync Touch — and then labels it UNREACHABLE, while `curl` gets HTTP 200 from that
/// exact host. The device is answering perfectly; the app just can't decode what it says.
///
/// `refreshStatus()` collapses a DECODE failure and a TRANSPORT failure into the same `nil`, so
/// three polls later T-010's reachability counter declares a live device dead. Telling the user
/// their device is unreachable sends them to debug a network that is working fine.
@MainActor
final class UnsupportedDeviceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    /// The REAL Touch's `/status`, captured verbatim from `kstouch-dfd0` on 2026-07-14 (current
    /// `master` firmware). It is missing 11 keys `KsStatus` requires — `min` first, then `usb`,
    /// `tx`, `fw`, `follow_*`, `launch`, `playing`, `link_owns`.
    ///
    /// This fixture goes GREEN the day `link-devices` ESP-029 ships and the Touch shares
    /// `ks_status.c`. Keep it.
    static let realTouchStatusJSON = """
    {"bpm":0.0,"sync":-1,"peers":0,"clock":1,"transport":0,"cue":0,"tfail":0,"tzero":0,
     "ccancel":0,"drop":0,"burst":0,"gap":1486,"work":93,"over":0,"core":1,
     "wbeats":49,"wclock":1,"wtport":43,"beats":0.00,"locked":0,"bsactive":0,
     "btn":-1,"btnlows":0,"btnpress":0,"clk":"silent","pulses":0}
    """.data(using: .utf8)!

    private func makeVM() -> DeviceDetailViewModel {
        DeviceDetailViewModel(
            client: KitchenSyncClient(host: "kstouch-dfd0.local", session: StubURLProtocol.session())
        )
    }

    /// A device that ANSWERS but speaks a dialect we don't understand is `.unsupported`.
    /// It is emphatically not "gone".
    func test_a_device_that_answers_but_cannot_be_decoded_is_unsupported_not_offline() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.realTouchStatusJSON)
        let vm = makeVM()

        await vm.refreshStatus()

        XCTAssertEqual(vm.statusAvailability, .unsupported,
                       "the device answered HTTP 200 — it is not unreachable, we just can't read it")
    }

    // MARK: The fleet list — where UNREACHABLE is actually displayed

    private func makeListVM() -> DeviceListViewModel {
        let defaults = UserDefaults(suiteName: "UnsupportedDeviceTests.\(UUID().uuidString)")!
        return DeviceListViewModel(store: ManualDeviceStore(defaults: defaults),
                                   session: StubURLProtocol.session())
    }

    /// **The exact bug seen on the bench.** The Touch answers every poll with HTTP 200, so it is
    /// plainly not gone — but the app decoded nothing, counted three misses, and rendered
    /// UNREACHABLE. A device that keeps answering must never be declared dead.
    func test_a_device_that_keeps_answering_is_never_declared_unreachable() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.realTouchStatusJSON)
        let vm = makeListVM()
        vm.addManualDevice(host: "kstouch-dfd0.local")

        for _ in 0..<5 { await vm.refreshNow() }   // well past T-010's 3-miss threshold

        XCTAssertNotEqual(vm.reachability(of: "kstouch-dfd0.local"), .unreachable,
                          "it answered HTTP 200 five times — calling it unreachable is a lie")
        XCTAssertEqual(vm.reachability(of: "kstouch-dfd0.local"), .unsupported)
    }

    /// And the T-010 behaviour still holds: a device that genuinely stops answering IS unreachable.
    func test_a_device_that_stops_answering_is_still_unreachable() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.realTouchStatusJSON)
        let vm = makeListVM()
        vm.addManualDevice(host: "kstouch-dfd0.local")
        await vm.refreshNow()

        StubURLProtocol.routes = [:]   // device drops off the network
        for _ in 0..<3 { await vm.refreshNow() }

        XCTAssertEqual(vm.reachability(of: "kstouch-dfd0.local"), .unreachable)
    }
}
