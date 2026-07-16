import SwiftUI

/// T-026: first-run setup. Shown when the user joins a fresh device's SoftAP — the device isn't
/// on the LAN yet, so it never appears in discovery, and the app has to meet the "set up my
/// device" expectation here. Confirms a device is on the AP, takes the user's WiFi, hands it
/// over, then points them back to their own network where the device will reappear.
///
/// The decisions live in `SetupViewModel` (tested); this is the thin surface over its phases.
struct SetupDeviceView: View {
    @StateObject private var vm = SetupViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var ssid = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch vm.phase {
                case .idle, .searching:
                    searching
                case .noDevice:
                    noDevice
                case .foundDevice, .provisioning, .failed:
                    form
                case .provisioned:
                    done
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
            .background(KS.bg.ignoresSafeArea())
            .navigationTitle("Set up a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await vm.search() }
    }

    // Confirming a device is actually answering on 192.168.4.1 before we offer a WiFi form.
    private var searching: some View {
        VStack(spacing: 14) {
            ProgressView().tint(KS.ledDim)
            Text("Looking for a device in setup mode…")
                .font(.ksMono(13)).foregroundStyle(KS.mut)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    // The phone isn't on a device AP (or nothing answered). Tell them exactly what to join.
    private var noDevice: some View {
        VStack(spacing: 14) {
            KSPowerLED(alive: false)
            Text("No device found in setup mode")
                .font(.ksMono(14)).foregroundStyle(KS.ink)
                .multilineTextAlignment(.center)
            Text("A new device broadcasts its own WiFi. In iOS Settings, join **KitchenSync-Setup** or **KSTouch-Config**, then come back.")
                .font(.ksMono(12)).foregroundStyle(KS.mut)
                .multilineTextAlignment(.center)
            Button("Check again") { Task { await vm.search() } }
                .font(.ksDisplay(14)).tracking(1.4)
                .foregroundStyle(KS.onInk)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(KS.ledFill, in: Capsule())
                .padding(.top, 6)
        }
        .padding(.top, 30)
    }

    // The device is there — collect the network to put it on.
    private var form: some View {
        VStack(spacing: 16) {
            Text("Enter the WiFi this device should join. It'll remember it and reconnect on its own from now on.")
                .font(.ksMono(12)).foregroundStyle(KS.mut)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            KSField(prefix: "SSID") {
                TextField("Your WiFi network", text: $ssid)
                    .font(.ksMono(14)).foregroundStyle(KS.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            KSField(prefix: "PASS") {
                SecureField("Network password", text: $password)
                    .font(.ksMono(14)).foregroundStyle(KS.ink)
            }

            if case .failed(let message) = vm.phase {
                Text(message)
                    .font(.ksMono(11)).foregroundStyle(KS.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await vm.provision(ssid: ssid, password: password) }
            } label: {
                HStack(spacing: 8) {
                    if vm.phase == .provisioning { ProgressView().tint(KS.onInk) }
                    Text(vm.phase == .provisioning ? "Sending…" : "Join network")
                }
                .font(.ksDisplay(14)).tracking(1.4)
                .foregroundStyle(KS.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(KS.ledFill, in: Capsule())
            }
            .disabled(ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.phase == .provisioning)
            .padding(.top, 4)
        }
    }

    // Creds sent; the device is rebooting to join. Close the loop: send them back to their
    // network, where discovery will pick the device up.
    private var done: some View {
        VStack(spacing: 14) {
            KSPowerLED(alive: true)
            Text("Sent to the device")
                .font(.ksMono(14)).foregroundStyle(KS.ink)
            Text("It's restarting to join **\(ssid)**. Reconnect this phone to that same WiFi, then it'll appear on the device list.")
                .font(.ksMono(12)).foregroundStyle(KS.mut)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .font(.ksDisplay(14)).tracking(1.4)
                .foregroundStyle(KS.onInk)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(KS.ledFill, in: Capsule())
                .padding(.top, 6)
        }
        .padding(.top, 30)
    }
}
