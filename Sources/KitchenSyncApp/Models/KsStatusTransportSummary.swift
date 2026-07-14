import Foundation

extension KsStatus {
    /// One word for the whole device, for the fleet list.
    enum TransportSummary: Equatable {
        case stopped
        case arming
        case playing
    }

    var transportSummary: TransportSummary {
        // When Link drives transport, the session's `playing` flag is the truth for
        // the device as a whole and OUTRANKS the per-output launch array — an entry
        // in there is either stale or belongs to an output not following Link, and
        // reporting "playing" off it would contradict the session.
        if linkOwnsTransport { return playing ? .playing : .stopped }

        // Running wins over arming: a device with one output already playing and
        // another still waiting for the bar line IS playing.
        if launch.contains(.running) { return .playing }
        if launch.contains(.armed)   { return .arming }
        return .stopped
    }
}
