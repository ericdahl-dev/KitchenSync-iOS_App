import Foundation

/// T-021: the ONE place that answers "what kind of failure was that?" for a device request.
///
/// The transport layer throws `KitchenSyncClientError` / `DecodingError`; those types must not
/// leak into every view model's `catch`, and the three-way "answered-and-read / answered-but-
/// undecodable / didn't-answer" decision must not be re-derived per call site (that drift is the
/// recurring bug — T-009/T-010/T-016/T-018). Each view model maps this one fault onto its own
/// presentation enum; the classification lives here.
enum DeviceFault: Equatable {
    /// The device ANSWERED, but the body was unreadable (`DecodingError`). It is there — its
    /// firmware just speaks a different shape. The way out is a firmware update, not a network fix.
    case undecodable
    /// HTTP 404 — the route is absent on this (older) firmware. The confidently-attributable case.
    case notFound
    /// The device answered with another error status — it is right there and talking; this is
    /// about the request/value, not the connection.
    case rejected(Int)
    /// No answer, or a transport-level failure. "Can't reach it", not "it said no".
    case unreachable
}

extension DeviceFault {
    static func classify(_ error: Error) -> DeviceFault {
        if error is DecodingError { return .undecodable }
        if let e = error as? KitchenSyncClientError {
            switch e {
            case .httpStatus(404):      return .notFound
            case .httpStatus(let code): return .rejected(code)
            case .invalidResponse:      return .unreachable
            }
        }
        return .unreachable
    }
}
