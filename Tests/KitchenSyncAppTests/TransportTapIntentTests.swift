import XCTest
@testable import KitchenSyncApp

/// TDD: written before `TransportTapIntent` exists. `/transport` on the
/// firmware only takes a `play` bool, quantized to the next bar
/// (`transport_launch.h`) — Stop is the only immediate action; Start always
/// arms. The tap gesture has exactly one decision to make: from stopped, tap
/// means "start"; from armed OR running, tap means "stop" (a second tap while
/// armed cancels the pending start, matching the physical device's own button
/// semantics — `transport_led.c`'s dark/blinking/solid states are exactly
/// these three).
final class TransportTapIntentTests: XCTestCase {
    func test_tap_while_stopped_requests_play() {
        XCTAssertEqual(TransportTapIntent.play(for: .stopped), true)
    }

    func test_tap_while_armed_requests_stop() {
        XCTAssertEqual(TransportTapIntent.play(for: .armed), false)
    }

    func test_tap_while_running_requests_stop() {
        XCTAssertEqual(TransportTapIntent.play(for: .running), false)
    }
}
