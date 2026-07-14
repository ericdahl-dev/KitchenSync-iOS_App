import SwiftUI

// The web UI's control vocabulary, ported. Every editable thing on the device's
// page is a `.fld`: a dim prefix label, a hairline divider, then the control.
// One component, ten uses.
//
// See docs/design/2026-07-14-view-layer-design-direction.md §7

/// `.fld` + `.pre`. The prefix sits at `KS.mut`, NOT the web's `#4B535B` —
/// that's ~2.5:1 on the panel and fails AA. Nothing about the look depends on
/// the label being unreadable.
struct KSField<Content: View>: View {
    let prefix: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .font(.ksMono(12))
                .tracking(1.2)
                .foregroundStyle(KS.mut)
                .padding(.trailing, 9)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(KS.line).frame(width: 1).padding(.vertical, 6)
                }
                .padding(.trailing, 11)
                .accessibilityHidden(true)   // the control below carries the label

            content
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(KS.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KS.line))
    }
}

/// `.fld.nudge` + `.stp`. The web's steppers are 46×46; these are 48 (the touch
/// floor). Drag the value horizontally to scrub — a mobile affordance the web
/// page has no answer for.
struct KSStepperField: View {
    let prefix: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 5
    /// Fired on every settled change. The caller decides whether to debounce.
    var onCommit: (Int) -> Void

    @State private var dragAccum: CGFloat = 0

    var body: some View {
        KSField(prefix: prefix) {
            HStack(spacing: 0) {
                stepButton("minus", by: -step)

                Text(value.formatted())
                    .font(.ksMono(15, .medium))
                    .monospacedDigit()
                    .foregroundStyle(KS.ink)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .gesture(scrub)
                    .accessibilityLabel(prefix)
                    .accessibilityValue(value.formatted())
                    .accessibilityAdjustableAction { direction in
                        set(value + (direction == .increment ? step : -step))
                    }

                stepButton("plus", by: step)
            }
        }
    }

    private func stepButton(_ symbol: String, by delta: Int) -> some View {
        Button {
            set(value + delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(KS.ink)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)   // covered by the adjustable action above
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                let delta = g.translation.width - dragAccum
                if abs(delta) >= 6 {
                    set(value + (delta > 0 ? step : -step))
                    dragAccum = g.translation.width
                }
            }
            .onEnded { _ in dragAccum = 0 }
    }

    private func set(_ new: Int) {
        let clamped = min(max(new, range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        value = clamped
        onCommit(clamped)
    }
}

/// `.sw` — the lime track toggle. 52×28 with padding to reach the 44pt tap floor.
struct KSSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(KS.ledFill) : AnyShapeStyle(KS.panel))
                    .overlay(Capsule().strokeBorder(configuration.isOn ? KS.ledEdge : KS.line))
                    .frame(width: 52, height: 28)
                    .shadow(color: configuration.isOn ? KS.led.opacity(0.35) : .clear, radius: 8)

                Circle()
                    .fill(configuration.isOn ? KS.onInk : KS.mut)
                    .frame(width: 20, height: 20)
                    .padding(.horizontal, 4)
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            .padding(8)              // 44pt tap target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// `.pill` / `.pill.on`.
struct KSPill: View {
    let text: String
    var on = false
    var color: Color = KS.mut

    var body: some View {
        Text(text)
            .font(.ksMono(9.5, .medium))
            .tracking(1.4)
            .foregroundStyle(on ? KS.onInk : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                if on {
                    Capsule().fill(KS.ledFill)
                } else {
                    Capsule().strokeBorder(color.opacity(0.6))
                }
            }
    }
}
