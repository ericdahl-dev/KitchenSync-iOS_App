import SwiftUI

/// One of the four clock outputs.
///
/// **Every control in this card has a `KsLiveEdit` case, so the card cannot
/// reboot anything.** That is a structural fact, not a visual promise — there is
/// no case in the enum for a reboot-required field, so one cannot be wired up here
/// even by mistake. Reboot-required settings live behind the settings sheet (T-007).
///
/// Layout departs from the device's web UI deliberately: the page puts `RUN` in the
/// middle of the config stack, between CABLE and NUDGE. Here transport comes FIRST.
/// On a phone the transport is why you opened the app; cable and swing are why you
/// opened it once, three weeks ago.
struct OutputCardView: View {
    let index: Int
    let config: ClockOutputConfig
    let launch: TransportLaunchState
    let bpm: Double
    let linkOwnsTransport: Bool
    let onEdit: (KsLiveEdit) -> Void
    let onTransport: (Bool) -> Void

    /// Link owns THIS output only if it's set to follow Link and Link is driving.
    private var linkOwned: Bool { linkOwnsTransport && config.followsLinkTransport }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TransportButton(state: launch, bpm: bpm, linkOwned: linkOwned, onTap: onTransport)
                .disabled(!config.enabled)

            VStack(spacing: 8) {
                cablePicker
                ratePicker
                nudge
                swing
                followLink
            }
            // A disabled output DIMS — it does not vanish. The web hides the section
            // (`.hide{display:none!important}`), which on a phone is a layout jump
            // under the user's thumb, and hides the very information you need in
            // order to decide whether to turn it on. You can still read that Out 3
            // is USB C at ÷2 while it's off.
            .opacity(config.enabled ? 1 : 0.5)
            .disabled(!config.enabled)
        }
        .padding(14)
        .background(KS.panelFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(KS.line.opacity(config.enabled ? 1 : 0.5))
        )
    }

    private var header: some View {
        HStack {
            Text("CLOCK OUT \(index + 1)")
                .font(.ksDisplay(11, .semibold))
                .tracking(2)
                .foregroundStyle(KS.mut)
                .accessibilityLabel("Clock out \(index + 1)")

            Spacer()

            Toggle("", isOn: Binding(
                get: { config.enabled },
                set: { onEdit(.outputEnabled(index: index, $0)) }
            ))
            .toggleStyle(KSSwitchStyle())
            .labelsHidden()
            .accessibilityLabel("Enable clock out \(index + 1)")
        }
    }

    // USB-MIDI virtual cable — Midihub USB A..D.
    private var cablePicker: some View {
        KSField(prefix: "CABLE") {
            Picker("Cable", selection: Binding(
                get: { config.cable },
                set: { onEdit(.outputCable(index: index, $0)) }
            )) {
                ForEach(0..<4, id: \.self) { c in
                    Text("USB \(["A", "B", "C", "D"][c])").tag(c)
                }
            }
            .pickerStyle(.menu)
            .tint(KS.ink)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// The firmware's exact option strings (`ks_web.cpp`'s `build_outputs()`),
    /// values and labels both. Deliberately NOT rewritten into prettier iOS copy —
    /// the user reads these same words on the device's own page.
    private static let rates: [(value: Int, label: String)] = [
        (24, "MIDI clock (24)"),
        (48, "×2 (48)"),
        (12, "÷2 (12)"),
        (6,  "÷4 (6)"),
        (4,  "1/16 (4)"),
        (2,  "1/8 (2)"),
        (1,  "1/4 (1)"),
    ]

    private var ratePicker: some View {
        KSField(prefix: "RATE") {
            Picker("Rate", selection: Binding(
                get: { config.ppqn },
                set: { onEdit(.outputPPQN(index: index, $0)) }
            )) {
                ForEach(Self.rates, id: \.value) { rate in
                    Text(rate.label).tag(rate.value)
                }
            }
            .pickerStyle(.menu)
            .tint(KS.ink)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // Latency-comp nudge: −250…250 milli-beats, step 5 (per `build_outputs()`).
    private var nudge: some View {
        KSStepperField(
            prefix: "NUDGE",
            value: Binding(get: { config.phaseMilliBeats }, set: { _ in }),
            range: -250...250,
            onCommit: { onEdit(.outputPhase(index: index, $0)) }
        )
    }

    // Swing: 0…250 milli-beats, 0 = straight.
    private var swing: some View {
        KSStepperField(
            prefix: "SWING",
            value: Binding(get: { config.swingMilliBeats }, set: { _ in }),
            range: 0...250,
            onCommit: { onEdit(.outputSwing(index: index, $0)) }
        )
    }

    /// Picks which single thing owns this output's Start/Stop. Exactly one master
    /// per output, never two.
    private var followLink: some View {
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
        .accessibilityLabel("Follow Link transport")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 14) {
            OutputCardView(
                index: 0,
                config: ClockOutputConfig(enabled: true, cable: 0, ppqn: 24,
                                          phaseMilliBeats: 15, swingMilliBeats: 0,
                                          followsLinkTransport: false),
                launch: .armed, bpm: 128, linkOwnsTransport: false,
                onEdit: { _ in }, onTransport: { _ in }
            )
            OutputCardView(
                index: 2,
                config: .disabled,
                launch: .stopped, bpm: 128, linkOwnsTransport: false,
                onEdit: { _ in }, onTransport: { _ in }
            )
        }
        .padding()
    }
    .background(KS.bg)
}
