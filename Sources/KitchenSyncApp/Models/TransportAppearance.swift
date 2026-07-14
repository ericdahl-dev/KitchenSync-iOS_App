import Foundation

/// Which of the three instrument faces a transport control wears. Deliberately
/// NOT a SwiftUI `Color` — the mapping from state to face is a decision worth
/// testing; turning a face into a gradient is not.
enum TransportFace: Equatable {
    case ember   // stopped: loaded, not firing
    case amber   // armed: waiting for the bar line
    case lime    // running
}

/// Pure mapping from an output's `TransportLaunchState` to how its transport
/// button presents. See `TransportTapIntent` for the other half — what a tap
/// on it should REQUEST.
struct TransportAppearance: Equatable {
    /// The firmware's own words for these states (`ks_web.cpp`'s `.tgl`), so
    /// the app and the device's web UI describe the same state identically.
    var label: String
    var face: TransportFace
    var blinks: Bool
    var acceptsTap: Bool

    /// `linkOwned` — Link owns this output's Start/Stop (`follow_link`), so a tap
    /// here must not be forwarded. `acceptsTap: false` means "reject and SAY so",
    /// not "disabled": the view keeps hit-testing on and pulses amber. Per the
    /// firmware's own web UI, *"a key aimed at a Link-owned output must not
    /// silently do nothing"*. Rejection never alters the reported state — a
    /// Link-owned running output still reads PLAYING; you just can't stop it here.
    static func appearance(for state: TransportLaunchState, linkOwned: Bool) -> TransportAppearance {
        let label: String
        let face: TransportFace
        let blinks: Bool

        switch state {
        case .stopped:
            (label, face, blinks) = ("STOPPED", .ember, false)
        case .armed:
            (label, face, blinks) = ("ARMING", .amber, true)
        case .running:
            (label, face, blinks) = ("PLAYING", .lime, false)
        }

        return TransportAppearance(label: label, face: face, blinks: blinks, acceptsTap: !linkOwned)
    }
}
