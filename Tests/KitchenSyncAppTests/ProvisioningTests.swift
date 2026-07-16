import XCTest
@testable import KitchenSyncApp

/// T-026: provisioning a device's WiFi is a `POST /save` with ONLY the credentials — a partial
/// form. The device is being set up for the first time; the app must not send `full_form` or
/// any other field, or it would reset settings it can't even see yet. Tested through the REAL
/// client against `StubURLProtocol`, so the actual URL + form encoding is what's asserted.
final class ProvisioningTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }

    private func client() -> KitchenSyncClient {
        KitchenSyncClient(host: SetupNetwork.host, session: StubURLProtocol.session())
    }

    private func formFields(_ body: Data) -> [String: String] {
        var out: [String: String] = [:]
        for pair in (String(data: body, encoding: .utf8) ?? "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = kv[0].removingPercentEncoding ?? kv[0]
            let raw = kv.count > 1 ? kv[1].replacingOccurrences(of: "+", with: " ") : ""
            out[key] = raw.removingPercentEncoding ?? raw
        }
        return out
    }

    func test_provisioning_posts_only_the_wifi_fields_to_save() async throws {
        StubURLProtocol.routes["POST /save"] = .init()
        try await client().provisionWifi(ssid: "StudioNet", password: "downbeat99")

        let req = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.path, "/save")
        XCTAssertEqual(req.url.host, "192.168.4.1")

        let fields = formFields(req.body)
        XCTAssertEqual(fields["wifi_ssid"], "StudioNet")
        XCTAssertEqual(fields["wifi_pass"], "downbeat99")
        // The whole point: a partial form. Sending full_form (or another field) would reset
        // the device's other settings while merely joining it to WiFi.
        XCTAssertNil(fields["full_form"], "provisioning must never send full_form")
        XCTAssertNil(fields["clock_out"])
    }

    func test_a_save_error_during_provisioning_surfaces() async {
        StubURLProtocol.routes["POST /save"] = .init(status: 500)
        do {
            try await client().provisionWifi(ssid: "X", password: "Y")
            XCTFail("a 500 from /save must not be swallowed")
        } catch {
            // expected — the setup flow needs to know provisioning failed
        }
    }
}
