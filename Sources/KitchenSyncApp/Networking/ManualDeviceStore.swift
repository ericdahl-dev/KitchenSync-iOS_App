import Foundation

/// Persists devices the user added by host/IP (units off the discoverable
/// subnet — Bonjour discovery only reaches the local network). Bonjour-
/// discovered devices are never persisted here; they just reappear on the next
/// scan, which is simpler than reconciling a stale cached list against
/// whatever's actually on the LAN right now.
struct ManualDeviceStore {
    private let key = "manualDevices.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [KitchenSyncDevice] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([KitchenSyncDevice].self, from: data)) ?? []
    }

    func save(_ devices: [KitchenSyncDevice]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: key)
    }
}
