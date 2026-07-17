import XCTest
@testable import KitchenSyncApp

/// T-021: the failure classifier, tested directly at its interface — feed it errors, assert the
/// fault. No view model, no `StubURLProtocol`; the decision is a pure function.
final class DeviceFaultTests: XCTestCase {

    // A DecodingError means the device ANSWERED but the body was unreadable — undecodable,
    // NOT unreachable. Collapsing those two is the exact bug this classifier exists to prevent.
    func test_decoding_error_is_undecodable() {
        let err = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        XCTAssertEqual(DeviceFault.classify(err), .undecodable)
    }

    // HTTP 404 — the route is absent on older firmware. The confidently-attributable case,
    // kept apart from unreachable so a stale-firmware user isn't told to check their network.
    func test_http_404_is_not_found() {
        XCTAssertEqual(DeviceFault.classify(KitchenSyncClientError.httpStatus(404)), .notFound)
    }

    // Any other error status: the device answered and refused — rejected, carrying the code.
    func test_other_http_status_is_rejected_with_code() {
        XCTAssertEqual(DeviceFault.classify(KitchenSyncClientError.httpStatus(500)), .rejected(500))
    }

    // A malformed/absent HTTP response is a transport-level failure, not an answer.
    func test_invalid_response_is_unreachable() {
        XCTAssertEqual(DeviceFault.classify(KitchenSyncClientError.invalidResponse), .unreachable)
    }

    // Anything unrecognised (URLError and friends) means we never got a usable answer.
    func test_unknown_error_is_unreachable() {
        XCTAssertEqual(DeviceFault.classify(URLError(.notConnectedToInternet)), .unreachable)
    }
}
