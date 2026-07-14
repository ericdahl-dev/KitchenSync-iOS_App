import SwiftUI

// Design tokens ported from the device's own web UI — the palette lives in
// `link-devices/X32Link/ui_chrome.c` (which `ks_web.cpp` includes as `%CSS%`),
// NOT in ks_web.cpp. Eight colors, three faces.
//
// See docs/design/2026-07-14-view-layer-design-direction.md

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }

    /// A color that differs by appearance. Done with a dynamic `UIColor` rather
    /// than an asset catalog so the hex values stay next to the CSS they came from.
    static func ks(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

enum KS {
    // MARK: Chrome — adapts to light/dark.

    static let bg    = Color.ks(dark: 0x070809, light: 0xF4F5F2)
    static let panel = Color.ks(dark: 0x0F1216, light: 0xFFFFFF)
    static let line  = Color.ks(dark: 0x262B31, light: 0xDDE0DA)
    static let ink   = Color.ks(dark: 0xE9ECE6, light: 0x14171A)
    /// The web's `--mut` (#838D95). Also replaces `.pre` (#4B535B, ~2.5:1 — fails AA).
    static let mut   = Color.ks(dark: 0x838D95, light: 0x6B7379)

    // MARK: Instrument — FIXED in both appearances.
    //
    // These depict hardware. Hardware doesn't invert: a lime LED is lime on a
    // white bench too. Only the *text* variants below adapt, because #B6FF36 on
    // white is 1.4:1 and would be unreadable.

    static let led     = Color(hex: 0xB6FF36)
    static let ledDim  = Color(hex: 0x36431A)
    static let ledEdge = Color(hex: 0x7FBF1F)
    /// Text drawn ON lime.
    static let onInk   = Color(hex: 0x0A0D07)
    static let amber   = Color(hex: 0xFF9D3B)
    /// The stopped label — salmon, not grey.
    static let ember   = Color(hex: 0xFF7A6B)

    static let ledFill   = LinearGradient(colors: [Color(hex: 0xCAFF5A), Color(hex: 0x9BE32A)],
                                          startPoint: .top, endPoint: .bottom)
    static let emberFill = LinearGradient(colors: [Color(hex: 0x2A1512), Color(hex: 0x1C0F0D)],
                                          startPoint: .top, endPoint: .bottom)
    static let amberFill = LinearGradient(colors: [Color(hex: 0x2C2113), Color(hex: 0x1D160D)],
                                          startPoint: .top, endPoint: .bottom)
    static let panelFill = LinearGradient(colors: [Color(hex: 0x191D22), Color(hex: 0x101317)],
                                          startPoint: .top, endPoint: .bottom)

    /// The firmware's own "this is a consequence" wash — `@keyframes nakrow`,
    /// `rgba(224,168,58,.14)`. Used for the rejected tap and the reboot band.
    static let consequence = Color(hex: 0xE0A83A).opacity(0.14)

    // MARK: Text variants — AA-safe in light mode.

    static let ledText   = Color.ks(dark: 0xB6FF36, light: 0x4F7A0E)
    static let amberText = Color.ks(dark: 0xFF9D3B, light: 0x9A5A00)
}

// MARK: - Type
//
// The web uses Bricolage Grotesque (display), DM Mono (values), DSEG7 Classic
// (the BPM readout). All three are SIL OFL 1.1 and SHOULD be bundled to keep
// the identity 1:1. They are not bundled yet — these are the documented
// fallbacks. Note the design direction's rule: if DSEG7 is absent, the tempo
// glass must DROP its ghost layer, because a grey duplicate of a non-segmented
// font reads as a rendering bug rather than unlit segments.

extension Font {
    /// Display face — wordmark, section heads, transport labels.
    static func ksDisplay(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Mono — every value, every field, every pill.
    static func ksMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
