import Foundation

/// Whether the device's clock task is faulting **right now**.
///
/// The tick-health counters are LIFETIME totals, not windowed — the firmware is explicit about it
/// (`ks_tick_health.h`: *"Lifetime counters, not windowed — a worst-case that scrolled past is not
/// a measurement."*). So a non-zero `droppedTicks` says only that the device dropped a tick at
/// SOME point, which for a real unit is usually boot. Warning on `> 0` lights an amber dot forever
/// on a perfectly healthy box, and a warning that is always on is one nobody reads.
///
/// What matters is the RATE. The app polls continuously, so it can simply look at the delta.
enum ClockFault: Equatable {
    case none
    /// The counters MOVED between polls. The clock task is dropping ticks now — this is the class
    /// of fault ESP-027 was about, and it is worth an alarm.
    case droppingNow

    /// `previous == nil` — the first sample of a session. There is no rate yet, so there is nothing
    /// to say. A device that booted with 47 drops must not alarm the instant you open its screen;
    /// that is the exact bug this replaces.
    ///
    /// A counter going DOWN means the device REBOOTED (lifetime counters zero on restart) — and
    /// this app reboots devices deliberately, via WRITE & REBOOT and OTA. A reset is not a fault,
    /// and must not be read as one or as a huge negative rate.
    static func between(previous: TickHealth?, current: TickHealth) -> ClockFault {
        guard let previous else { return .none }

        if current.droppedTicks < previous.droppedTicks || current.overruns < previous.overruns {
            return .none    // rebooted
        }

        let dropped = current.droppedTicks > previous.droppedTicks
        let overran = current.overruns > previous.overruns
        return dropped || overran ? .droppingNow : .none
    }
}
