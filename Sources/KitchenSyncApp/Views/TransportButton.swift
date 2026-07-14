import SwiftUI

/// One output's Start/Stop. The single most important control in the app.
///
/// Play is QUANTIZED: a tap arms the output, and the device fires it on the next
/// bar line — which may be most of a bar away. Stop is immediate. The blink on
/// `.armed` is therefore the only evidence a tap registered, and it is
/// load-bearing, not decoration.
///
/// `state` comes straight from `/status.launch[N]` on every poll. This view never
/// predicts the armed→running transition; the device computes it and reports it.
/// The `TimelineView` below drives a blink PHASE only.
struct TransportButton: View {
    let state: TransportLaunchState
    /// Session tempo — the blink rides it, so the button pulses in time with the music.
    let bpm: Double
    /// Link owns this output's transport (`follow_link`) — taps get rejected, loudly.
    let linkOwned: Bool
    /// Caller passes `TransportTapIntent.play(for: state)`. Not re-derived here.
    let onTap: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nakPulse = false

    private var appearance: TransportAppearance {
        .appearance(for: state, linkOwned: linkOwned)
    }

    var body: some View {
        Button(action: tap) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                    paused: !appearance.blinks || reduceMotion)) { context in
                face(lit: litPhase(at: context.date))
            }
        }
        .buttonStyle(.plain)
        // Rejected taps must still be FELT, so hit-testing stays on even when
        // `acceptsTap` is false. `.disabled()` would swallow the tap silently.
        .contentShape(Rectangle())
        .sensoryFeedback(trigger: state) { old, new in
            if old == .stopped && new == .armed   { return .impact(weight: .heavy) }   // tap landed
            if old == .armed   && new == .running { return .impact(weight: .medium) }  // the bar hit
            if new == .stopped && old != .stopped { return .impact(flexibility: .rigid) }
            return nil
        }
        .sensoryFeedback(.warning, trigger: nakPulse)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(appearance.acceptsTap ? "" : "Link owns transport for outputs set to follow it.")
    }

    // MARK: Face

    @ViewBuilder
    private func face(lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        ZStack {
            shape.fill(fill)
            shape.strokeBorder(strokeColor, lineWidth: state == .armed ? 1.5 : 1)

            HStack(spacing: 8) {
                // Reduced motion can't rely on the blink, so the armed state grows
                // a glyph. The label already carries the state — the firmware chose
                // to make the label BE the state, and that choice pays off here.
                if reduceMotion && state == .armed {
                    Image(systemName: "hourglass")
                }
                Text(appearance.label)
                    .font(.ksDisplay(17))
                    .tracking(2)
            }
            .foregroundStyle(foreground)

            if linkOwned {
                HStack {
                    Spacer()
                    Text("LINK")
                        .font(.ksMono(9.5, .medium))
                        .tracking(1.4)
                        .foregroundStyle(KS.amber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(KS.amber.opacity(nakPulse ? 1 : 0.5)))
                        .padding(.trailing, 12)
                }
            }
        }
        // ≥64pt. The web's `.tgl` is ~40pt — under the 44pt floor, and this is the
        // control you hit under pressure with a monitor wedge in your face.
        .frame(maxWidth: .infinity, minHeight: 64)
        .opacity(bodyOpacity(lit: lit))
        .shadow(color: glowColor(lit: lit), radius: glowRadius(lit: lit))
        .overlay(nakOverlay)
        .animation(.easeOut(duration: 0.18), value: state)
    }

    /// Hard-edged, ~35% duty, at `60/bpm` — the firmware's own beat cadence
    /// (`ui_chrome.c`'s `setInterval(flashBeat, 60000/bpm)`).
    ///
    /// Deliberately NOT `.repeatForever(autoreverses: true)`: a soft sinusoidal
    /// throb is the universal visual language of "loading, please wait", which is
    /// the exact wrong message. Armed is not loading. Armed is a cocked hammer.
    private func litPhase(at date: Date) -> Bool {
        guard appearance.blinks, !reduceMotion else { return true }
        let period = 60.0 / max(bpm, 40)
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        return phase < 0.35
    }

    private var fill: LinearGradient {
        switch appearance.face {
        case .ember: return KS.emberFill
        case .amber: return KS.amberFill
        case .lime:  return KS.ledFill
        }
    }

    private var strokeColor: Color {
        switch appearance.face {
        case .ember: return KS.line
        case .amber: return KS.amber
        case .lime:  return KS.ledEdge
        }
    }

    private var foreground: Color {
        switch appearance.face {
        case .ember: return KS.ember
        case .amber: return KS.amber
        case .lime:  return KS.onInk
        }
    }

    private func bodyOpacity(lit: Bool) -> Double {
        if linkOwned { return 0.45 }
        return lit ? 1.0 : 0.42
    }

    private func glowColor(lit: Bool) -> Color {
        switch appearance.face {
        case .lime:  return KS.led.opacity(0.45)   // the tempo glass's bloom, promoted
        case .amber: return KS.amber.opacity(lit ? 0.5 : 0)
        case .ember: return .clear
        }
    }

    private func glowRadius(lit: Bool) -> CGFloat {
        switch appearance.face {
        case .lime:  return 18
        case .amber: return 14
        case .ember: return 0
        }
    }

    /// The firmware's `nak` animation — a rejected key pulses amber rather than
    /// doing nothing. `ks_web.cpp`: *"A key aimed at a Link-owned output must not
    /// silently do nothing."*
    private var nakOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(KS.amber, lineWidth: 1.5)
            .opacity(nakPulse ? 1 : 0)
            .animation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true), value: nakPulse)
    }

    private var accessibilityLabel: String {
        let name = appearance.label.capitalized
        return linkOwned ? "\(name). Link owns transport." : name
    }

    private func tap() {
        guard appearance.acceptsTap else {
            nakPulse = true
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                nakPulse = false
            }
            return
        }
        onTap(TransportTapIntent.play(for: state))
    }
}

#Preview {
    VStack(spacing: 16) {
        TransportButton(state: .stopped, bpm: 128, linkOwned: false) { _ in }
        TransportButton(state: .armed,   bpm: 128, linkOwned: false) { _ in }
        TransportButton(state: .running, bpm: 128, linkOwned: false) { _ in }
        TransportButton(state: .running, bpm: 128, linkOwned: true)  { _ in }
    }
    .padding()
    .background(KS.bg)
}
