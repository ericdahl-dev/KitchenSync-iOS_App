import Foundation

/// Mirrors `TransportLaunchState` (`link-devices/X32Link/transport_launch.h`) as
/// reported per output in `/status`'s `launch[4]` array. Quantized: Play arms,
/// waits for the next bar line, then runs — Stop is immediate. That asymmetry is
/// deliberate (it's Ableton's own launch behaviour), so drive UI straight from
/// this value rather than re-deriving an "armed" state on the client — the
/// device already computes and reports it every poll.
enum TransportLaunchState: Int, Decodable {
    case stopped = 0
    case armed = 1
    case running = 2
}
