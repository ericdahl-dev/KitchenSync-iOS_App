import Foundation

/// T-026: first-run setup. When a device has never joined the user's network it comes up on its
/// own SoftAP (`SetupNetwork`); the app reaches it there, confirms it's ours, and hands it the
/// user's WiFi credentials over a partial `POST /save`. The device then reboots to join and the
/// device list takes over the reconnect + rediscovery.
///
/// Transport-agnostic on purpose (T-027): the *decision* logic — confirm, then provision — is
/// the same whether the credential transport is HTTP-over-SoftAP (today) or BLE (later); only
/// `provision` swaps.
@MainActor
final class SetupViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case searching
        case foundDevice          // a device answered on the setup AP — safe to offer setup
        case noDevice             // nothing ours at the setup address
        case provisioning
        case provisioned          // creds sent; the device is rebooting to join
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private var client: KitchenSyncClient {
        KitchenSyncClient(host: SetupNetwork.host, session: session)
    }

    /// Confirm we're actually on one of our devices' setup APs by reaching its config server —
    /// so the setup screen only appears for a real device, not an empty or foreign AP.
    func search() async {
        phase = .searching
        do {
            _ = try await client.fetchConfig()
            phase = .foundDevice
        } catch {
            phase = .noDevice
        }
    }

    /// Send the user's network to the device (WiFi fields only — never clobbers other settings).
    /// A blank SSID isn't an attempt; a failure surfaces so the user knows it didn't take.
    func provision(ssid: String, password: String) async {
        let ssid = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else { return }
        phase = .provisioning
        do {
            try await client.provisionWifi(ssid: ssid, password: password)
            phase = .provisioned
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
