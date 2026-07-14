import Foundation

/// A device this app knows about — discovered via Bonjour or added manually by
/// host/IP. `host` is embedded directly in every request URL: for a discovered
/// unit that's `<mdns-name>.local`, which iOS resolves the same way a browser
/// hitting the device's own web UI would (see `KitchenSyncDiscovery`'s doc
/// comment for why this app never resolves mDNS names to raw IPs itself).
struct KitchenSyncDevice: Identifiable, Hashable, Codable {
    var id: String { host }
    var host: String
    var displayName: String
    var addedManually: Bool

    init(host: String, displayName: String? = nil, addedManually: Bool = false) {
        self.host = host
        self.displayName = displayName ?? host
        self.addedManually = addedManually
    }
}
