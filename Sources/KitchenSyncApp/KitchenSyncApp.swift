import SwiftUI

@main
struct KitchenSyncApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // The device is dark, the reference UI is dark, and the room is
                // dark. Light mode exists so the app isn't broken on a bright
                // bench — not because it's the default.
                .preferredColorScheme(.dark)
        }
    }
}

/// Placeholder root — a bench harness for the T-003 controls, with no device
/// behind it. `DeviceListView` (T-005) replaces this outright. Don't grow it.
struct RootView: View {
    @State private var outputs: [ClockOutputConfig] = [
        ClockOutputConfig(enabled: true, cable: 0, ppqn: 24, phaseMilliBeats: 15,
                          swingMilliBeats: 0, followsLinkTransport: false),
        ClockOutputConfig(enabled: true, cable: 1, ppqn: 48, phaseMilliBeats: 0,
                          swingMilliBeats: 20, followsLinkTransport: true),
        .disabled,
        ClockOutputConfig(enabled: true, cable: 3, ppqn: 12, phaseMilliBeats: -40,
                          swingMilliBeats: 0, followsLinkTransport: false),
    ]
    @State private var launch: [TransportLaunchState] = [.stopped, .running, .stopped, .armed]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        OutputCardView(
                            index: i,
                            config: outputs[i],
                            launch: launch[i],
                            bpm: 128,
                            linkOwnsTransport: true,
                            onEdit: apply,
                            onTransport: { play in
                                // No device here — fake the quantized arm so the
                                // blink is visible on the bench.
                                launch[i] = play ? .armed : .stopped
                            }
                        )
                    }
                }
                .padding()
            }
            .background(KS.bg)
            .navigationTitle("Bench harness")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func apply(_ edit: KsLiveEdit) {
        switch edit {
        case .outputEnabled(let i, let v):      outputs[i].enabled = v
        case .outputCable(let i, let v):        outputs[i].cable = v
        case .outputPPQN(let i, let v):         outputs[i].ppqn = v
        case .outputPhase(let i, let v):        outputs[i].phaseMilliBeats = v
        case .outputSwing(let i, let v):        outputs[i].swingMilliBeats = v
        case .outputFollowsLink(let i, let v):  outputs[i].followsLinkTransport = v
        default: break
        }
    }
}
