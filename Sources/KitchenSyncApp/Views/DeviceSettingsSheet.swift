import SwiftUI

/// The reboot-required settings, quarantined.
///
/// **Everything in here restarts the device.** Saving POSTs the full form to
/// `/save`, which persists to NVS and reboots — the unit drops out of the Link
/// session and all clock output stops for several seconds. Mid-set, that is a
/// destructive act, and the UI has to say so out loud. The device's own web page
/// says nothing at all; its only signal is the button's label. That gap is the
/// biggest single difference between the reference UI and this one.
///
/// The contents are generated from `KsConfig.rebootRequiredFormKeys` — the same set
/// the partition test (T-012) holds disjoint from `KsLiveEdit`. An untagged
/// reboot-required control in here is therefore impossible by construction, and a
/// live-editable control cannot wander in.
struct DeviceSettingsSheet: View {
    let deviceName: String
    let config: KsConfig
    let onSave: (KsConfig, [WifiCredentialEdit]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft: KsConfig
    @State private var wifiEdits: [WifiCredentialEdit]
    @State private var confirming = false

    init(deviceName: String, config: KsConfig, onSave: @escaping (KsConfig, [WifiCredentialEdit]) -> Void) {
        self.deviceName = deviceName
        self.config = config
        self.onSave = onSave
        _draft = State(initialValue: config)
        // Passwords seed EMPTY — they were never on the wire. Blank means "keep".
        _wifiEdits = State(initialValue: config.seededWifiEdits())
    }

    private var hasEdits: Bool {
        draft != config || wifiEdits != config.seededWifiEdits()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    consequenceBand

                    // Order is DELIBERATELY the reverse of the web page's. It puts WiFi
                    // first "for the phone setup flow" — but if you're in this sheet,
                    // discovery already found the device. WiFi is the least likely thing
                    // you're changing and by far the most dangerous to fat-finger. Last.
                    //
                    // These sections appear ONLY if the device reports the hardware. A board
                    // with no speaker doesn't get a metronome toggle — drawing one for
                    // hardware that isn't fitted is how a UI lies. Solder a strip onto a
                    // Touch and flip one FIRMWARE flag, and the section shows up here with
                    // no change to this app at all.
                    if draft.metronome != nil { metronome }
                    if draft.followBeatEnabled != nil { followBeat }
                    wifi

                    writeAndReboot
                }
                .padding()
            }
            .background(KS.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(hasEdits)
            .alert("Write & Reboot \(deviceName)?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Write & Reboot", role: .destructive) {
                    onSave(draft, wifiEdits)
                    dismiss()
                }
            } message: {
                Text("The device will restart, drop out of the Link session, and stop all clock output for about ten seconds.")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: The warning

    private var consequenceBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THESE SETTINGS REBOOT THE DEVICE")
                .font(.ksDisplay(12.5, .semibold))
                .tracking(1.4)
                .foregroundStyle(KS.amberText)

            Text("Saving writes to flash and restarts. The device drops out of the Link session and all clock output stops for about ten seconds.")
                .font(.ksMono(12))
                .foregroundStyle(KS.mut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(KS.consequence, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(KS.amber.opacity(0.35))
        )
    }

    // MARK: The three reboot-required settings

    private var metronome: some View {
        KSSectionRail(title: "METRONOME") {
            rebootToggle(
                label: "enable",
                key: "metronome",
                caption: "The audio codec only starts at boot, so this cannot be applied live. Volume, voice and accent CAN — they're on the device screen.",
                // Only rendered when `draft.metronome != nil`, so the device HAS a speaker.
                isOn: Binding(
                    get: { draft.metronome?.enabled ?? false },
                    set: { draft.metronome?.enabled = $0 }
                )
            )
        }
    }

    private var followBeat: some View {
        KSSectionRail(title: "FOLLOW BEAT (MIC)") {
            rebootToggle(
                label: "enable",
                key: "follow_beat",
                caption: "Listens to the room and follows the beat it hears.",
                isOn: Binding(
                    get: { draft.followBeatEnabled ?? false },
                    set: { draft.followBeatEnabled = $0 }
                )
            )
        }
    }

    private var wifi: some View {
        KSSectionRail(title: "WIFI NETWORKS") {
            ForEach($wifiEdits) { $edit in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SLOT \(edit.id + 1)")
                            .font(.ksMono(10))
                            .tracking(1.6)
                            .foregroundStyle(KS.mut)
                        if config.wifi.indices.contains(edit.id), config.wifi[edit.id].passwordIsSet {
                            // A lime SET pill, never a row of dots. Dots imply an
                            // editable secret you could select and delete — there is no
                            // such thing here; the password is write-only.
                            KSPill(text: "SET", on: true)
                        }
                        Spacer()
                        rebootsTag(for: "wifi_ssid\(edit.id == 0 ? "" : String(edit.id))")
                    }

                    KSField(prefix: "SSID") {
                        TextField(edit.id == 0 ? "required" : "optional", text: $edit.ssid)
                            .font(.ksMono(13))
                            .foregroundStyle(KS.ink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    KSField(prefix: "PASS") {
                        SecureField(
                            config.wifi.indices.contains(edit.id) && config.wifi[edit.id].passwordIsSet
                                ? "keep current" : "",
                            text: $edit.password
                        )
                        .font(.ksMono(13))
                        .foregroundStyle(KS.ink)
                        .textInputAutocapitalization(.never)
                    }

                    Text("Leave the password blank to keep the saved one. Clear the SSID to forget this network.")
                        .font(.ksMono(10.5))
                        .foregroundStyle(KS.mut)
                }
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: Pieces

    private func rebootToggle(label: String, key: String, caption: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.ksMono(12)).foregroundStyle(KS.mut)
                rebootsTag(for: key)
                Spacer()
                Toggle("", isOn: isOn)
                    .toggleStyle(KSSwitchStyle())
                    .labelsHidden()
                    .accessibilityLabel("\(label). Changing this reboots the device.")
            }
            Text(caption)
                .font(.ksMono(10.5))
                .foregroundStyle(KS.mut)
        }
    }

    /// Renders ONLY for keys the partition test says are reboot-required. A control in
    /// this sheet whose key isn't in that set silently gets no tag — which is a bug
    /// the test would already have caught upstream, because such a key cannot exist.
    @ViewBuilder
    private func rebootsTag(for key: String) -> some View {
        if KsConfig.rebootRequiredFormKeys.contains(key) {
            KSPill(text: "REBOOTS", color: KS.amber)
        }
    }

    /// `.write` — ported literally, 6pt of key travel that bottoms out under the thumb.
    private var writeAndReboot: some View {
        WriteAndRebootButton { confirming = true }
            .disabled(!hasEdits)
            .opacity(hasEdits ? 1 : 0.4)
            .padding(.top, 4)
    }
}

/// The commit key. `internal` to the settings feature by intent — it must be
/// unreachable from the live surface, where nothing may reboot the device.
struct WriteAndRebootButton: View {
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text("WRITE & REBOOT")
                .font(.ksDisplay(16))
                .tracking(2)
                .foregroundStyle(KS.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(KS.ledFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                // `.write:active{transform:translateY(4px);box-shadow:0 1px 0 #5e8a16}`
                .offset(y: pressed ? 4 : 0)
                .shadow(color: Color(hex: 0x5E8A16), radius: 0, y: pressed ? 1 : 6)
                .shadow(color: KS.led.opacity(0.5), radius: 15, y: pressed ? 4 : 16)
                .animation(.easeOut(duration: 0.06), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
