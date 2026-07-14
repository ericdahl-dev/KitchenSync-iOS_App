#!/usr/bin/env swift
//
// Renders the KitchenSync app icon. Source-controlled and re-runnable:
//
//     swift Tools/make_app_icon.swift Sources/KitchenSyncApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// The icon is drawn, not drawn-over: it uses the same palette as the device's own
// web UI (KS.bg / KS.panel / KS.led), because the app was built to look like the
// thing it controls.
//
// WHAT IT IS: a MIDI clock pulse train in lime on charcoal, with one taller ACCENT
// pulse — the downbeat. That is literally what this box emits, and a square wave
// still reads as a square wave at 40px, which "KITCHEN·SYNC" in a display face
// absolutely does not.
//
// iOS rules: full-bleed square, NO alpha, NO rounded corners — the OS masks it.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S = 1024.0

guard let out = CommandLine.arguments.dropFirst().first else {
    FileHandle.standardError.write("usage: make_app_icon.swift <out.png>\n".data(using: .utf8)!)
    exit(2)
}

let space = CGColorSpaceCreateDeviceRGB()
// noneSkipLast = opaque. An app icon with an alpha channel is rejected at submission.
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write("could not create context\n".data(using: .utf8)!)
    exit(1)
}

func rgb(_ hex: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        Double((hex >> 16) & 0xFF) / 255,
        Double((hex >> 8) & 0xFF) / 255,
        Double(hex & 0xFF) / 255, a,
    ])!
}

// ---- the panel ---------------------------------------------------------------
// KS.panel -> KS.bg, top to bottom. The same brushed-dark unit the web UI renders.
let bg = CGGradient(colorsSpace: space,
                    colors: [rgb(0x161B21), rgb(0x0B0E11), rgb(0x070809)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// A lime glow behind the wave — the LED bleeding into the panel. Sells the "this
// thing is powered and running" feeling that the hardware's own LED gives you.
let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(0xB6FF36, 0.16), rgb(0xB6FF36, 0.0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: S / 2, y: S * 0.5), startRadius: 0,
                       endCenter: CGPoint(x: S / 2, y: S * 0.5), endRadius: S * 0.52,
                       options: [])

// ---- the pulse train ---------------------------------------------------------
// Four beats. Beat one is the ACCENT and rises higher, exactly like the accent LED
// and the metronome's accented downbeat. Asymmetry is what stops this reading as a
// generic waveform: it has a downbeat, so it has a bar, so it is a CLOCK.

// Proportions matter more than the idea here. The first cut used a 59px stroke on an
// 86px pulse: the gaps filled in and the whole thing read as a lime blob. A pulse
// train is only legible if the GAPS survive, so the line stays thin relative to the
// duty cycle, and there are THREE beats, not four — fewer, bigger, clearer.

let lo = S * 0.335          // the low rail
let hi = S * 0.600          // a normal pulse
let hiAccent = S * 0.700    // the downbeat, one step prouder
let left = S * 0.115
let right = S - left
let beats = 3.0
let period = (right - left) / beats
let pulseWidth = period * 0.50
let gap = period - pulseWidth

let stroke = S * 0.042
let path = CGMutablePath()
// Start and end on the LOW rail with equal tails. The first cut began on a rising
// edge and ended with a long flat run, which pulled the whole mark left.
path.move(to: CGPoint(x: left, y: lo))
for beat in 0 ..< Int(beats) {
    let x0 = left + gap / 2 + Double(beat) * period
    let top = beat == 0 ? hiAccent : hi
    path.addLine(to: CGPoint(x: x0, y: lo))
    path.addLine(to: CGPoint(x: x0, y: top))            // rising edge
    path.addLine(to: CGPoint(x: x0 + pulseWidth, y: top))
    path.addLine(to: CGPoint(x: x0 + pulseWidth, y: lo)) // falling edge
}
path.addLine(to: CGPoint(x: right, y: lo))

// SHARP corners. Round joins turned this into a bent pipe; a clock edge is square,
// and squaring the joins is the whole difference between "waveform" and "maze".
ctx.setLineCap(.butt)
ctx.setLineJoin(.miter)
ctx.setMiterLimit(10)

// The mark should look EMITTED, not printed — so it needs a real glow.
//
// Two dead ends first, both worth naming: ONE wide translucent stroke has a hard
// outer edge and reads as a dark-green BORDER around the wave. STACKING several
// translucent strokes just turns that one hard edge into a set of them — visible
// concentric banding, a contour map. Neither is a glow, because a glow FALLS OFF and
// a stroke does not.
//
// A shadow does. Zero offset + a blur radius + the LED colour is a real Gaussian
// bloom around the path. Two passes, because one is too timid to see on charcoal.
for (blur, alpha) in [(S * 0.075, 0.75), (S * 0.030, 0.85)] as [(Double, Double)] {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: rgb(0x9BE32A, alpha))
    ctx.setStrokeColor(rgb(0xB6FF36))
    ctx.setLineWidth(stroke)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()
}

// The filament itself, crisp and unshadowed, over its own bloom.
ctx.setStrokeColor(rgb(0xE4FFA8))
ctx.setLineWidth(stroke)
ctx.addPath(path)
ctx.strokePath()

// ---- write -------------------------------------------------------------------
guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: out)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(out)")
