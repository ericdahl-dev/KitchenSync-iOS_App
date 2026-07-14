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

    func refreshStatus() async {
        let fresh = try? await client.fetchStatus()
        status = fresh
        // A failed poll while rebooting is the device still being down — which is
        // exactly what we're waiting out. Only an ANSWER clears the flag.
        if fresh != nil { isRebooting = false }
    }

    /// The device's ACTUAL settings, as opposed to `/status`'s telemetry.
    /// A device on firmware older than 2026-07-14 has no `/config.json` and will
    /// 404 here — distinguishing that from a real failure is T-009.
    func loadConfig() async {
        config = try? await client.fetchConfig()
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

    /// Quantized Start / immediate Stop. `output: nil` is the master (`out=all`).
    /// Deliberately does NOT touch `status` — the device computes the launch state
    /// and reports it on the next poll. Guessing it here is how you end up showing
    /// a running output that never started.
    func transport(output: Int?, play: Bool) async {
        try? await client.postTransport(output: output, play: play)
    }
}
