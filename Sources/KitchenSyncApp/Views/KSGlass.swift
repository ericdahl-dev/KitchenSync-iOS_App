import SwiftUI

/// The tempo readout — the device's `.scr` / `.readout`.
///
/// The web UI draws a 7-segment display with an all-segments-lit "188.8" ghost
/// behind the live value, imitating the unlit segments of a real LED display.
/// That trick REQUIRES the DSEG7 Classic face. It isn't bundled yet, so per the
/// design direction the ghost layer is deliberately DROPPED: a grey duplicate of
/// a non-segmented font doesn't read as unlit segments, it reads as a rendering
/// bug. Bundle DSEG7 and the ghost comes back — see `ghost` below.
struct KSGlass: View {
    let bpm: Double
    var size: CGFloat = 58

    private var text: String {
        bpm > 0 ? String(format: "%.1f", bpm) : "--.-"
    }

    var body: some View {
        Text(text)
            .font(.ksMono(size, .heavy))
            .monospacedDigit()
            .foregroundStyle(KS.led)
            .shadow(color: KS.led.opacity(0.45), radius: size * 0.24)
            .contentTransition(.numericText())
            .padding(.horizontal, size * 0.22)
            .padding(.vertical, size * 0.12)
            .frame(minWidth: size * 2.2)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x0A0D0A), Color(hex: 0x070907)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RadialGradient(colors: [KS.led.opacity(0.08), .clear],
                                       center: .init(x: 0.5, y: -0.2),
                                       startRadius: 0, endRadius: size * 3.8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color(hex: 0x1F261B))
                    )
            }
            .accessibilityLabel("Tempo")
            .accessibilityValue(bpm > 0 ? "\(text) BPM" : "No tempo")
    }
}

/// The `.pwr` LED — breathes while the device is answering, goes dead grey when
/// it isn't. The web page never needs an offline state; the app needs one
/// constantly, and it's the first thing a user checks. (Proper unreachable
/// modelling — consecutive-failure thresholds — is T-010.)
struct KSPowerLED: View {
    let alive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(alive ? KS.led : KS.mut)
            .frame(width: 9, height: 9)
            .shadow(color: alive ? KS.led : .clear, radius: 5)
            .opacity(alive && dim && !reduceMotion ? 0.45 : 1)
            .animation(alive && !reduceMotion
                       ? .easeInOut(duration: 1.7).repeatForever(autoreverses: true)
                       : .default,
                       value: dim)
            .onAppear { dim = true }
            .accessibilityHidden(true)
    }
}
