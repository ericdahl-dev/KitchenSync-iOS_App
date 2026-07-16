import Foundation

enum KitchenSyncClientError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The device sent an unreadable response."
        case .httpStatus(let code): return "The device returned HTTP \(code)."
        }
    }
}

/// Thin HTTP client for one KitchenSync unit's control surface
/// (`KitchenSync/main/ks_web.cpp` in `link-devices`). One instance per device;
/// `host` is typically `<mdns-name>.local`. Every method maps 1:1 to a route —
/// see each firmware handler's own doc comment for the full protocol contract,
/// this type is deliberately a thin transport, not a place to add business
/// logic.
struct KitchenSyncClient {
    let host: String
    let port: Int
    private let session: URLSession

    init(host: String, port: Int = 80, session: URLSession = .shared) {
        self.host = host
        self.port = port
        self.session = session
    }

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = port
        c.path = path
        if !query.isEmpty { c.queryItems = query }
        guard let url = c.url else {
            preconditionFailure("KitchenSyncClient built an invalid URL from host \(host)")
        }
        return url
    }

    /// GET /status — telemetry (bpm, peers, playing, launch state, tick/phase
    /// health). Poll this, don't cache it; nothing here reflects settings.
    func fetchStatus() async throws -> KsStatus {
        let (data, response) = try await session.data(from: url("/status"))
        try Self.checkOK(response)
        return try JSONDecoder().decode(KsStatus.self, from: data)
    }

    /// GET /config.json (P4-041) — the device's actual current settings.
    func fetchConfig() async throws -> KsConfig {
        let (data, response) = try await session.data(from: url("/config.json"))
        try Self.checkOK(response)
        return try JSONDecoder().decode(KsConfig.self, from: data)
    }

    /// POST /live — a PARTIAL patch (`ks_form_apply` on the firmware). Only the
    /// fields present change; everything else keeps its current value, no
    /// reboot. Posting a field outside `KsLiveEdit`'s closed set (WiFi creds,
    /// `metronome`/`follow_beat` enable) is a silent no-op on the device —
    /// `KsLiveEdit` exists so this client can't do that by accident.
    func postLive(_ edits: [KsLiveEdit]) async throws {
        var fields: [String: String] = [:]
        for edit in edits {
            let (key, value) = edit.formField
            fields[key] = value
        }
        try await postForm("/live", fields: fields)
    }

    func postLive(_ edit: KsLiveEdit) async throws {
        try await postLive([edit])
    }

    /// POST /save — the FULL form (`ks_form_resolve` on the firmware),
    /// persists to NVS and reboots the device. Required for WiFi credentials
    /// and for turning on a metronome that was off.
    func postSave(_ config: KsConfig, wifiEdits: [WifiCredentialEdit]) async throws {
        try await postForm("/save", fields: config.saveFormFields(wifiEdits: wifiEdits))
    }

    /// T-026: first-run WiFi provisioning. POSTs ONLY the credentials to `/save` — a partial
    /// form (no `full_form`), so the firmware leaves every other setting alone and this can
    /// never clobber a device's config while merely joining it to a network. The device stores
    /// the credentials and reboots to join. Point the client at `SetupNetwork.host` — the
    /// device's own SoftAP — for this, since it isn't on the LAN yet.
    func provisionWifi(ssid: String, password: String) async throws {
        try await postForm("/save", fields: ["wifi_ssid": ssid, "wifi_pass": password])
    }

    /// POST /transport?out=N|all&play=1|0 — quantized Start/Stop (ESP-011).
    /// Takes effect on the next bar line; poll `/status.launch[N]` to watch it
    /// arm, then run.
    func postTransport(output: Int?, play: Bool) async throws {
        let outValue = output.map(String.init) ?? "all"
        var request = URLRequest(url: url("/transport", query: [
            URLQueryItem(name: "out", value: outValue),
            URLQueryItem(name: "play", value: play ? "1" : "0"),
        ]))
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try Self.checkOK(response)
    }

    /// POST /update — raw `.bin` body (no multipart), streamed into the
    /// inactive OTA slot (P4-017, dual-slot). The device reboots into it on
    /// success; do not cross-flash a binary built for a different chip target.
    func uploadFirmware(_ binary: Data) async throws {
        var request = URLRequest(url: url("/update"))
        request.httpMethod = "POST"
        request.httpBody = binary
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try Self.checkOK(response)
    }

    private func postForm(_ path: String, fields: [String: String]) async throws {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormURLEncoding.encode(fields)
        let (_, response) = try await session.data(for: request)
        try Self.checkOK(response)
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw KitchenSyncClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw KitchenSyncClientError.httpStatus(http.statusCode) }
    }
}
