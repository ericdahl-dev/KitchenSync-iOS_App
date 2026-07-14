import SwiftUI

/// The fleet. `List(.plain)` with custom rows, NOT a `Form` and NOT
/// `.insetGrouped` — Apple's grouped-inset style is precisely the "generic iOS
/// settings app" this must not look like.
struct DeviceListView: View {
    @StateObject private var vm = DeviceListViewModel()
    @State private var addingDevice = false

    /// The manual devices, as their own collection. The two sections are not just
    /// cosmetic: `removeManualDevices(at:)` takes offsets into the FILTERED manual
    /// list, so making that list the `ForEach` collection means the offsets line up
    /// **by construction** rather than by a comment nobody reads.
    private var manual: [KitchenSyncDevice] { vm.devices.filter(\.addedManually) }
    private var discovered: [KitchenSyncDevice] { vm.devices.filter { !$0.addedManually } }

    var body: some View {
        NavigationStack {
            Group {
                if vm.devices.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(background)
            .navigationDestination(for: KitchenSyncDevice.self) { DeviceDetailView(device: $0) }
            .navigationTitle("KitchenSync")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addingDevice = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add device by host or IP")
                }
            }
            .sheet(isPresented: $addingDevice) {
                AddDeviceView { vm.addManualDevice(host: $0) }
            }
        }
        .task { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var list: some View {
        List {
            if !discovered.isEmpty {
                Section {
                    ForEach(discovered) { device in
                        NavigationLink(value: device) {
                            DeviceRow(device: device,
                                      status: vm.statuses[device.id],
                                      reachability: vm.reachability(of: device.id))
                        }
                    }
                } header: {
                    SectionHead("DISCOVERED")
                }
            }

            if !manual.isEmpty {
                Section {
                    // Offsets from this ForEach index `manual` — which is exactly what
                    // removeManualDevices(at:) expects.
                    ForEach(manual) { device in
                        NavigationLink(value: device) {
                            DeviceRow(device: device,
                                      status: vm.statuses[device.id],
                                      reachability: vm.reachability(of: device.id))
                        }
                    }
                    .onDelete { vm.removeManualDevices(at: $0) }
                } header: {
                    SectionHead("ADDED BY HAND")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.refreshNow() }
    }

    /// Not "No Devices." The overwhelmingly common cause is the phone being on the
    /// wrong SSID, or a network that blocks mDNS — so say that, and offer the way out.
    private var emptyState: some View {
        VStack(spacing: 14) {
            KSPowerLED(alive: false)

            Text("Looking for KitchenSync units on this network…")
                .font(.ksMono(14))
                .foregroundStyle(KS.ink)
                .multilineTextAlignment(.center)

            Text("Your phone must be on the same WiFi as the device. Some guest networks block discovery.")
                .font(.ksMono(12))
                .foregroundStyle(KS.mut)
                .multilineTextAlignment(.center)

            Button("Add by IP") { addingDevice = true }
                .font(.ksDisplay(14))
                .tracking(1.4)
                .foregroundStyle(KS.onInk)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(KS.ledFill, in: Capsule())
                .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The web's `body` gradient — what makes the black read as lit, not flat.
    private var background: some View {
        ZStack {
            KS.bg
            RadialGradient(colors: [Color(hex: 0x14181D), .clear],
                           center: .init(x: 0.5, y: -0.1),
                           startRadius: 0, endRadius: 500)
        }
        .ignoresSafeArea()
    }
}

/// The web's group head (`ks_web.cpp`): a small lime square, then tracked-out caps.
private struct SectionHead: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(KS.ledDim).frame(width: 6, height: 6)
            Text(text)
                .font(.ksDisplay(12.5, .semibold))
                .tracking(1.6)
                .foregroundStyle(KS.mut)
        }
        .accessibilityLabel(text.capitalized)
    }
}

/// A miniature rack unit.
private struct DeviceRow: View {
    let device: KitchenSyncDevice
    let status: KsStatus?
    let reachability: DeviceListViewModel.Reachability

    private var live: Bool { status != nil && reachability == .reachable }

    var body: some View {
        HStack(spacing: 12) {
            KSPowerLED(alive: live)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName.uppercased())
                    .font(.ksDisplay(15))
                    .tracking(1.2)
                    .foregroundStyle(KS.ink)
                    .lineLimit(1)

                // A manually-added device's name IS its host — don't print it twice.
                if device.displayName != device.host {
                    Text(device.host)
                        .font(.ksMono(11))
                        .foregroundStyle(KS.mut)
                        .lineLimit(1)
                }

                if reachability == .unreachable {
                    // An expected-to-be-there device that has missed three polls in a
                    // row. Say so — the whole point of the app is telling you the state
                    // of hardware on stage, and "silently stale" is the worst answer.
                    KSPill(text: "UNREACHABLE", color: KS.amber)
                        .padding(.top, 2)
                } else if let status {
                    summaryPill(status.transportSummary)
                        .padding(.top, 2)
                } else if device.addedManually {
                    KSPill(text: "MANUAL")
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                KSGlass(bpm: status?.bpm ?? 0, size: 26)
                // "0 PEERS" for a device that isn't answering is a lie dressed as
                // a measurement. If there's no status, we don't know the peer count.
                Text(status.map { "\($0.peers) PEERS" } ?? "NO SIGNAL")
                    .font(.ksMono(10.5))
                    .tracking(1.6)
                    .foregroundStyle(KS.mut)
            }
        }
        .padding(.vertical, 10)
        .opacity(live ? 1 : 0.55)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(KS.line)
    }

    @ViewBuilder
    private func summaryPill(_ summary: KsStatus.TransportSummary) -> some View {
        switch summary {
        case .playing: KSPill(text: "PLAYING", on: true)
        case .arming:  KSPill(text: "ARMING", color: KS.amber)
        case .stopped: KSPill(text: "STOPPED")
        }
    }
}

/// A single host field. Hostname or raw IP — discovery misses units on other
/// subnets, and a venue's guest WiFi may block mDNS entirely.
struct AddDeviceView: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                KSField(prefix: "HOST") {
                    TextField("kitchensync-xxxx.local or 192.168.1.42", text: $host)
                        .font(.ksMono(14))
                        .foregroundStyle(KS.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit(add)
                }

                Text("Bonjour only reaches the local subnet. Add a unit by host or IP if it isn't found.")
                    .font(.ksMono(11))
                    .foregroundStyle(KS.mut)

                Spacer()
            }
            .padding()
            .background(KS.bg.ignoresSafeArea())
            .navigationTitle("Add device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func add() {
        onAdd(host)
        dismiss()
    }
}
