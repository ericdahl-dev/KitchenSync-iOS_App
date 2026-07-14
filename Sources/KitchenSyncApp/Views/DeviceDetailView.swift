import SwiftUI

/// One device — the instrument.
///
/// **Everything on this screen is live.** Every control routes through a
/// `KsLiveEdit` case, which means this screen structurally cannot reboot the
/// device. The three reboot-required settings (WiFi, metronome ENABLE, follow-beat
/// ENABLE) have no case in the enum and live behind the settings sheet (T-007).
///
/// The trap this design exists to kill: on the device's own web page, the metronome
/// ENABLE toggle and the metro-accent toggle are the identical component, forty
/// pixels apart, in the same box — and one of them reboots the device mid-set. Here
/// the enable is not a control at all; it's a read-only status row.
struct DeviceDetailView: View {
    let device: KitchenSyncDevice

    @StateObject private var vm: DeviceDetailViewModel

    init(device: KitchenSyncDevice) {
        self.device = device
        _vm = StateObject(wrappedValue: DeviceDetailViewModel(
            client: KitchenSyncClient(host: device.host)
        ))
    }

    private var bpm: Double { vm.status?.bpm ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                tempo
                meterBridge
                masterTransport

                if let config = vm.config {
                    clockOutSection(config)
                    metronomeSection(config)
                    ledSection(config)
                } else {
                    configUnavailable
                }

                diagnostics
            }
            .padding()
        }
        .background(KS.bg.ignoresSafeArea())
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.start()
            await vm.loadConfig()
        }
        .onDisappear { vm.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            KSPowerLED(alive: vm.status != nil)

            HStack(spacing: 0) {
                Text("KITCHEN·").foregroundStyle(KS.ink)
                Text("SYNC").foregroundStyle(KS.ledText)
            }
            .font(.ksDisplay(20))
            .tracking(1.2)

            Spacer()

            Text(vm.status.map { "FW \($0.firmwareVersion)" } ?? "OFFLINE")
                .font(.ksMono(10.5))
                .tracking(1.8)
                .foregroundStyle(KS.mut)
        }
    }

    // MARK: Tempo

    private var tempo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BeatDot(bpm: bpm, running: vm.status != nil)
                Text("SESSION TEMPO")
                    .font(.ksMono(10))
                    .tracking(1.8)
                    .foregroundStyle(Color(hex: 0x6F8A4D))
                Spacer()
                Text(sourceLabel)
                    .font(.ksMono(10))
                    .tracking(1.8)
                    .foregroundStyle(KS.amberText)
            }

            KSGlass(bpm: bpm, size: 58)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The web page hardcodes "Ableton Link". `KsStatus` knows better.
    private var sourceLabel: String {
        guard let s = vm.status else { return "—" }
        switch s.tempoSource {
        case .link:        return "ABLETON LINK"
        case .midiClockIn: return "MIDI CLOCK IN"
        case .followBeat:  return "FOLLOW BEAT"
        }
    }

    // MARK: Meter bridge

    private var meterBridge: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            KSStatCell(label: "LINK PEERS") {
                Text(vm.status.map { "\($0.peers)" } ?? "—")
                    .font(.ksMono(15, .medium)).monospacedDigit().foregroundStyle(KS.ink)
            }
            KSStatCell(label: "USB-MIDI") {
                KSPill(text: (vm.status?.usbConnected ?? false) ? "CONNECTED" : "ABSENT",
                       on: vm.status?.usbConnected ?? false)
            }
            KSStatCell(label: "MIDI CLOCK IN") {
                Text(vm.status.map { $0.midiClockInBPM > 0 ? String(format: "%.1f BPM", $0.midiClockInBPM) : "none" } ?? "—")
                    .font(.ksMono(13)).foregroundStyle(KS.ink)
            }
            KSStatCell(label: "FOLLOW BEAT") {
                Text(vm.status?.followBeatSummary ?? "—")
                    .font(.ksMono(13)).foregroundStyle(KS.ink)
            }
            KSStatCell(label: "TRANSPORT") {
                Text(summaryText)
                    .font(.ksMono(13)).foregroundStyle(KS.ink)
            }
            KSStatCell(label: "CLOCK PULSES") {
                Text(vm.status.map { "\($0.clockPulseCount)" } ?? "—")
                    .font(.ksMono(13)).monospacedDigit().foregroundStyle(KS.ink)
            }
        }
    }

    private var summaryText: String {
        switch vm.status?.transportSummary {
        case .playing: return "playing"
        case .arming:  return "arming"
        case .stopped: return "stopped"
        case nil:      return "—"
        }
    }

    // MARK: Master transport
    //
    // Two buttons, not one toggle. A single toggle whose state is a DERIVED summary
    // shows the wrong thing during a mixed arming/playing moment — and it shows it
    // on stage. Play is quantized here too; Stop is immediate and always safe.

    private var masterTransport: some View {
        HStack(spacing: 10) {
            MasterButton(title: "PLAY", face: playFace, blinks: vm.status?.transportSummary == .arming, bpm: bpm) {
                Task { await vm.transport(output: nil, play: true) }
            }
            MasterButton(title: "STOP", face: .ember, blinks: false, bpm: bpm) {
                Task { await vm.transport(output: nil, play: false) }
            }
        }
        // A full-brightness lime PLAY on a device that isn't answering invites a tap
        // that can't land. Dim it to match its actual reachability.
        .opacity(vm.status == nil ? 0.35 : 1)
        .disabled(vm.status == nil)
    }

    private var playFace: TransportFace {
        switch vm.status?.transportSummary {
        case .playing: return .lime
        case .arming:  return .amber
        default:       return .lime
        }
    }

    // MARK: Live sections

    private func clockOutSection(_ config: KsConfig) -> some View {
        KSSectionRail(title: "MIDI CLOCK OUT") {
            HStack {
                Text("master enable").font(.ksMono(12)).foregroundStyle(KS.mut)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.clockOutEnabled },
                    set: { v in Task { await vm.apply(.clockOutEnabled(v)) } }
                ))
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()
                .accessibilityLabel("Master clock out enable")
            }

            ForEach(Array(config.clock.enumerated()), id: \.offset) { i, out in
                OutputCardView(
                    index: i,
                    config: out,
                    launch: vm.status?.launch.indices.contains(i) == true ? vm.status!.launch[i] : .stopped,
                    bpm: bpm,
                    linkOwnsTransport: vm.status?.linkOwnsTransport ?? false,
                    onEdit: { edit in Task { await vm.apply(edit) } },
                    onTransport: { play in Task { await vm.transport(output: i, play: play) } }
                )
            }
        }
    }

    private func metronomeSection(_ config: KsConfig) -> some View {
        KSSectionRail(title: "METRONOME") {
            // NOT a toggle. `metronome` enable has no KsLiveEdit case — it requires a
            // full /save, which REBOOTS the device. It is deliberately unreachable
            // from this screen. (T-007 gives it a home behind a warning.)
            RebootOnlyRow(label: "enable", value: config.metronomeEnabled ? "ON" : "OFF")

            HStack {
                Text("accent").font(.ksMono(12)).foregroundStyle(KS.mut)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.metronomeAccent },
                    set: { v in Task { await vm.apply(.metronomeAccent(v)) } }
                ))
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()
                .accessibilityLabel("Metronome accent")
            }

            KSLiveSlider(label: "VOL", range: 0...100, value: config.metronomeVolume) { v in
                Task { await vm.apply(.metronomeVolume(v)) }
            }

            KSField(prefix: "VOICE") {
                Picker("Voice", selection: Binding(
                    get: { config.metronomeVoice },
                    set: { v in Task { await vm.apply(.metronomeVoice(v)) } }
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

    private func ledSection(_ config: KsConfig) -> some View {
        KSSectionRail(title: "LED STRIP · VISUAL METRONOME") {
            HStack {
                Text("enable").font(.ksMono(12)).foregroundStyle(KS.mut)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.ledEnabled },
                    set: { v in Task { await vm.apply(.ledEnabled(v)) } }
                ))
                .toggleStyle(KSSwitchStyle())
                .labelsHidden()
                .accessibilityLabel("LED enable")
            }

            KSLiveSlider(label: "BRIGHT", range: 0...100, value: config.ledBrightness) { v in
                Task { await vm.apply(.ledBrightness(v)) }
            }
            KSLiveSlider(label: "FADE", range: 0...100, value: config.ledFade) { v in
                Task { await vm.apply(.ledFade(v)) }
            }

            KSField(prefix: "MODE") {
                Picker("Mode", selection: Binding(
                    get: { config.ledMode },
                    set: { v in Task { await vm.apply(.ledMode(v)) } }
                )) {
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
                    get: { Color(hex: config.ledBeatColor) },
                    set: { c in Task { await vm.apply(.ledBeatColor(c.rgb24)) } }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            KSField(prefix: "ACCENT") {
                ColorPicker("Accent colour", selection: Binding(
                    get: { Color(hex: config.ledAccentColor) },
                    set: { c in Task { await vm.apply(.ledAccentColor(c.rgb24)) } }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// Two very different reasons the config can be missing, and they must not be
    /// conflated: the device isn't answering AT ALL, or it answered but has no
    /// `/config.json` (firmware older than 2026-07-14 404s on it, while every other
    /// route still works). Blaming old firmware for what is really a dead network
    /// sends the user off to flash a device that was fine.
    ///
    /// Telling the two apart properly — typing the 404 distinctly from a transport
    /// failure — is T-009. Until then, lean on whether /status is answering.
    private var configUnavailable: some View {
        KSSectionRail(title: "SETTINGS") {
            Text(vm.status == nil
                 ? "This device isn't answering. Check that your phone is on the same network."
                 : "This device answered but returned no settings. Firmware older than 2026-07-14 has no /config.json — status and transport still work.")
                .font(.ksMono(12))
                .foregroundStyle(KS.mut)
        }
    }

    // MARK: Diagnostics

    private var diagnostics: some View {
        KSSectionRail(title: "DIAGNOSTICS") {
            DisclosureGroup {
                VStack(spacing: 6) {
                    if let t = vm.status?.tickHealth {
                        DiagRow("dropped ticks", "\(t.droppedTicks)", warn: t.droppedTicks > 0)
                        DiagRow("bursts", "\(t.bursts)")
                        DiagRow("max gap µs", "\(t.maxGapMicros)")
                        DiagRow("max work µs", "\(t.maxWorkMicros)")
                        DiagRow("overruns", "\(t.overruns)", warn: t.overruns > 0)
                    }
                    if let p = vm.status?.phaseHealth {
                        // maxStepMicros is the number that, unread, cost 138 seconds of
                        // silent DIN clock in ESP-027. It SHOULD carry a warning
                        // threshold — but nobody has told us what that threshold is, and
                        // inventing one would be worse than showing the raw number.
                        DiagRow("max origin step µs", "\(p.maxStepMicros)")
                        DiagRow("rtt min/max µs", "\(p.rttMinMicros)/\(p.rttMaxMicros)")
                    }
                    if vm.status?.tickHealth == nil && vm.status?.phaseHealth == nil {
                        Text("not measured")
                            .font(.ksMono(12))
                            .foregroundStyle(KS.mut)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Text("tick / phase health")
                        .font(.ksMono(12))
                        .foregroundStyle(KS.mut)
                    if hasDiagWarning {
                        Circle().fill(KS.amber).frame(width: 6, height: 6)
                    }
                }
            }
            .tint(KS.mut)
        }
    }

    /// Only unambiguous signals. A dropped tick or an overrun is a fault by
    /// definition — no threshold needed, and none invented.
    private var hasDiagWarning: Bool {
        guard let t = vm.status?.tickHealth else { return false }
        return t.droppedTicks > 0 || t.overruns > 0
    }
}

// MARK: - Pieces

/// A setting that CANNOT be changed from this screen because changing it reboots
/// the device. Rendered as a value, not a control — you cannot fat-finger a
/// read-only row into restarting a box mid-set.
private struct RebootOnlyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.ksMono(12)).foregroundStyle(KS.mut)
            Spacer()
            Text(value)
                .font(.ksMono(13, .medium))
                .foregroundStyle(KS.ink)
            KSPill(text: "REBOOTS", color: KS.amber)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). Changing this reboots the device; it lives in settings.")
    }
}

private struct DiagRow: View {
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

/// The beat dot — ~90ms lit, once per beat, at `60/bpm`. The firmware's own cadence.
private struct BeatDot: View {
    let bpm: Double
    let running: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running || bpm <= 0 || reduceMotion)) { ctx in
            let period = 60.0 / max(bpm, 40)
            let phase = ctx.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            let lit = running && bpm > 0 && phase < 0.15
            Circle()
                .fill(lit ? KS.led : KS.ledDim)
                .frame(width: 8, height: 8)
                .shadow(color: lit ? KS.led.opacity(0.8) : .clear, radius: 5)
        }
        .accessibilityHidden(true)
    }
}

/// Master PLAY / STOP. ≥56pt — the web's are ~26pt, which is unusable.
private struct MasterButton: View {
    let title: String
    let face: TransportFace
    let blinks: Bool
    let bpm: Double
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !blinks || reduceMotion)) { ctx in
                let period = 60.0 / max(bpm, 40)
                let phase = ctx.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                let lit = !blinks || reduceMotion || phase < 0.35

                Text(title)
                    .font(.ksDisplay(16))
                    .tracking(2)
                    .foregroundStyle(face == .lime ? KS.onInk : KS.ember)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(face == .lime ? KS.ledFill : KS.emberFill,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(face == .lime ? KS.ledEdge : KS.line)
                    )
                    .opacity(lit ? 1 : 0.45)
            }
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    /// Back to the firmware's `0xRRGGBB`.
    var rgb24: UInt32 {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (v: CGFloat) -> UInt32 in UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (clamp(r) << 16) | (clamp(g) << 8) | clamp(b)
    }
}
