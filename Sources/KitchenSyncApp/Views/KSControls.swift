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

/// `.row`, in its DESKTOP form — label stacked over value.
///
/// The web's phone layout flings label and value to opposite edges
/// (`justify-content:space-between`); its desktop rule stacks them. The desktop
/// rule is the right one for a phone: a stacked pair is one glance, a label and a
/// value 300px apart is two.
struct KSStatCell<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.ksMono(10))
                .tracking(1.8)
                .foregroundStyle(KS.mut)
                .accessibilityHidden(true)
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(KS.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KS.line))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.capitalized)
    }
}

/// `.sect` — a 2pt rail with a lime cap. Makes a stack of rows read like a patch bay.
struct KSSectionRail<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                Rectangle().fill(KS.line).frame(width: 2)
                Rectangle().fill(KS.ledDim).frame(width: 2, height: 28)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.ksDisplay(12.5, .semibold))
                    .tracking(1.6)
                    .foregroundStyle(KS.mut)
                content
            }
        }
    }
}

/// A live-editable continuous value.
///
/// Debounced at **60ms** — the firmware's own interval (`ks_web.cpp` debounces
/// number inputs at 60ms before POSTing /live, and the device's /live handler
/// debounce-writes NVS behind that). Dragging a brightness slider would otherwise
/// fire a real HTTP POST per frame.
struct KSLiveSlider: View {
    let label: String
    let range: ClosedRange<Int>
    let value: Int
    let onCommit: (Int) -> Void

    @State private var local: Double?
    @State private var debounce: Task<Void, Never>?

    private var shown: Double { local ?? Double(value) }

    var body: some View {
        KSField(prefix: label) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { shown },
                        set: { new in
                            local = new
                            debounce?.cancel()
                            debounce = Task {
                                try? await Task.sleep(for: .milliseconds(60))
                                guard !Task.isCancelled else { return }
                                onCommit(Int(new.rounded()))
                            }
                        }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 5
                )
                .tint(KS.led)

                Text("\(Int(shown.rounded()))")
                    .font(.ksMono(13, .medium))
                    .monospacedDigit()
                    .foregroundStyle(KS.ink)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        // Let the device win once it has answered — never leave a slider showing a
        // number the device doesn't have.
        .onChange(of: value) { _, new in
            if debounce?.isCancelled ?? true { local = nil }
            _ = new
        }
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
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
