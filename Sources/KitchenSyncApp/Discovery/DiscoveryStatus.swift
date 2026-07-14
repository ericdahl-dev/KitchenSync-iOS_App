import Foundation
import Network

/// Why the device list is empty — or why it isn't.
///
/// This type exists because "empty" used to be the app's only answer, and it is the least
/// useful one it could give. A KitchenSync that is powered, on the network, and audibly
/// following the Link session looked EXACTLY the same in this app as no device at all.
///
/// The cause was iOS's Local Network permission. Denied, iOS does not fail the Bonjour
/// browse — it returns nothing, forever, with no error surfaced to the app. So the user
/// goes and debugs their WiFi, their router, their firmware: everything except the one
/// toggle in Settings that actually turns it back on.
///
/// iOS *does* say so, via `kDNSServiceErr_PolicyDenied`. `KitchenSyncDiscovery` simply
/// never set a `stateUpdateHandler` and never listened.
///
/// Pure, and mapped from `NWBrowser.State`, so it can be tested without a browser.
enum DiscoveryStatus: Equatable {
    /// The browser is coming up. Not yet news.
    case starting
    /// Browsing normally. An empty list here really does mean "nothing on the network".
    case browsing
    /// Waiting on something transient — the WiFi is down, the interface is coming back.
    /// It recovers on its own, so do NOT send the user off to change a setting.
    case waiting
    /// **iOS is refusing us the local network.** Nothing else will fix this and no amount
    /// of waiting will change it. The only way out is the user's Settings app.
    case permissionDenied
    /// The browser died. `NWBrowser` does not come back from `.failed` on its own —
    /// somebody has to restart it.
    case failed
    /// Cancelled, because we asked.
    case stopped

    /// `kDNSServiceErr_PolicyDenied`. The one signal that means "the user has to act".
    private static let policyDenied = DNSServiceErrorType(-65570)

    init(browserState: NWBrowser.State) {
        switch browserState {
        case .setup:
            self = .starting
        case .ready:
            self = .browsing
        case .cancelled:
            self = .stopped
        case .waiting(let error):
            // A permission denial ARRIVES AS A WAIT, which is precisely the trap: it looks
            // like something that will resolve itself, and it never does. Only the DNS
            // policy code tells the two apart.
            self = Self.isPolicyDenied(error) ? .permissionDenied : .waiting
        case .failed(let error):
            self = Self.isPolicyDenied(error) ? .permissionDenied : .failed
        @unknown default:
            self = .waiting
        }
    }

    private static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == policyDenied }
        return false
    }

    /// True only when the USER can fix it. Everything else is ours or the network's, and
    /// putting a "change your privacy settings" banner on those would be the same crime in
    /// the other direction — a signal that sends someone to fix the wrong thing.
    var needsUserAction: Bool { self == .permissionDenied }
}
