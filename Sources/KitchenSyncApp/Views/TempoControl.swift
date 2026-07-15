import SwiftUI

/// The set-tempo surface (ESP-037). Three ways in, one number out:
///
///  - **Tap** — computed HERE, from local tap intervals, never sent as tap events over
///    WiFi (network jitter would wreck the timing). The app resolves taps to a BPM and
///    sends that.
///  - **Numeric** — type it.
///  - **± steppers** — nudge by 1.
///
/// All three call `onSet(bpm)`, which routes through `KsLiveEdit.setTempo` → `/live`.
/// Only shown when the device actually has a settable tempo (`config.tempo != nil`);
/// a listener-only box has no business drawing this.
///
/// The number shown is the SET tempo (`config.tempo`), not the effective one the clock
/// is running (`status.bpm`) — so it doesn't jump when a Link session takes over. When
/// Link IS driving, the control says so, because a tempo you set that the device is
/// currently ignoring is exactly the kind of silent lie this app keeps stamping out.
struct TempoControl: View {
    /// The tempo to SHOW — the effective one (what the box is clocking), so it follows
    /// Link and never jumps. See `DeviceDetailViewModel.tempoDisplay`.
    let tempo: Double
    /// True when a Link session is driving. Link owns the tempo; the set controls stand
    /// down and just report Link's value.
    let linkDriving: Bool
    let onSet: (Double) -> Void

    static let minBPM = 20.0
    static let maxBPM = 300.0

    @State private var editing = false
    @State private var draft = ""
    @State private var tapTimes: [Date] = []
    /// Show an edit immediately instead of waiting a poll for `status.bpm` to catch up —
    /// otherwise a ± tap looks dead for half a second, then snaps. Cleared once the
    /// device's reported tempo converges on it.
    @State private var optimistic: Double?

    private var shown: Double { optimistic ?? tempo }
    private var editable: Bool { !linkDriving }

    private func clamp(_ v: Double) -> Double { min(Self.maxBPM, max(Self.minBPM, v)) }

    private func commit(_ v: Double) {
        let c = clamp(v)
        optimistic = c
        onSet(c)
    }

    private func step(_ delta: Double) { commit((shown + delta).rounded()) }

    /// Resolve taps to a BPM locally. Keep only taps within 2 s of each other (a gap
    /// starts a fresh count), average the intervals, and set once we have two taps.
    private func tap() {
        let now = Date()
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2.0 { tapTimes = [] }
        tapTimes.append(now)
        if tapTimes.count > 6 { tapTimes.removeFirst(tapTimes.count - 6) }
        guard tapTimes.count >= 2 else { return }
        var intervals: [TimeInterval] = []
        for i in 1..<tapTimes.count { intervals.append(tapTimes[i].timeIntervalSince(tapTimes[i - 1])) }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        guard avg > 0 else { return }
        commit((60.0 / avg).rounded())
    }

    private func commitDraft() {
        editing = false
        if let v = Double(draft.replacingOccurrences(of: ",", with: ".")) { commit(v) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TEMPO")
                    .font(.ksMono(10)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0x6F8A4D))
                Spacer()
                if linkDriving {
                    Text("LINK IS DRIVING")
                        .font(.ksMono(10)).tracking(1.8)
                        .foregroundStyle(KS.amberText)
                }
            }

            HStack(spacing: 10) {
                stepButton("−") { step(-1) }

                Group {
                    if editing {
                        TextField("", text: $draft)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.ksDisplay(30))
                            .foregroundStyle(KS.ink)
                            .onSubmit(commitDraft)
                            .submitLabel(.done)
                    } else {
                        Text(shown.formatted(.number.precision(.fractionLength(0...1))))
                            .font(.ksDisplay(30))
                            .foregroundStyle(editable ? KS.ink : KS.mut)
                            .onTapGesture {
                                guard editable else { return }
                                draft = shown.formatted(.number.precision(.fractionLength(0...1)))
                                editing = true
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    Text("BPM").font(.ksMono(9)).tracking(1.6)
                        .foregroundStyle(KS.mut).offset(y: 12)
                }

                stepButton("+") { step(1) }

                Button(action: tap) {
                    Text("TAP")
                        .font(.ksDisplay(15)).tracking(1.2)
                        .foregroundStyle(KS.onInk)
                        .frame(width: 66, height: 44)
                        .background(KS.ledFill, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tap tempo")
            }
            .disabled(!editable)   // Link owns the tempo while it's driving
            .opacity(editable ? 1 : 0.5)
        }
        .padding(14)
        .background(KS.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(KS.line))
        // The device caught up (its reported tempo reached our optimistic value, within
        // rounding): drop the optimistic override and follow the device again.
        .onChange(of: tempo) { _, new in
            if let o = optimistic, abs(new - o) < 0.75 { optimistic = nil }
        }
    }

    private func stepButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.ksDisplay(24))
                .foregroundStyle(KS.ink)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [Color(hex: 0x1A1F25), Color(hex: 0x12161B)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(KS.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "−" ? "Tempo down" : "Tempo up")
    }
}
