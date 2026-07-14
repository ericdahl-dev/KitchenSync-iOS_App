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
    @State private var showingSettings = false
    @State private var showingFirmware = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .disabled(vm.config == nil)

                    // NEVER gated behind a successful config fetch. On old firmware
                    // /config.json 404s (T-009) — and a firmware update is the way OUT
                    // of that state, so locking it away behind the very thing that's
                    // broken would strand the user.
                    Button {
                        showingFirmware = true
                    } label: {
                        Label("Update firmware", systemImage: "arrow.up.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Device actions")
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let config = vm.config {
                DeviceSettingsSheet(deviceName: device.displayName, config: config) { draft, wifiEdits in
                    Task { await vm.save(draft, wifiEdits: wifiEdits) }
                }
            }
        }
        .sheet(isPresented: $showingFirmware) {
            FirmwareUpdateSheet(deviceName: device.displayName) { binary in
                await vm.uploadFirmware(binary)
            }
        }
        .overlay { if vm.isRebooting { rebootingOverlay } }
        .task {
            vm.start()
            await vm.loadConfig()
        }
        .onDisappear { vm.stop() }
    }

    /// An EXPECTED disappearance, not an error. The device is restarting because we
    /// asked it to. The poll loop keeps running; the instant `/status` answers, this
    /// clears itself — the device coming back is the signal, so no timer, no guess.
    private var rebootingOverlay: some View {
        ZStack {
            KS.bg.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(KS.amber)
                Text("REBOOTING…")
                    .font(.ksDisplay(15))
                    .tracking(2)
                    .foregroundStyle(KS.amberText)
                Text("The device is restarting and will rejoin the Link session shortly.")
                    .font(.ksMono(12))
                    .foregroundStyle(KS.mut)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rebooting. The device is restarting.")
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

    /// Why the settings aren't here — attributed from the actual failure, not guessed
    /// from whether `/status` happens to be answering.
    ///
    /// A `/config.json` 404 (firmware older than 2026-07-14) and a dead network are
    /// different problems with different fixes, and blaming the wrong one sends the
    /// user off to reflash a device that was fine — or to debug a network that was.
    ///
    /// Note what is deliberately NOT offered here: a "save anyway" form. Without the
    /// read there is no read-modify-write, so a full `/save` built from fabricated
    /// defaults would clobber settings we were never able to see. The honest move is
    /// to disable it and say why. The way OUT of the old-firmware state is an OTA
    /// update (T-008), which is why that path must never be gated behind a successful
    /// config fetch.
    @ViewBuilder
    private var configUnavailable: some View {
        KSSectionRail(title: "SETTINGS") {
            switch vm.configAvailability {
            case .unsupportedByFirmware:
                Text("This device's firmware is older than 2026-07-14 and has no /config.json, so its settings can't be read — and therefore can't be safely changed. Status, transport and live edits still work. Update the firmware to enable settings.")
                    .font(.ksMono(12))
                    .foregroundStyle(KS.mut)
                KSPill(text: "OLD FIRMWARE", color: KS.amber)

            case .failed:
                Text("Couldn't read this device's settings. It answered, but not with a config.")
                    .font(.ksMono(12))
                    .foregroundStyle(KS.mut)

            case .unknown, .available:
                // .available with no config shouldn't happen; .unknown means the fetch
                // hasn't finished. Neither is a firmware problem, so don't say it is.
                Text(vm.status == nil
                     ? "This device isn't answering. Check that your phone is on the same network."
                     : "Reading settings…")
                    .font(.ksMono(12))
                    .foregroundStyle(KS.mut)
            }
        }
    }

    // MARK: Diagnostics

    private var diagnostics: some View {
        KSSectionRail(title: "DIAGNOSTICS") {
            DisclosureGroup {
                VStack(spacing: 6) {
                    if let t = vm.status?.tickHealth {
                        // These are LIFETIME totals — the firmware says so. A non-zero value means
                        // "this happened at some point", usually at boot, and colouring it amber
                        // forever is how a real, healthy device ends up permanently flagged. The
                        // number is still worth SHOWING; it just isn't an alarm. Only a counter
                        // that is MOVING right now warns (see `hasDiagWarning`).
                        DiagRow("dropped ticks", "\(t.droppedTicks) since boot",
                                warn: vm.clockFault == .droppingNow)
                        DiagRow("bursts", "\(t.bursts)")
                        DiagRow("max gap µs", "\(t.maxGapMicros)")
                        DiagRow("max work µs", "\(t.maxWorkMicros)")
                        DiagRow("overruns", "\(t.overruns) since boot",
                                warn: vm.clockFault == .droppingNow)

                        if vm.clockFault == .droppingNow {
                            Text("The clock task is dropping ticks RIGHT NOW.")
                                .font(.ksMono(11))
                                .foregroundStyle(KS.amberText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
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

    /// A RATE, not a lifetime total.
    ///
    /// This used to be `droppedTicks > 0`. But those are LIFETIME counters, so a real device that
    /// dropped 47 ticks at boot and has been flawless since lit an amber warning **forever** — and
    /// a warning that is always on is one nobody reads, which makes it worthless on the day it
    /// matters. Only a counter that MOVES between polls is news. See `ClockFault`.
    private var hasDiagWarning: Bool {
        vm.clockFault == .droppingNow
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
