import Foundation

/// One device's screen. `DeviceListViewModel` owns the fleet; this owns a single
/// unit once you've drilled into it.
@MainActor
final class DeviceDetailViewModel: ObservableObject {
    @Published private(set) var status: KsStatus?
    @Published private(set) var config: KsConfig?

    /// The device is restarting because we asked it to. An EXPECTED disappearance,
    /// not an error — a user who just pressed WRITE & REBOOT must not be told their
    /// device fell off the network. Clears the instant `/status` answers again: the
    /// device coming back is the signal, so there's no timer and no guess.
    @Published private(set) var isRebooting = false

    private let client: KitchenSyncClient
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    /// Polls faster than `DeviceListViewModel`'s 2s: this is the screen where a
    /// quantized start is watched arming, and a 2s poll makes that flip land late.
    init(client: KitchenSyncClient, pollInterval: Duration = .milliseconds(500)) {
        self.client = client
        self.pollInterval = pollInterval
    }

    /// Idempotent — SwiftUI's `.task {}` re-invokes on every re-appear, and two
    /// poll loops against one device is a bug that only shows up as doubled traffic.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(1))
            }
        }
    }

    /// The screen went away; the polling goes with it.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Why we do or don't have this device's telemetry.
    ///
    /// A DECODE failure and a TRANSPORT failure are different problems with different fixes, and
    /// collapsing them is how a live device gets reported as dead. Found on real hardware: a
    /// KitchenSync Touch answers `/status` with HTTP 200 in a dialect this app can't read
    /// (`link-devices` ESP-029), and the app called it UNREACHABLE — sending the user off to debug
    /// a network that was working perfectly.
    enum StatusAvailability: Equatable {
        case unknown
        case available
        /// It ANSWERED, but we couldn't decode it. The device is fine; its firmware speaks a
        /// different `/status`. The way out is a firmware update, not a network fix.
        case unsupported
        /// It didn't answer at all.
        case unreachable
    }

    @Published private(set) var statusAvailability: StatusAvailability = .unknown

    func refreshStatus() async {
        do {
            let fresh = try await client.fetchStatus()
            status = fresh
            statusAvailability = .available
            isRebooting = false     // the device answering IS the signal
        } catch is DecodingError {
            // It's there. We just can't read it.
            statusAvailability = .unsupported
        } catch {
            status = nil
            statusAvailability = .unreachable
            // A failed poll while rebooting is the device still being down — which is
            // exactly what we're waiting out. Only an ANSWER clears that flag.
        }
    }

    /// Why we do or don't have the device's settings.
    ///
    /// A 404 and a dead network are DIFFERENT failures. `GET /config.json` landed on
    /// 2026-07-14; a unit on older firmware 404s on it while status, transport, live
    /// edits and OTA all keep working. Telling that user their device is unreachable
    /// is wrong — and telling a user whose WiFi dropped that their firmware is old
    /// sends them off to reflash a device that was fine.
    enum ConfigAvailability: Equatable {
        case unknown
        case available
        /// The device answered, but has no `/config.json`. Old firmware. The way OUT
        /// of this state is an OTA update, so the update path must stay reachable.
        case unsupportedByFirmware
        /// Anything else — transport error, 500, garbage body.
        case failed
    }

    @Published private(set) var configAvailability: ConfigAvailability = .unknown

    /// The device's ACTUAL settings, as opposed to `/status`'s telemetry.
    func loadConfig() async {
        do {
            config = try await client.fetchConfig()
            configAvailability = .available
        } catch KitchenSyncClientError.httpStatus(404) {
            // The one case we can attribute confidently.
            config = nil
            configAvailability = .unsupportedByFirmware
        } catch {
            config = nil
            configAvailability = .failed
        }
    }

    /// Apply one live-safe edit immediately. `KsLiveEdit`'s closed case set is the
    /// ONLY thing that reaches `/live` — reboot-required fields have no case, so
    /// they cannot be routed here even by mistake. They go through `save`.
    func apply(_ edit: KsLiveEdit) async {
        try? await client.postLive(edit)
    }

    /// The FULL form. Persists to NVS and **reboots the device** — it drops out of
    /// the Link session and all clock output stops for several seconds. Never call
    /// this for something `KsLiveEdit` can express; that's what `apply` is for.
    /// The UI must have already warned the user (T-007).
    func save(_ config: KsConfig, wifiEdits: [WifiCredentialEdit]) async {
        try? await client.postSave(config, wifiEdits: wifiEdits)
        // Optimistic on purpose: the device may well drop the connection mid-reply
        // as it restarts, so a thrown error here does NOT mean the save failed. Mark
        // it rebooting either way and let the next successful poll be the truth.
        isRebooting = true
        status = nil
    }

    /// Push a firmware `.bin` over the air, into the inactive OTA slot (dual-slot).
    ///
    /// Returns whether the device accepted it. Unlike `save`, this is NOT optimistic:
    /// a failed flash must not claim the device is rebooting, because dual-slot means
    /// the device is still happily running its OLD firmware. Telling the user to wait
    /// for a restart that is never coming is worse than telling them it failed.
    @discardableResult
    func uploadFirmware(_ binary: Data) async -> Bool {
        do {
            try await client.uploadFirmware(binary)
            isRebooting = true      // it reboots into the new slot
            status = nil
            return true
        } catch {
            return false
        }
    }

    /// Quantized Start / immediate Stop. `output: nil` is the master (`out=all`).
    /// Deliberately does NOT touch `status` — the device computes the launch state
    /// and reports it on the next poll. Guessing it here is how you end up showing
    /// a running output that never started.
    func transport(output: Int?, play: Bool) async {
        try? await client.postTransport(output: output, play: play)
    }
}
