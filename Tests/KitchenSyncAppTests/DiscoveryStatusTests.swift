import Network
import XCTest
@testable import KitchenSyncApp

/// TDD, from a bug the user hit on real hardware: *"I don't see the s3touch in the app —
/// even though it's following the Link session."*
///
/// The device was advertising `_http._tcp` correctly the whole time, and the same build
/// found it instantly in the Simulator. What was different on the phone was iOS's **Local
/// Network permission**, which had been reset by reinstalling the app.
///
/// When that permission is denied, iOS does not fail the browse — it just returns NOTHING,
/// forever. `KitchenSyncDiscovery` didn't even set a `stateUpdateHandler`, so a browser
/// that was dead on arrival stayed dead in silence and the list sat empty with no
/// explanation. The user is then sent to debug their network, their WiFi, their firmware —
/// everything except the one switch that actually turns it back on.
///
/// The recurring bug of this codebase, one more time: a failure with no signal (T-009,
/// T-010, T-016, T-018, and `link_owns`). iOS DOES tell us — `kDNSServiceErr_PolicyDenied`.
/// We just never listened.
///
/// The mapping is pure so it can be asserted without standing up an `NWBrowser`.
final class DiscoveryStatusTests: XCTestCase {

    /// THE ONE THAT MATTERS. -65570 is `kDNSServiceErr_PolicyDenied`: iOS is refusing us
    /// the local network, and no amount of waiting will change that.
    func test_a_policy_denied_browser_is_reported_as_permission_denied() {
        let denied = NWError.dns(DNSServiceErrorType(-65570))

        XCTAssertEqual(DiscoveryStatus(browserState: .waiting(denied)), .permissionDenied)
    }

    /// ...and it is NOT confused with a transient wait. A browser waiting because the WiFi
    /// is still coming up will recover on its own; telling the user to go change a Settings
    /// toggle for that is sending them to fix the wrong thing.
    func test_an_ordinary_wait_is_not_reported_as_permission_denied() {
        let transient = NWError.posix(.ENETDOWN)

        XCTAssertEqual(DiscoveryStatus(browserState: .waiting(transient)), .waiting)
    }

    func test_a_ready_browser_is_browsing() {
        XCTAssertEqual(DiscoveryStatus(browserState: .ready), .browsing)
    }

    /// A FAILED browser never comes back by itself — NWBrowser is done. Somebody has to
    /// restart it, and nobody can if nobody is told.
    func test_a_failed_browser_is_reported_as_failed() {
        XCTAssertEqual(DiscoveryStatus(browserState: .failed(.posix(.ENETDOWN))), .failed)
    }

    func test_setup_and_cancelled_are_not_errors() {
        XCTAssertEqual(DiscoveryStatus(browserState: .setup), .starting)
        XCTAssertEqual(DiscoveryStatus(browserState: .cancelled), .stopped)
    }

    /// Only `permissionDenied` is the user's to fix. Everything else is ours or the
    /// network's, and must not put a "go change your privacy settings" banner on screen.
    func test_only_permission_denial_asks_the_user_to_do_something() {
        XCTAssertTrue(DiscoveryStatus.permissionDenied.needsUserAction)
        XCTAssertFalse(DiscoveryStatus.browsing.needsUserAction)
        XCTAssertFalse(DiscoveryStatus.waiting.needsUserAction)
        XCTAssertFalse(DiscoveryStatus.failed.needsUserAction)
        XCTAssertFalse(DiscoveryStatus.starting.needsUserAction)
    }
}
