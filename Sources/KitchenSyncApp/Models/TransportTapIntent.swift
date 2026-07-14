import Foundation

/// Pure mapping from an output's current `TransportLaunchState` to what a tap
/// on its transport button should request. `/transport` only takes a `play`
/// bool — Start always arms (quantized to the next bar), Stop is immediate —
/// so from `.stopped` a tap means "start"; from `.armed` (cancel the pending
/// start) or `.running` (stop now), a tap means "stop". Kept separate from any
/// view so it's testable without SwiftUI/Network.framework in the loop.
enum TransportTapIntent {
    static func play(for state: TransportLaunchState) -> Bool {
        state == .stopped
    }
}
