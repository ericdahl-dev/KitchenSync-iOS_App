import XCTest
@testable import KitchenSyncApp

/// TDD: written before `ClockFault` exists.
///
/// **Found on real hardware, 2026-07-14.** The diagnostics dot was `droppedTicks > 0` — but those
/// are LIFETIME counters (`ks_tick_health.h`: *"Lifetime counters, not windowed — a worst-case
/// that scrolled past is not a measurement."*).
///
/// So a real Touch reporting `drop:47`, accumulated once at boot, lit an amber warning **forever**
/// on a perfectly healthy device. Sampled every 4s for 32s, `drop` never moved off 47 and `over`
/// stayed 0. A warning that is always on is a warning nobody reads — and it will be ignored on the
/// one day it means something.
///
/// The distinction that matters is the RATE, and the app polls continuously, so it can see it:
///   - non-zero but STATIC   -> dropped ticks at boot, fine now. Say nothing.
///   - INCREASING            -> the clock task is dropping ticks RIGHT NOW. This is ESP-027.
final class ClockFaultTests: XCTestCase {
    private func tick(dropped: UInt32, overruns: UInt32 = 0) -> TickHealth {
        TickHealth(droppedTicks: dropped, bursts: 0, maxGapMicros: 1487, maxWorkMicros: 229,
                   overruns: overruns, core: 1, beatsWritten: 0, clockPulsesWritten: 0, reprimes: 0)
    }

    /// THE BUG. The real bench device: 47 dropped ticks at boot, static ever since.
    func test_a_static_lifetime_counter_is_not_a_fault() {
        let fault = ClockFault.between(previous: tick(dropped: 47), current: tick(dropped: 47))
        XCTAssertEqual(fault, .none,
                       "47 dropped at boot with none since is a healthy device — do not cry wolf")
    }

    /// The one we actually want to catch: the counter MOVED.
    func test_a_rising_dropped_count_is_a_fault() {
        let fault = ClockFault.between(previous: tick(dropped: 47), current: tick(dropped: 48))
        XCTAssertEqual(fault, .droppingNow)
    }

    func test_a_rising_overrun_count_is_a_fault() {
        let fault = ClockFault.between(previous: tick(dropped: 47, overruns: 0),
                                       current:  tick(dropped: 47, overruns: 1))
        XCTAssertEqual(fault, .droppingNow)
    }

    /// The first sample has nothing to compare against. A device that booted with 47 drops must
    /// not alarm the instant you open its screen — that is the very bug being fixed.
    func test_the_first_sample_cannot_know_a_rate_and_must_not_alarm() {
        let fault = ClockFault.between(previous: nil, current: tick(dropped: 47))
        XCTAssertEqual(fault, .none)
    }

    /// **The reboot trap.** Lifetime counters reset to 0 when the device restarts — and this app
    /// reboots devices deliberately (WRITE & REBOOT, OTA). A counter going DOWN is a reboot, not a
    /// fault, and must not be read as a fault or as a huge negative rate.
    func test_counters_resetting_after_a_reboot_is_not_a_fault() {
        let fault = ClockFault.between(previous: tick(dropped: 47, overruns: 3),
                                       current:  tick(dropped: 0,  overruns: 0))
        XCTAssertEqual(fault, .none, "a reboot zeroes lifetime counters — that is not a clock fault")
    }

    /// And immediately after that reboot, a genuine new drop still faults.
    func test_a_drop_after_a_reboot_still_faults() {
        let fault = ClockFault.between(previous: tick(dropped: 0), current: tick(dropped: 1))
        XCTAssertEqual(fault, .droppingNow)
    }
}
