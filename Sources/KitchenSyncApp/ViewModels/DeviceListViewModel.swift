import Foundation

@MainActor
final class DeviceListViewModel: ObservableObject {
    @Published private(set) var devices: [KitchenSyncDevice] = []
    @Published private(set) var statuses: [String: KsStatus] = [:]   // keyed by device.id (== host)

    /// Whether a device is still answering.
    ///
    /// NOT a bare "did the last poll succeed". At a 2s poll, one dropped request on a
    /// busy LAN is noise, and flapping a red badge on every missed packet would be
    /// worse than saying nothing. A device goes unreachable only after
    /// `missesBeforeUnreachable` CONSECUTIVE failures; any single success resets the
    /// count, because three misses spread across a flaky hour with successes between
    /// them is a working device, not a dead one.
    enum Reachability: Equatable {
        case reachable
        case unreachable
    }

    private static let missesBeforeUnreachable = 3

    private let discovery = KitchenSyncDiscovery()
    private let store: ManualDeviceStore
    private let session: URLSession
    private var pollTask: Task<Void, Never>?
    private var consecutiveMisses: [String: Int] = [:]

    init(store: ManualDeviceStore = ManualDeviceStore(), session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    func reachability(of id: String) -> Reachability {
        (consecutiveMisses[id] ?? 0) >= Self.missesBeforeUnreachable ? .unreachable : .reachable
    }

    func start() {
        guard pollTask == nil else { return }   // .task{} re-invokes on every view re-appear
        devices = store.load()
        discovery.onHostnamesChanged = { [weak self] hostnames in
            Task { @MainActor in self?.merge(discovered: hostnames) }
        }
        discovery.start()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshAll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        discovery.stop()
        pollTask?.cancel()
        pollTask = nil
    }

    func addManualDevice(host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !devices.contains(where: { $0.host == trimmed }) else { return }
        devices.append(KitchenSyncDevice(host: trimmed, addedManually: true))
        persistManualDevices()
    }

    func removeManualDevices(at offsets: IndexSet) {
        let manual = devices.filter(\.addedManually)
        let toRemove = Set(offsets.map { manual[$0].id })
        devices.removeAll { toRemove.contains($0.id) }
        persistManualDevices()
    }

    private func persistManualDevices() {
        store.save(devices.filter(\.addedManually))
    }

    /// Internal rather than private so a test can put a DISCOVERED device into the
    /// list without standing up Bonjour — which is the only way to prove that
    /// `removeManualDevices(at:)` deletes the right row when the two kinds interleave.
    func merge(discovered hostnames: Set<String>) {
        for name in hostnames {
            let host = "\(name).local"
            if !devices.contains(where: { $0.host == host }) {
                devices.append(KitchenSyncDevice(host: host))
            }
        }
    }

    /// Pull-to-refresh. The poll loop is already running; this just jumps the queue.
    func refreshNow() async {
        await refreshAll()
    }

    private func refreshAll() async {
        let snapshot = devices
        let session = session
        await withTaskGroup(of: (String, KsStatus?).self) { group in
            for device in snapshot {
                group.addTask {
                    let client = KitchenSyncClient(host: device.host, session: session)
                    let status = try? await client.fetchStatus()
                    return (device.id, status)
                }
            }
            for await (id, status) in group {
                if let status {
                    statuses[id] = status
                    consecutiveMisses[id] = 0
                } else {
                    let misses = (consecutiveMisses[id] ?? 0) + 1
                    consecutiveMisses[id] = misses
                    // Below the threshold the last known status is still the best we
                    // have, so keep showing it. Past the threshold it is no longer a
                    // measurement, it's a fossil — a device that is gone must not still
                    // be reporting 128 bpm.
                    if misses >= Self.missesBeforeUnreachable {
                        statuses[id] = nil
                    }
                }
            }
        }
    }
}
