import XCTest
@testable import KitchenSyncApp

/// TDD: written before `DeviceDetailViewModel` exists.
///
/// Tests run the REAL `KitchenSyncClient` against a stubbed `URLProtocol`, so the
/// URL building, form encoding, and HTTP status checking are all exercised. The
/// only thing faked is the wire.
@MainActor
final class DeviceDetailViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeVM() -> DeviceDetailViewModel {
        DeviceDetailViewModel(
            client: KitchenSyncClient(host: "kitchensync-a4f2.local",
                                      session: StubURLProtocol.session())
        )
    }

    /// The firmware's verbatim wire keys (`ks_status.c`) — including the oddity
    /// that MIDI-clock-in BPM rides under `"min"`. Not "prettified".
    private static let statusJSON = """
    {"bpm":128.0,"min":0.0,"peers":4,"usb":true,"tx":12345,"fw":"1.2.3",
     "follow_enabled":false,"follow_bpm":0.0,"follow_confidence":0.0,"follow_valid":false,
     "launch":[0,1,2,0],"playing":true,"link_owns":false}
    """.data(using: .utf8)!

    func test_refresh_publishes_the_devices_status() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makeVM()

        await vm.refreshStatus()

        XCTAssertEqual(vm.status?.bpm, 128.0)
        XCTAssertEqual(vm.status?.peers, 4)
        XCTAssertEqual(vm.status?.launch[1], .armed)
    }

    /// A live edit must POST /live as a PARTIAL patch — exactly the one field
    /// that changed, nothing else. Sending a full form here would be wrong: the
    /// firmware's `ks_form_apply` leaves absent fields alone, and a full form is
    /// what `/save` is for (which reboots).
    func test_live_edit_posts_only_the_changed_field_to_live() async {
        StubURLProtocol.routes["POST /live"] = .init()
        let vm = makeVM()

        await vm.apply(.ledBrightness(60))

        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        let req = StubURLProtocol.requests[0]
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.path, "/live")
        XCTAssertEqual(String(data: req.body, encoding: .utf8), "led_bright=60")
    }

    func test_transport_posts_the_output_index_and_play_flag() async {
        StubURLProtocol.routes["POST /transport"] = .init()
        let vm = makeVM()

        await vm.transport(output: 2, play: true)

        let req = StubURLProtocol.requests[0]
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.path, "/transport")
        XCTAssertEqual(req.url.query, "out=2&play=1")
    }

    /// `out=all` is the firmware's own spelling for the master transport — a nil
    /// output must not become "out=" or be omitted.
    func test_master_transport_posts_out_all() async {
        StubURLProtocol.routes["POST /transport"] = .init()
        let vm = makeVM()

        await vm.transport(output: nil, play: false)

        XCTAssertEqual(StubURLProtocol.requests[0].url.query, "out=all&play=0")
    }

    private static let configJSON = """
    {"clock_out":true,"metronome":false,"metro_accent":true,"metro_vol":80,\
    "metro_voice":0,"led":false,"led_bright":60,"led_mode":0,"led_fade":55,\
    "led_beat":"#00B400","led_accent":"#DC6E00","follow_beat":false,\
    "wifi":[{"ssid":"TestNet","pass_set":true},{"ssid":"","pass_set":false},{"ssid":"","pass_set":false}],\
    "clock":[{"en":true,"cable":0,"ppqn":24,"phase":0,"swing":0,"follow":true},\
    {"en":false,"cable":1,"ppqn":24,"phase":0,"swing":0,"follow":true},\
    {"en":false,"cable":2,"ppqn":24,"phase":0,"swing":0,"follow":true},\
    {"en":false,"cable":3,"ppqn":24,"phase":0,"swing":0,"follow":true}]}
    """.data(using: .utf8)!

    func test_load_config_publishes_the_devices_settings() async {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        let vm = makeVM()

        await vm.loadConfig()

        XCTAssertEqual(vm.config?.ledBrightness, 60)
        XCTAssertEqual(vm.config?.wifi.first?.ssid, "TestNet")
        // The password is never on the wire, so it can never be in the model.
        XCTAssertEqual(vm.config?.wifi.first?.passwordIsSet, true)
    }

    /// `/save` is the FULL form and it REBOOTS the device. It must carry every
    /// field — including the reboot-only ones that `/live` has no case for, which
    /// is the entire reason this path exists.
    func test_save_posts_the_full_form_including_reboot_only_fields() async throws {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        StubURLProtocol.routes["POST /save"] = .init()
        let vm = makeVM()
        await vm.loadConfig()
        let config = try XCTUnwrap(vm.config)

        await vm.save(config, wifiEdits: [WifiCredentialEdit(id: 0, ssid: "Backline", password: "hunter2")])

        let req = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.path, "/save")

        let body = try XCTUnwrap(String(data: req.body, encoding: .utf8))
        // Reboot-only fields — the ones with no KsLiveEdit case. If these ever
        // stop riding on /save, they become unreachable from the app entirely.
        XCTAssertTrue(body.contains("metronome=0"), body)
        XCTAssertTrue(body.contains("follow_beat=0"), body)
        XCTAssertTrue(body.contains("wifi_ssid=Backline"), body)
        XCTAssertTrue(body.contains("wifi_pass=hunter2"), body)
        // And a live-editable one, to prove it's the full form and not a patch.
        XCTAssertTrue(body.contains("led_bright=60"), body)
    }

    // MARK: /config.json is newer than the fleet (T-009)
    //
    // GET /config.json landed 2026-07-14. A unit on older firmware 404s on it while
    // every other route — status, transport, live edits, OTA — still works fine.
    //
    // A 404 and a dead network are DIFFERENT failures and must not be conflated:
    // telling a user their firmware is old when really their WiFi dropped sends them
    // off to reflash a device that was fine.

    func test_config_404_means_the_firmware_is_too_old_not_that_the_device_is_gone() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        // No /config.json route registered -> the stub answers 404.
        let vm = makeVM()

        await vm.refreshStatus()
        await vm.loadConfig()

        XCTAssertEqual(vm.configAvailability, .unsupportedByFirmware)
        XCTAssertNil(vm.config)
        // And critically: everything else still works.
        XCTAssertEqual(vm.status?.bpm, 128.0)
    }

    func test_config_transport_failure_is_not_blamed_on_firmware() async {
        // Route the stub to a hard transport error rather than any HTTP response.
        StubURLProtocol.routes["GET /config.json"] = .init(status: 500, body: Data())
        let vm = makeVM()

        await vm.loadConfig()

        XCTAssertNotEqual(vm.configAvailability, .unsupportedByFirmware,
                          "a 500 is not an old-firmware 404 — don't tell the user to reflash")
        XCTAssertEqual(vm.configAvailability, .failed)
    }

    func test_a_successful_load_reports_available() async {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        let vm = makeVM()

        await vm.loadConfig()

        XCTAssertEqual(vm.configAvailability, .available)
    }

    func test_availability_starts_unknown_before_any_attempt() {
        XCTAssertEqual(makeVM().configAvailability, .unknown)
    }

    /// `/save` reboots the device. It will stop answering for several seconds, and
    /// the UI must say "rebooting" rather than "unreachable" — an expected
    /// disappearance is not an error, and a user who just pressed WRITE & REBOOT
    /// should not be told their device fell off the network.
    func test_saving_marks_the_device_as_rebooting() async throws {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        StubURLProtocol.routes["POST /save"] = .init()
        let vm = makeVM()
        await vm.loadConfig()
        let config = try XCTUnwrap(vm.config)
        XCTAssertFalse(vm.isRebooting)

        await vm.save(config, wifiEdits: [])

        XCTAssertTrue(vm.isRebooting)
    }

    /// And it clears itself the instant the device answers again — no timer, no
    /// guess. The device coming back IS the signal.
    func test_rebooting_clears_when_the_device_answers_again() async throws {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        StubURLProtocol.routes["POST /save"] = .init()
        let vm = makeVM()
        await vm.loadConfig()
        let config = try XCTUnwrap(vm.config)
        await vm.save(config, wifiEdits: [])
        XCTAssertTrue(vm.isRebooting)

        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        await vm.refreshStatus()

        XCTAssertFalse(vm.isRebooting)
    }

    /// A failed poll while rebooting must NOT clear the flag — that's the device
    /// still being down, which is exactly what we're waiting out.
    func test_a_failed_poll_while_rebooting_keeps_the_rebooting_state() async throws {
        StubURLProtocol.routes["GET /config.json"] = .init(body: Self.configJSON)
        StubURLProtocol.routes["POST /save"] = .init()
        let vm = makeVM()
        await vm.loadConfig()
        let config = try XCTUnwrap(vm.config)
        await vm.save(config, wifiEdits: [])

        // No /status route registered -> the stub 404s -> the fetch throws.
        await vm.refreshStatus()

        XCTAssertTrue(vm.isRebooting)
        XCTAssertNil(vm.status)
    }

    // MARK: The poll loop

    private func makePollingVM() -> DeviceDetailViewModel {
        DeviceDetailViewModel(
            client: KitchenSyncClient(host: "kitchensync-a4f2.local",
                                      session: StubURLProtocol.session()),
            pollInterval: .milliseconds(20)
        )
    }

    private func waitForRequests(atLeast n: Int) async {
        for _ in 0..<100 {
            if StubURLProtocol.requests.count >= n { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func test_start_polls_status_repeatedly() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makePollingVM()

        vm.start()
        await waitForRequests(atLeast: 3)
        vm.stop()

        XCTAssertGreaterThanOrEqual(StubURLProtocol.requests.count, 3)
        XCTAssertEqual(vm.status?.bpm, 128.0)
    }

    /// The detail screen goes away, the polling must go with it. A view model that
    /// keeps hammering a device after you navigated away is four devices' worth of
    /// traffic on a LAN that also has to carry the audio.
    func test_stop_ends_the_poll_loop() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makePollingVM()

        vm.start()
        await waitForRequests(atLeast: 2)
        vm.stop()

        let settled = StubURLProtocol.requests.count
        try? await Task.sleep(for: .milliseconds(150))   // several poll intervals

        XCTAssertEqual(StubURLProtocol.requests.count, settled,
                       "polling continued after stop()")
    }

    /// SwiftUI's `.task {}` re-invokes on every re-appear. Two poll loops against
    /// one device is a bug that only shows up as doubled traffic.
    func test_start_is_idempotent() async {
        StubURLProtocol.routes["GET /status"] = .init(body: Self.statusJSON)
        let vm = makePollingVM()

        vm.start()
        vm.start()
        vm.start()
        await waitForRequests(atLeast: 2)
        vm.stop()

        let settled = StubURLProtocol.requests.count
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(StubURLProtocol.requests.count, settled,
                       "a second start() spawned an extra poll loop that stop() didn't cancel")
    }
}
