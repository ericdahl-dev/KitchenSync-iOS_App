import XCTest
@testable import KitchenSyncApp

/// TDD: written before `TransportAppearance` exists.
///
/// The mapping from an output's `TransportLaunchState` to how its transport
/// button LOOKS is real logic, not styling — it decides whether the button
/// blinks (the only feedback that a quantized start armed) and whether a tap
/// is accepted at all. Kept as a pure function over enums, with no SwiftUI
/// types, so it can be asserted on. The view turns a `TransportFace` into
/// colors; that part has nothing to decide.
///
/// Labels are the firmware's own words (`ks_web.cpp`'s `.tgl` states), so the
/// app and the device's web UI say the same thing about the same state.
final class TransportAppearanceTests: XCTestCase {
    func test_stopped_is_ember_and_does_not_blink() {
        let a = TransportAppearance.appearance(for: .stopped, linkOwned: false)

        XCTAssertEqual(a.label, "STOPPED")
        // Ember, not grey: grey is what DISABLED looks like, and a stopped
        // output is the opposite of disabled — it's loaded and ready to fire.
        XCTAssertEqual(a.face, .ember)
        XCTAssertFalse(a.blinks)
        XCTAssertTrue(a.acceptsTap)
    }

    /// The one that matters. Play is quantized — a tap arms the output and the
    /// bar line may be most of a bar away. The blink is the ONLY evidence the
    /// tap registered. The device's own web UI gets this wrong: its `.tgl.arming`
    /// is a static amber with a 150ms colour transition and no motion at all.
    func test_armed_is_amber_and_blinks() {
        let a = TransportAppearance.appearance(for: .armed, linkOwned: false)

        XCTAssertEqual(a.label, "ARMING")
        XCTAssertEqual(a.face, .amber)
        XCTAssertTrue(a.blinks)
        XCTAssertTrue(a.acceptsTap)
    }

    func test_running_is_lime_and_does_not_blink() {
        let a = TransportAppearance.appearance(for: .running, linkOwned: false)

        XCTAssertEqual(a.label, "PLAYING")
        XCTAssertEqual(a.face, .lime)
        // Running is steady. Only the ARMED state blinks — a blinking "playing"
        // would destroy the one signal that means "your tap is still pending".
        XCTAssertFalse(a.blinks)
        XCTAssertTrue(a.acceptsTap)
    }

    /// Link owns transport for this output — a tap must NOT be forwarded.
    ///
    /// `acceptsTap == false` means "reject and say so", NOT "disabled". The
    /// firmware's own web UI is explicit about this (`ks_web.cpp`): *"A key
    /// aimed at a Link-owned output must not silently do nothing"* — it fires
    /// an amber `nak` pulse instead. A button that swallows the tap teaches the
    /// user the app is broken. The view keeps hit-testing on and pulses.
    func test_link_owned_output_rejects_the_tap() {
        for state in [TransportLaunchState.stopped, .armed, .running] {
            let a = TransportAppearance.appearance(for: state, linkOwned: true)
            XCTAssertFalse(a.acceptsTap, "\(state) should reject the tap when Link owns transport")
        }
    }

    /// Rejecting the tap must not lie about the state. A Link-owned output that
    /// is RUNNING still reads PLAYING — you just can't stop it from here.
    func test_link_owned_output_still_reports_its_true_state() {
        let a = TransportAppearance.appearance(for: .running, linkOwned: true)

        XCTAssertEqual(a.label, "PLAYING")
        XCTAssertEqual(a.face, .lime)
    }
}
