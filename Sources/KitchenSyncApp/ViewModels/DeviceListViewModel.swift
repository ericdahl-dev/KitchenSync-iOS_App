import Foundation

@MainActor
final class DeviceListViewModel: ObservableObject {
    @Published private(set) var devices: [KitchenSyncDevice] = []
    @Published private(set) var statuses: [String: KsStatus] = [:]   // keyed by device.id (== host)

    private let discovery = KitchenSyncDiscovery()
    private let store: ManualDeviceStore
    private var pollTask: Task<Void, Never>?

    init(store: ManualDeviceStore = ManualDeviceStore()) {
        self.store = store
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

    private func merge(discovered hostnames: Set<String>) {
        for name in hostnames {
            let host = "\(name).local"
            if !devices.contains(where: { $0.host == host }) {
                devices.append(KitchenSyncDevice(host: host))
            }
        }
    }

    private func refreshAll() async {
        let snapshot = devices
        await withTaskGroup(of: (String, KsStatus?).self) { group in
            for device in snapshot {
                group.addTask {
                    let client = KitchenSyncClient(host: device.host)
                    let status = try? await client.fetchStatus()
                    return (device.id, status)
                }
            }
            for await (id, status) in group {
                if let status {
                    statuses[id] = status
                }
            }
        }
    }
}
