import SwiftUI

@main
struct KitchenSyncApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Placeholder root view — exists only so the app has something to launch (T-001).
/// `DeviceListView` (T-005) replaces this; don't grow it, the view model it should
/// be driven by (`DeviceListViewModel`) is already written and waiting.
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "No UI yet",
            systemImage: "metronome",
            description: Text("The view layer is T-003 through T-008.")
        )
    }
}
