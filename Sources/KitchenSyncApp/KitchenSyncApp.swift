import SwiftUI

@main
struct KitchenSyncApp: App {
    var body: some Scene {
        WindowGroup {
            DeviceListView()
                // The device is dark, the reference UI is dark, and the room is
                // dark. Light mode exists so the app isn't broken on a bright
                // bench — not because it's the default.
                .preferredColorScheme(.dark)
        }
    }
}
