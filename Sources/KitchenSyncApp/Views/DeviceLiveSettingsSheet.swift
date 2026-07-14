import SwiftUI

/// Everything you can change **live**. Nothing here reboots the device.
///
/// That is a structural guarantee, not a promise: every control on this sheet routes through a
/// `KsLiveEdit` case, and there is no case for a reboot-only field (WiFi, metronome *enable*,
/// follow-beat *enable*). Those live behind the door at the bottom, on their own surface, with the
/// consequence band and the `WRITE & REBOOT` key.
///
/// **No surface ever mixes live and reboot controls.** The device's own web page puts the metronome
/// ENABLE toggle and the metro-accent toggle forty pixels apart, as the identical component, in the
/// same box — one applies instantly and the other restarts the device mid-set, with nothing on
/// screen to tell them apart. Better labelling would not have fixed that. Not being adjacent does.
///
/// Sections appear only for hardware the device actually reports (`link-devices` ESP-030): no
/// speaker, no click section; no strip, no LED section. Solder a strip onto a Touch and flip one
/// FIRMWARE flag, and the LED section shows up here with no change to this app.
struct DeviceLiveSettingsSheet: View {
    let deviceName: String
    let config: KsConfig
    let status: KsStatus?
    let clockFault: ClockFault
    let onEdit: (KsLiveEdit) -> Void
    let onSave: (KsConfig, [WifiCredentialEdit]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    liveBanner

                    clockOutputs

                    // Only if a speaker is fitted. A volume slider for a speaker that doesn't
                    // exist is a UI lying about the hardware.
                    if let m = config.metronome { click(m) }
                    if let l = config.led { led(l) }

                    diagnostics

                    deviceSetupDoor
                }
                .padding()
            }
            .background(KS.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSetup) {
                DeviceSettingsSheet(deviceName: deviceName, config: config, onSave: onSave)
            }
        }
        .presentationDetents([.large])
    }

    /// The counterpart of Device Setup's consequence band. It says the *reassuring* thing, and it
    /// is the reason a user can touch anything here without thinking twice.
    private var liveBanner: some View {
        Text("Everything on this screen applies instantly. Nothing here reboots the device.")
            .font(.ksMono(12))
            .foregroundStyle(KS.mut)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(KS.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KS.line))
    }

    // MARK: Clock outputs — the set-once half. Nudge and swing stay on Performance.

    private var clockOutputs: some View {
        KSSectionRail(title: "MIDI CLOCK OUT") {
            HStack {
                Text("master enable").font(.ksMono(12)).foregroundStyle(KS.mut)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.clockOutEnabled },
                    set: { onEdit(.clockOutEnabled($0)) }
                ))
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()
                .accessibilityLabel("Master clock out enable")
            }

            // One card per element — the array LENGTH is the device's real output count
            // (1 on a Touch, 4 on a P4), never a hardcoded 4.
            ForEach(Array(config.clock.enumerated()), id: \.offset) { i, out in
                SettingsOutputCard(index: i, config: out, onEdit: onEdit)
            }
        }
    }

    // MARK: Click — only when a speaker is fitted

    private func click(_ m: MetronomeConfig) -> some View {
        KSSectionRail(title: "CLICK") {
            // The metronome ENABLE is NOT here. It has no KsLiveEdit case — it needs a full
            // /save, which REBOOTS. It lives behind the door, and this row only reports it.
            RebootOnlyStatusRow(label: "enable", value: m.enabled ? "ON" : "OFF")

            HStack {
                Text("accent").font(.ksMono(12)).foregroundStyle(KS.mut)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { m.accent },
                    set: { onEdit(.metronomeAccent($0)) }
                ))
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()
                .accessibilityLabel("Click accent")
            }

            KSLiveSlider(label: "VOL", range: 0...100, value: m.volume) { onEdit(.metronomeVolume($0)) }

            KSField(prefix: "VOICE") {
                Picker("Voice", selection: Binding(
                    get: { m.voice },
                    set: { onEdit(.metronomeVoice($0)) }
                )) {
                    Text("Tone").tag(0)
                    Text("Click").tag(1)
                    Text("Wood").tag(2)
                }
                .pickerStyle(.menu)
                .tint(KS.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: LED — only when a strip is wired

    private func led(_ l: LedConfig) -> some View {
        KSSectionRail(title: "LED STRIP") {
            HStack {
                Text("enable").font(.ksMono(12)).foregroundStyle(KS.mut)
                Spacer()
                Toggle("", isOn: Binding(get: { l.enabled }, set: { onEdit(.ledEnabled($0)) }))
                    .toggleStyle(KSSwitchStyle())
                    .labelsHidden()
                    .accessibilityLabel("LED enable")
            }

            KSLiveSlider(label: "BRIGHT", range: 0...100, value: l.brightness) { onEdit(.ledBrightness($0)) }
            KSLiveSlider(label: "FADE", range: 0...100, value: l.fade) { onEdit(.ledFade($0)) }

            KSField(prefix: "MODE") {
                Picker("Mode", selection: Binding(get: { l.mode }, set: { onEdit(.ledMode($0)) })) {
                    Text("Chase").tag(0)
                    Text("Flash").tag(1)
                    Text("Fill").tag(2)
                }
                .pickerStyle(.menu)
                .tint(KS.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            KSField(prefix: "BEAT") {
                ColorPicker("Beat colour", selection: Binding(
                    get: { Color(hex: l.beatColor) },
                    set: { onEdit(.ledBeatColor($0.rgb24)) }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            KSField(prefix: "ACCENT") {
                ColorPicker("Accent colour", selection: Binding(
                    get: { Color(hex: l.accentColor) },
                    set: { onEdit(.ledAccentColor($0.rgb24)) }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: Diagnostics

    private var diagnostics: some View {
        KSSectionRail(title: "DIAGNOSTICS") {
            DisclosureGroup {
                VStack(spacing: 6) {
                    if let t = status?.tickHealth {
                        // LIFETIME totals. Shown, but not an alarm — only a counter that is MOVING
                        // right now is news (T-018). Warning on `> 0` lit an amber dot forever on a
                        // device that dropped a tick at boot and has been flawless since.
                        DiagLine("dropped ticks", "\(t.droppedTicks) since boot",
                                 warn: clockFault == .droppingNow)
                        DiagLine("overruns", "\(t.overruns) since boot",
                                 warn: clockFault == .droppingNow)
                        DiagLine("max gap µs", "\(t.maxGapMicros)")
                        DiagLine("max work µs", "\(t.maxWorkMicros)")

                        if clockFault == .droppingNow {
                            Text("The clock task is dropping ticks RIGHT NOW.")
                                .font(.ksMono(11))
                                .foregroundStyle(KS.amberText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let p = status?.phaseHealth {
                        // maxStepMicros is the number that, unread, cost 138 seconds of silent DIN
                        // clock (ESP-027). It SHOULD have a warning threshold — but nobody has told
                        // us what it is, and inventing one would be worse than showing the number.
                        DiagLine("max origin step µs", "\(p.maxStepMicros)")
                        DiagLine("rtt min/max µs", "\(p.rttMinMicros)/\(p.rttMaxMicros)")
                    }
                    if status?.tickHealth == nil && status?.phaseHealth == nil {
                        Text("not measured")
                            .font(.ksMono(12))
                            .foregroundStyle(KS.mut)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Text("tick / phase health").font(.ksMono(12)).foregroundStyle(KS.mut)
                    if clockFault == .droppingNow {
                        Circle().fill(KS.amber).frame(width: 6, height: 6)
                    }
                }
            }
            .tint(KS.mut)
        }
    }

    // MARK: The door

    /// A DOOR, not a section. Everything on the other side of it reboots the device, and it is on
    /// its own surface for exactly that reason — the whole point of this split is that a live
    /// slider and a reboot toggle are never adjacent.
    private var deviceSetupDoor: some View {
        Button { showingSetup = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DEVICE SETUP")
                        .font(.ksDisplay(12.5, .semibold))
                        .tracking(1.4)
                        .foregroundStyle(KS.amberText)
                    Text("WiFi, metronome enable, follow beat — these reboot the device")
                        .font(.ksMono(11))
                        .foregroundStyle(KS.mut)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(KS.mut)
            }
            .padding(12)
            .background(KS.consequence, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(KS.amber.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
    }
}

/// One clock output's SET-ONCE controls. Nudge and swing are not here — they're on Performance,
/// because they're what you reach for while the band is playing.
private struct SettingsOutputCard: View {
    let index: Int
    let config: ClockOutputConfig
    let onEdit: (KsLiveEdit) -> Void

    private static let rates: [(value: Int, label: String)] = [
        (24, "MIDI clock (24)"), (48, "×2 (48)"), (12, "÷2 (12)"), (6, "÷4 (6)"),
        (4, "1/16 (4)"), (2, "1/8 (2)"), (1, "1/4 (1)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CLOCK OUT \(index + 1)")
                    .font(.ksDisplay(11, .semibold))
                    .tracking(2)
                    .foregroundStyle(KS.mut)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.enabled },
                    set: { onEdit(.outputEnabled(index: index, $0)) }
                ))
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()
                .accessibilityLabel("Enable clock out \(index + 1)")
            }

            KSField(prefix: "CABLE") {
                Picker("Cable", selection: Binding(
                    get: { config.cable },
                    set: { onEdit(.outputCable(index: index, $0)) }
                )) {
                    ForEach(0..<4, id: \.self) { c in
                        Text("USB \(["A", "B", "C", "D"][c])").tag(c)
                    }
                }
                .pickerStyle(.menu).tint(KS.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // The firmware's exact option strings — the user reads the same words on the device's
            // own page. Not rewritten into prettier iOS copy.
            KSField(prefix: "RATE") {
                Picker("Rate", selection: Binding(
                    get: { config.ppqn },
                    set: { onEdit(.outputPPQN(index: index, $0)) }
                )) {
                    ForEach(Self.rates, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu).tint(KS.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { config.followsLinkTransport },
                    set: { onEdit(.outputFollowsLink(index: index, $0)) }
                ))
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()

                Text("follow Link transport")
                    .font(.ksMono(12))
                    .foregroundStyle(KS.mut)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Follow Link transport, output \(index + 1)")
        }
        .padding(12)
        .background(KS.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KS.line))
    }
}

/// A setting that cannot be changed from a LIVE surface, because changing it reboots the device.
/// Rendered as a value with a chevron, never as a control — you cannot fat-finger a read-only row
/// into restarting a box mid-set.
private struct RebootOnlyStatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.ksMono(12)).foregroundStyle(KS.mut)
            Spacer()
            Text(value).font(.ksMono(13, .medium)).foregroundStyle(KS.ink)
            KSPill(text: "REBOOTS", color: KS.amber)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). Changing this reboots the device; it lives in Device Setup.")
    }
}

private struct DiagLine: View {
    let label: String
    let value: String
    var warn = false

    init(_ label: String, _ value: String, warn: Bool = false) {
        self.label = label
        self.value = value
        self.warn = warn
    }

    var body: some View {
        HStack {
            Text(label).font(.ksMono(11)).foregroundStyle(KS.mut)
            Spacer()
            Text(value)
                .font(.ksMono(12, .medium))
                .monospacedDigit()
                .foregroundStyle(warn ? KS.amberText : KS.ink)
        }
    }
}
