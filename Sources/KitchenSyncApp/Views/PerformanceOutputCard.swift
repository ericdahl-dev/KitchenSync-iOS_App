import SwiftUI

/// One clock output, as it appears **on stage**.
///
/// The transport button, plus the two controls you actually reach for mid-set: NUDGE and SWING.
/// Nothing else. Cable, rate and follow-Link live in Settings, because knocking a cable assignment
/// loose during a song is a way to ruin it, and you cannot knock what is not on the screen.
///
/// NUDGE earns its place here on the firmware's own account: `nudge_mbeats` is live via `/nudge`,
/// no reboot, and the comment says it "slides the RC-505 into the pocket". That is a playing
/// control, not a setup one. Swing is the same kind of thing — a groove you feel your way to while
/// the band is going.
///
/// Every control here has a `KsLiveEdit` case, so this card structurally cannot reboot the device.
struct PerformanceOutputCard: View {
    let index: Int
    let config: ClockOutputConfig
    let launch: TransportLaunchState
    let bpm: Double
    let linkOwnsTransport: Bool
    let onEdit: (KsLiveEdit) -> Void
    let onTransport: (Bool) -> Void

    private var linkOwned: Bool { linkOwnsTransport && config.followsLinkTransport }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TransportButton(state: launch, bpm: bpm, linkOwned: linkOwned, onTap: onTransport)
                .disabled(!config.enabled)

            VStack(spacing: 8) {
                KSStepperField(
                    prefix: "NUDGE",
                    value: Binding(get: { config.phaseMilliBeats }, set: { _ in }),
                    range: -250...250,
                    onCommit: { onEdit(.outputPhase(index: index, $0)) }
                )
                KSStepperField(
                    prefix: "SWING",
                    value: Binding(get: { config.swingMilliBeats }, set: { _ in }),
                    range: 0...250,
                    onCommit: { onEdit(.outputSwing(index: index, $0)) }
                )
            }
            // A disabled output DIMS — it does not vanish. Hiding it is a layout jump under the
            // user's thumb, and you lose the ability to see what it's set to before enabling it.
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

    /// Read-only on stage. Enabling or disabling an output is a Settings act — doing it by accident
    /// mid-song silences a device, and the transport button below is the only thing here that
    /// should be one tap from changing what the audience hears.
    private var header: some View {
        HStack {
            Text("CLOCK OUT \(index + 1)")
                .font(.ksDisplay(11, .semibold))
                .tracking(2)
                .foregroundStyle(KS.mut)

            Spacer()

            if !config.enabled {
                KSPill(text: "OFF")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clock out \(index + 1)\(config.enabled ? "" : ", off")")
    }
}
