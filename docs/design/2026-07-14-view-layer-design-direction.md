# KitchenSync iOS — Design Direction for the View Layer

**Date:** 2026-07-14
**Scope:** T-003 through T-008 (the entire view layer)
**Method:** Derived by reading the device's own web UI in `link-devices`, not invented.

## Sources read

- `link-devices/KitchenSync/main/ks_web.cpp` — the page, its page-specific CSS/JS
- `link-devices/X32Link/ui_chrome.c` — the shared chrome CSS/JS that `ks_web.cpp` includes as
  `%CSS%`/`%JS%`. **This is where the real palette lives** — not in `ks_web.cpp`.
- `Sources/KitchenSyncApp/Models/*.swift`, `Networking/KitchenSyncClient.swift`,
  `ViewModels/DeviceListViewModel.swift`, `tasks/T-003.md`–`T-008.md`

---

## 0. What the web UI actually is

The device's page is not a generic firmware config form. It is a deliberate, coherent instrument
panel, and it is better than it needs to be. But it has four real failures, and three of them are
exactly the things this app exists to fix.

**The whole palette, verbatim** (`ui_chrome.c:26-28`):

```css
:root{--bg:#070809;--panel-2:#0f1216;--ink:#e9ece6;--mut:#838d95;--line:#262b31;
--led:#b6ff36;--led-dim:#36431a;--amber:#ff9d3b;
--mono:'DM Mono',...;--disp:'Bricolage Grotesque',...;--seg:'DSEG7 Classic',...}
```

Eight colors, three faces. Near-black background, one lime LED, one amber, one warm off-white
ink, one grey. Everything else in both files is a tint of those.

### The signature moves, in order of how much they matter

**1. The tempo glass.** A 7-segment readout with an unlit-segment ghost behind it:

```css
.readout .ghost{position:absolute;inset:4px 0 2px;color:#1a2113}
.readout .live{position:relative;color:var(--led);text-shadow:0 0 14px rgba(182,255,54,.45)}
.bignum{font-size:58px}
```

with `<span class="ghost bignum">188.8</span>` behind the live BPM. That "188.8" is the
all-segments-lit ghost of a real LED display. It's one `ZStack` and it is the soul of the design.

**2. The prefix-label field** (`ui_chrome.c:58-60`):

```css
.fld{display:flex;align-items:center;background:var(--panel-2);border:1px solid var(--line);border-radius:9px;padding:0 12px}
.fld .pre{color:#4b535b;font-size:12px;letter-spacing:.1em;padding-right:9px;border-right:1px solid var(--line);margin-right:11px}
.fld:focus-within{border-color:#4a5a2c;box-shadow:0 0 0 3px rgba(182,255,54,.08)}
```

Every editable thing is this: `CABLE | [USB A ▾]`, `NUDGE | − 0 +`, `SSID | […]`. One component,
ten uses. Port it.

**3. The physical write key** (`ui_chrome.c:71-72`, `ks_web.cpp:137`):

```css
.write{...background:linear-gradient(180deg,#d2ff63,#9be32a);box-shadow:0 6px 0 #5e8a16,0 16px 30px -12px rgba(182,255,54,.5)}
.write:active{transform:translateY(4px);box-shadow:0 1px 0 #5e8a16}
```

A key with 6px of travel that bottoms out when you press it. Labelled **Write & Reboot**.

**4. The transport toggle** (`ks_web.cpp:107-113`) — one control, three states, state *is* the
label and the color:

```css
.tgl{...border:1px solid var(--line);background:linear-gradient(180deg,#2a1512,#1c0f0d);color:#ff7a6b;transition:background .15s,color .15s,border-color .15s}
.tgl.arming{border-color:var(--amber);color:var(--amber);background:linear-gradient(180deg,#2c2113,#1d160d)}
.tgl.playing{border-color:#7fbf1f;color:#0a0d07;background:linear-gradient(180deg,#caff5a,#9be32a)}
.tgl:disabled{opacity:.45;cursor:not-allowed}
```

**Stopped is not neutral grey — it's an ember**: dark maroon `#2A1512 → #1C0F0D` with salmon
`#FF7A6B` text. That's a good decision. It reads "loaded, not firing," and it distinguishes
stopped from disabled (which is just `opacity:.45`).

### The four failures

- **The armed state does not blink.** `.tgl.arming` is a *static* amber with a 150ms color
  transition. The one interaction where the web UI most needed motion, it has none. T-003 is
  right to demand a blink.
- **Live vs. reboot is completely invisible.** The distinction exists — it's the `class="live"`
  attribute on `ks_web.cpp:193,199,202-203,206`, on the clock-out fields in `build_outputs()`,
  and on everything in `build_led()`. It is *a CSS class the user cannot see*. The metronome
  group is the trap made flesh: the `metronome` enable toggle (`ks_web.cpp:196`, no `.live`) and
  the `metro_accent` toggle (`ks_web.cpp:199`, `class="live"`) are **the identical `.sw`
  component, forty pixels apart, in the same box**. One applies instantly. The other reboots the
  device. Nothing on screen says so. **This is the single most important thing the iOS app fixes.**
- **Contrast failures.** `.pre` at `#4B535B` on `#0F1216` is ~2.5:1. `.foot` at `#3C444C` on
  `#070809` is ~2:1. Both are 12px and 10.5px body text. Do not copy those values.
- **Dark-only.** No `prefers-color-scheme` anywhere; the only media query is
  `prefers-reduced-motion` (`ui_chrome.c:75`) — which, credit where due, it does honor.

---

## 1. Palette and typography in SwiftUI

Two token families, and the split is load-bearing: **fills keep the device's colors in both
modes; text colors adapt.** `#B6FF36` on white is 1.4:1 — shipping it as a text color is how this
app gets an unreadable light mode.

```swift
enum KS {
    // Chrome — adapts. Asset catalog, Any/Dark appearance.
    static let bg     = Color("ks.bg")      // #070809 / #F4F5F2
    static let panel  = Color("ks.panel")   // #0F1216 / #FFFFFF
    static let line   = Color("ks.line")    // #262B31 / #DDE0DA
    static let ink    = Color("ks.ink")     // #E9ECE6 / #14171A
    static let mut    = Color("ks.mut")     // #838D95 / #6B7379

    // Instrument — fixed. These depict hardware; hardware doesn't invert.
    static let led       = Color(hex: 0xB6FF36)
    static let ledDim    = Color(hex: 0x36431A)
    static let ledOn     = LinearGradient([0xCAFF5A, 0x9BE32A], .top, .bottom)
    static let ledEdge   = Color(hex: 0x7FBF1F)
    static let onInk     = Color(hex: 0x0A0D07)   // text ON lime
    static let amber     = Color(hex: 0xFF9D3B)
    static let ember     = Color(hex: 0xFF7A6B)   // stopped label
    static let emberFill = LinearGradient([0x2A1512, 0x1C0F0D], .top, .bottom)
    static let amberFill = LinearGradient([0x2C2113, 0x1D160D], .top, .bottom)
    static let consequence = Color(hex: 0xE0A83A).opacity(0.14) // firmware's own `nakrow` wash

    // Semantic text variants — AA-safe in light mode.
    static let ledText   = Color("ks.led.text")   // #B6FF36 / #4F7A0E
    static let amberText = Color("ks.amber.text") // #FF9D3B / #9A5A00
}
```

**Depart on `.pre`:** the field prefix label moves from `#4B535B` to `KS.mut` (~2.5:1 → ~5.1:1).
Nothing about the look is lost; the labels just stop being decorative.

**Default to dark.** `.preferredColorScheme(.dark)` at the `App` level, with a "Follow System"
opt-out. The device is dark, the reference UI is dark, and the room is dark. Light mode exists so
the app isn't broken on a bright bench at 2pm — not because it's the default. A performer's phone
at full brightness in light mode is a flashlight pointed at the audience.

### Typography

All three faces are SIL OFL 1.1; bundle them and keep the identity 1:1.

| Role | Web | iOS | Used for |
|---|---|---|---|
| Display | Bricolage Grotesque 600/800 | bundle; fallback `.system(weight: .heavy).fontWidth(.condensed)` | wordmark, section heads (12.5pt/.12em), transport labels (17pt/.14em), WRITE & REBOOT (16pt/.14em), ± steppers (24pt) |
| Mono | DM Mono 400/500 | bundle; fallback `.system(design: .monospaced)` | every value, every field, every pill |
| Segment | DSEG7 Classic | bundle — **required** for the ghost trick | the BPM readout only |

If DSEG7 can't be bundled, fall back to DM Mono heavy and **delete the ghost layer**. A grey
duplicate of a non-segmented font doesn't read as unlit segments; it reads as a rendering bug.

Two non-negotiables: **`.monospacedDigit()` on every number** (a 3-digit BPM must not reflow a
row), and **a sentence-case `.accessibilityLabel` on every uppercase `.18em`-tracked
micro-label** — VoiceOver reads tracked-out caps badly. Cap those labels at
`.dynamicTypeSize(...DynamicTypeSize.accessibility1)` while values scale freely.

---

## 2. `TransportButton` (T-003) — the one control that matters

The appearance mapping is pulled out as a pure function because T-003 asks for tests over the
state→appearance mapping, and you cannot usefully assert on a gradient:

```swift
struct TransportAppearance: Equatable {
    var label: String            // "STOPPED" / "ARMING" / "PLAYING" — the firmware's own words
    var fill: Fill               // .ember / .amber / .lime
    var stroke: Color
    var foreground: Color
    var blinks: Bool
    var isEnabled: Bool

    static func appearance(for state: TransportLaunchState,
                           linkOwned: Bool) -> TransportAppearance
}

struct TransportButton: View {
    let state: TransportLaunchState   // straight from /status.launch[N] — never local
    let bpm: Double
    let linkOwned: Bool
    let onTap: (Bool) -> Void         // caller passes TransportTapIntent.play(for: state)
}
```

**Geometry.** Full card width, **minimum 64pt tall** (the web's `.tgl` is ~40pt — below the 44pt
floor, and this is the control you hit under pressure with a monitor wedge in your face).
`RoundedRectangle(cornerRadius: 14, style: .continuous)`, `.contentShape` on the full rect. Label
in display 800 at 17pt, `.tracking(2)`, uppercase.

**The three states, ported literally:**

- `.stopped` — `KS.emberFill`, 1pt `KS.line` stroke, `KS.ember` label. Keep the ember. Grey would
  be the obvious choice and it's the wrong one: grey is what *disabled* looks like, and a stopped
  output is the opposite of disabled — it's cocked.
- `.armed` — `KS.amberFill`, **1.5pt** `KS.amber` stroke, `KS.amber` label, **and it blinks.**
- `.running` — `KS.ledOn`, `KS.ledEdge` stroke, `KS.onInk` label, plus
  `.shadow(color: KS.led.opacity(0.45), radius: 18)`. That glow is the tempo glass's
  `text-shadow:0 0 14px rgba(182,255,54,.45)`, promoted to the button. Visible across a stage.

### The blink

This is the whole task. Play is quantized: the tap posts an intent, the device arms, and the bar
line may be most of a bar away. The blink is the *only* evidence the tap registered.

**Blink at the beat, not at some arbitrary UI rate.** The firmware already established the
cadence — `ui_chrome.c:86-90`:

```js
function flashBeat(){beatEl.classList.add('on');setTimeout(function(){beatEl.classList.remove('on')},90)}
function setBeat(bpm){...if(bpm>0){beatTimer=setInterval(flashBeat,60000/bpm)}}
```

A short hard flash, once per beat, period `60000/bpm`. Reuse it for the armed state and the
button pulses **in time with the music**. It tells you the bar line is coming, it's legible from
across a room, and it's already the house style.

```swift
TimelineView(.animation(minimumInterval: 1.0/30.0, paused: !appearance.blinks || reduceMotion)) { ctx in
    let period = 60.0 / max(bpm, 40)
    let phase  = ctx.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
    let lit    = phase < 0.35                       // hard-edged, ~35% duty
    face.opacity(lit ? 1.0 : 0.42)
        .shadow(color: KS.amber.opacity(lit ? 0.5 : 0), radius: 14)
}
```

Explicitly **not** `.opacity().repeatForever(autoreverses: true)`. That produces a soft
sinusoidal throb, which is the universal visual language of *"loading, please wait"* — the exact
wrong message. Armed is not loading. Armed is a cocked hammer. Hard edges, off-beat, high
contrast.

And **no client-side prediction of when armed becomes running.** `TimelineView` here only drives
a blink phase; it never estimates a transition. The state comes from `/status.launch[N]` and
nowhere else.

### The native wins the web page cannot have

**Haptics on the transition, not just the tap.** The tap you already felt with your finger. The
`.armed → .running` flip happens *later*, at the bar line, when you may well be looking at
something else. That's the moment a phone can do something a browser can't:

```swift
.sensoryFeedback(trigger: state) { old, new in
    if old == .stopped && new == .armed   { return .impact(weight: .heavy) }   // tap landed
    if old == .armed   && new == .running { return .impact(weight: .medium) }  // the bar hit
    if new == .stopped && old != .stopped { return .impact(flexibility: .rigid) } // stop
    return nil
}
```

Plus a one-shot bloom on the run: scale `1.0 → 1.03 → 1.0` on a
`.spring(response: 0.22, dampingFraction: 0.6)` with the lime glow radius ramping `0 → 18`. The
button doesn't fade into playing; it *catches*.

**`.contentTransition(.numericText())`** anywhere a number changes — the BPM readout most of all.

### The rejected tap

`ks_web.cpp:118-123` and its comment — *"A key aimed at a Link-owned output must not silently do
nothing"* — is a principle worth honoring:

```css
@keyframes nak{0%,100%{border-color:var(--line);color:var(--mut)}30%,65%{border-color:var(--amber);color:var(--amber)}}
@keyframes nakrow{0%,100%{background:transparent}30%{background:rgba(224,168,58,.14)}}
```

When `linkOwnsTransport && output.followsLinkTransport`, the button renders at `.opacity(0.45)`
with a small outlined `LINK` pill — but it stays *tappable*, and a tap fires a 0.6s amber border
pulse plus a 1.2s amber wash (`KS.consequence`) behind the caption naming the owner, ported
verbatim: *"Link owns transport for outputs set to follow it."* A `.disabled(true)` button that
swallows the tap teaches the user the app is broken. Use `.allowsHitTesting(true)` with the
action branching on ownership, plus `.accessibilityHint`.

**Reduced motion** (mirroring `ui_chrome.c:75`): no blink, no bloom. The armed state gets a
static full-opacity amber fill *plus* a leading `hourglass` glyph, and the label change
STOPPED → ARMING → PLAYING carries the state — which it already does, because the firmware chose
to make the label the state. Haptics stay on; they're not motion.

---

## 3. `OutputCardView` (T-003) — one of four

The web UI puts `RUN` in the middle of the config stack as just another `.fld` row, between
`CABLE` and `NUDGE` (`build_outputs()`, `ks_web.cpp:401-403`). **Invert that.** On a phone the
transport is why you opened the app; cable and swing are why you opened it *once, three weeks
ago*.

```
┌─────────────────────────────────────────┐  KSPanel, radius 14, KS.line hairline,
│ CLOCK OUT 1                    [ ●━━ ]  │  fill: white .02 → clear over KS.panel
│                                         │  (the .frow.out rule, ks_web.cpp:128)
│  ┌───────────────────────────────────┐  │
│  │           S T O P P E D           │  │  ← TransportButton, ≥64pt, full width
│  └───────────────────────────────────┘  │
│                                         │
│  CABLE  │ USB A                      ▾  │  ← KSField, live: .outputCable
│  RATE   │ MIDI clock (24)            ▾  │  ← KSField, live: .outputPPQN
│  NUDGE  │  [−]      +15       [+]      │  ← KSStepperField, live: .outputPhase
│  SWING  │  [−]        0       [+]      │  ← KSStepperField, live: .outputSwing
│                                         │
│  [ ●━━ ]  follow Link transport         │  ← live: .outputFollowsLink
└─────────────────────────────────────────┘
```

Every control in this card has a `KsLiveEdit` case. **The output card cannot reboot anything.**
That's a structural fact, not a visual promise.

- **Header cap:** `CLOCK OUT 1` in 11pt, `.tracking(.18em)`, uppercase, `KS.mut`. Right-aligned
  enable toggle → `.outputEnabled(index:)`.
- **RATE picker options — use the firmware's exact strings** (`ks_web.cpp:385-387`), values and
  labels both: `24 "MIDI clock (24)"`, `48 "×2 (48)"`, `12 "÷2 (12)"`, `6 "÷4 (6)"`,
  `4 "1/16 (4)"`, `2 "1/8 (2)"`, `1 "1/4 (1)"`. Don't rewrite them into "prettier" iOS copy — the
  user reads the same words on the device's page.
- **NUDGE / SWING:** `−250…250` and `0…250` milli-beats, step 5, clamped, exactly as
  `build_outputs()` sets them. The web's 46×46 stepper becomes **48×48**. Value centered, mono,
  `.monospacedDigit()`. Add a horizontal drag-scrub on the value for fine work — a mobile
  affordance the web page has no answer for.
- **Disabled output:** the web hides the section (`.hide{display:none!important}`). **Don't.** On
  a phone that's a layout jump under the user's thumb, and it hides the information you need in
  order to decide whether to enable it. Instead: `.opacity(0.5)` + `.disabled(true)` on the
  config rows and the transport button; card stroke drops to `KS.line.opacity(0.5)`. You can
  still read that Out 3 is set to USB C at ÷2 while it's off.

---

## 4. `DeviceListView` (T-005) — the fleet

`NavigationStack` + `List(.plain)` with custom rows. **Not a `Form`, not `.insetGrouped`.**
Apple's grouped-inset style is precisely the "generic iOS settings app" this must not be.

Background: port `body`'s gradient (`ui_chrome.c:32`) —
`RadialGradient(colors: [Color(hex: 0x14181D), .clear], center: .init(x: 0.5, y: -0.1), startRadius: 0, endRadius: 500)`
over `KS.bg`, `.ignoresSafeArea()`. It's what makes the black look lit rather than flat.

**Two sections, and the split does double duty.** Section headers use the web's group-head
treatment (`ks_web.cpp:126-127`): a 6pt `KS.ledDim` square, then display 600 at 12.5pt,
`.tracking(.12em)`.

- `DISCOVERED` — rows carry `antenna.radiowaves.left.and.right` in `KS.ledText`. Not deletable.
- `ADDED BY HAND` — rows carry an outlined `MANUAL` pill. `.onDelete` bound **only to this
  `ForEach`**, over `devices.filter(\.addedManually)`.

That second point is not cosmetic. `DeviceListViewModel.removeManualDevices(at:)` takes `IndexSet`
offsets into the filtered manual list. Making manual devices their own section means the `ForEach`
collection *is* the filtered list, so the offsets line up **by construction** — the T-005 footgun
is designed out rather than commented around.

**The row.** A miniature rack unit:

```
 ●  KITCHENSYNC-A4F2          ┌─────────┐  ← DSEG7 @ 26pt, ghost "188.8" behind
    kitchensync-a4f2.local    │  128.0  │
    [PLAYING]                 └─────────┘
                              4 PEERS
```

- **Left:** the `.pwr` LED (`ui_chrome.c:41`) — 9pt circle, `KS.led`,
  `.shadow(color: KS.led, radius: 5)`, breathing on the firmware's exact curve
  (`@keyframes breathe{0%,100%{opacity:1}50%{opacity:.45}}` over 3.4s →
  `.easeInOut(duration: 1.7).repeatForever(autoreverses: true)` between `1.0` and `0.45`).
  **If `/status` last failed, the LED goes `KS.mut`, stops breathing, and the row drops to
  `.opacity(0.45)`.** The web page never needs an offline state; the app does, constantly, and
  it's the first thing a user checks. (See T-010.)
- **Right:** the tempo glass at small scale, ghost layer intact. Reusing the segmented readout in
  the list is what makes this feel like *a fleet of instruments* instead of a list of hostnames.
  Under it, peers in mono 10.5pt `.tracking(.16em)`.
- **The playing pill** — derived exactly the way the web derives it (`ks_web.cpp:225-229`). That's
  real logic; put it on the model where it can be tested, not in the view:

  ```swift
  extension KsStatus {
      enum TransportSummary { case stopped, arming, playing }
      var transportSummary: TransportSummary {
          if linkOwnsTransport { return playing ? .playing : .stopped }
          if launch.contains(.running) { return .playing }
          if launch.contains(.armed)   { return .arming }
          return .stopped
      }
  }
  ```

  Rendered as `KSPill`: `.playing` → filled `KS.ledOn` with `KS.onInk` text; `.arming` → outlined
  amber, **blinking at beat rate** like the transport button; `.stopped` → outlined `KS.mut`. An
  arming device must be identifiable from the fleet screen without drilling in.

**Empty state.** Not "No Devices." The overwhelmingly common real cause is the phone being on the
wrong SSID or a network with mDNS blocked. Say that: a searching pulse, *"Looking for KitchenSync
units on this network…"*, then *"Your phone must be on the same WiFi as the device. Some guest
networks block discovery."*, then a prominent **Add by IP** button. `AddDeviceView` is a single
`KSField("HOST")` — `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()`,
`.keyboardType(.URL)` — placeholder `kitchensync-xxxx.local or 192.168.1.42`, calling
`addManualDevice(host:)`.

`.task { vm.start() }` / `.onDisappear { vm.stop() }`, and `.refreshable` for a manual re-browse.

---

## 5. `DeviceDetailView` (T-006) — the instrument

`ScrollView`, not `Form`, same reason as above.

**Header — port the rack head almost verbatim.** Brand row (`ks_web.cpp:174`): breathing LED,
then `KITCHEN·SYNC` in display 800 20pt `.tracking(.06em)` uppercase with `SYNC` in `KS.ledText`
(`.wordmark b{color:var(--led)}`), then `ESP32-P4 · FW 1.2.3` right-aligned in 10.5pt
`.tracking(.18em)` `KS.mut`. This is the one place the skeuomorphism earns its keep.

**The tempo glass — the hero.** Build it as `KSGlass` and reuse it in the list row:

```swift
RoundedRectangle(cornerRadius: 11, style: .continuous)
    .fill(LinearGradient([0x0A0D0A, 0x070907], .top, .bottom))
    .overlay(RadialGradient(colors: [KS.led.opacity(0.08), .clear],
                            center: .init(x: 0.5, y: -0.2),
                            startRadius: 0, endRadius: 220))
    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color(hex: 0x1F261B)))
    .overlay { ZStack(alignment: .leading) {
        Text("188.8").font(.seg(58)).foregroundStyle(Color(hex: 0x1A2113))   // ghost
        Text(bpmString).font(.seg(58)).foregroundStyle(KS.led)
            .shadow(color: KS.led.opacity(0.45), radius: 14)
            .contentTransition(.numericText())
    }}
```

Every value there is lifted from `ui_chrome.c:45-57`. The inner shadow
(`inset 0 0 32px rgba(0,0,0,.9)`) has no SwiftUI primitive — approximate with an inner
`strokeBorder(.black.opacity(0.9), lineWidth: 14).blur(radius: 8).clipShape(...)`.

Top strip: the 8pt beat dot (`KS.ledDim` → `KS.led` + glow, ~90ms lit, `TimelineView` at
`60/bpm`, same generator as the armed blink), `SESSION TEMPO` in `#6F8A4D`, and the source
right-aligned in `KS.amberText`.

**One honest improvement over the web:** the page hardcodes `Ableton Link` as the source.
`KsStatus` knows better — if `peers == 0 && midiClockInBPM > 0` show `MIDI CLOCK IN`; if
`peers == 0 && followBeatValid` show `FOLLOW BEAT`; otherwise `ABLETON LINK`. A tempo display
that lies about its source is worse than one that has no label.

**Meter bridge.** The web's phone layout flings label and value to opposite edges
(`.row{justify-content:space-between}`), but its *desktop* rule stacks them (`@media (min-width:760px)`:
`.row{flex-direction:column;align-items:flex-start;gap:7px}` in a 4-column grid). **The desktop
rule is the right one for a phone.** A stacked label/value pair is one glance; a label and a value
300px apart is two. Use a 2-column `LazyVGrid` of `KSStatCell`: LINK PEERS, USB-MIDI (a `KSPill`,
`.on` when connected), MIDI CLOCK IN, CLOCK OUT (pulses), FOLLOW BEAT (`off` / `listening…` /
`128.0 BPM` — exactly the three strings at `ks_web.cpp:248`), TRANSPORT.

**Master transport.** The web's `.tp` PLAY/STOP buttons are ~26pt tall (`padding:6px 12px`).
Unusable. Replace with two side-by-side buttons at **≥56pt**: `PLAY` (lime, and it renders
amber+blinking while any output is `.armed`, since play is quantized here too) and `STOP` (ember,
immediate, always enabled, **no confirmation ever**). Two buttons rather than one toggle, mapping
directly to `postTransport(output: nil, play:)` — a single toggle whose state is a *derived
summary* will show the wrong thing during a mixed arming/playing moment, and it will show it on
stage.

**Live sections**, each wrapped in `KSSectionRail` — the `.sect` left rail (`ks_web.cpp:91-92`):
a 2pt `KS.line` vertical rule with a 28pt `KS.ledDim` cap at the top. A small detail that makes a
stack of rows read like a patch bay.

- `MIDI CLOCK OUT` — master enable → `.clockOutEnabled`. Then the four `OutputCardView`s.
- `METRONOME` — accent → `.metronomeAccent`; VOL 0–100 step 5 → `.metronomeVolume`; VOICE
  (Tone / Click / Wood, per `build_voice()`) → `.metronomeVoice`. **The enable toggle is not
  here.** See §6.
- `LED STRIP · VISUAL METRONOME` — enable → `.ledEnabled`; BRIGHT / FADE 0–100 step 5; MODE
  (Chase / Flash / Fill, per `build_led()`); BEAT and ACCENT colors via
  `ColorPicker(supportsOpacity: false)` → `.ledBeatColor` / `.ledAccentColor` as `UInt32`.
- `DIAGNOSTICS` — a `DisclosureGroup`, collapsed. `TickHealth` and `PhaseHealth` as mono rows.
  One thing here is not decoration: `PhaseHealth.maxStepMicros` is, per the firmware's own
  comment, *"the number that, unread, cost 138 seconds of silent DIN clock in ESP-027."* Put an
  amber dot on the collapsed header when it exceeds a threshold. **⚠️ OPEN QUESTION: what is that
  threshold? Not invented here — get the number from whoever owns `link_measurement`.** Same for
  `droppedTicks > 0`, which is unambiguous and needs no threshold.

**Debounce, at the firmware's own interval.** `ks_web.cpp:315-319`:

```js
var num=el.type==='number';
el.addEventListener(num?'input':'change',function(){
  if(num){clearTimeout(liveT);liveT=setTimeout(function(){postLive(el)},60)}else postLive(el)})
```

Continuous controls debounce at **60ms**; discrete controls (toggles, pickers, steppers) post
immediately. Copy that split and that number — it's already tuned against a device whose `/live`
handler debounce-writes NVS (`config_persist_mark`, ARC-022). Sliders and `ColorPicker` hold a
local `@State` and fire a cancel-and-rearm `Task` with a 60ms sleep. Steppers post on the tap.

---

## 6. The live / reboot split — the hard constraint

The rule is `KsLiveEdit`'s case list, and nothing else. Not field names, not intuition.
`metronomeVolume`, `metronomeVoice`, `metronomeAccent` are live; `metronome` **enable** is not.
`led` enable *is* live; `follow_beat` enable is not. Verifiable in the firmware: the
`class="live"` attribute at `ks_web.cpp:193/199/202/203/206` and throughout
`build_outputs()`/`build_led()`, and its conspicuous absence at `ks_web.cpp:196` (metronome),
`ks_web.cpp:209` (follow_beat), and in `build_wifi()`.

The design answers this **structurally first, visually second.** Visual affordances are a
backstop. Structure is the mechanism.

### Structural

> **Everything on `DeviceDetailView` is live. Nothing on `DeviceDetailView` can reboot. The
> Settings sheet contains only reboot-required controls, and nothing else.**

Enforce it in the type system, not in review comments:

- **`KSLiveControl`** — a wrapper every control on the detail screen goes through. It takes a
  `KsLiveEdit`-producing closure. You cannot construct one without a `KsLiveEdit` case, and there
  is no case for WiFi, metronome-enable, or follow-beat-enable. A developer who tries to put the
  metronome enable toggle on the detail screen finds there is no case to hand it.
- **`WriteAndRebootButton`** — `internal` to the settings feature. Unreachable from the detail
  screen.
- **A partition test** over `KsConfig.saveFormFields(wifiEdits:)`'s key set: split it into exactly
  two disjoint sets — the keys `KsLiveEdit` can emit, and a declared `RebootRequired` list.
  **Every key must land in exactly one, and the test fails if a new field appears in neither.**
  That is the only durable defense against the trap — if firmware later makes the metronome enable
  live-safe, the test tells you, instead of a user discovering it on stage.

### Visual — three affordances

**1. A live edit flashes lime.** The web already defines the vocabulary and only uses it for focus
(`ui_chrome.c:59`): `.fld:focus-within{border-color:#4a5a2c;box-shadow:0 0 0 3px rgba(182,255,54,.08)}`.
Repurpose it as **confirmation**: on a successful `/live` 200, the `KSField` frame pulses that
ring for ~250ms. Applied instantly, shown instantly. A control that pulses lime **has already
taken effect** — that becomes the app's word for "live," learned in the first ten seconds of use
and never explained.

On failure: pulse `KS.ember` and **revert the local value**. Never leave a slider displaying a
number the device does not have.

**2. The reboot controls physically do not exist on the live surface.** They exist only in the
sheet: `.sheet` + `.presentationDetents([.large])`, `.interactiveDismissDisabled(hasEdits)`. Its
header is a consequence band — `KS.amberText` on `KS.consequence` (the firmware's own
`rgba(224,168,58,.14)`, already its color for *"this is a consequence"*, from `@keyframes nakrow`):

> **These settings reboot the device.** Saving writes to flash and restarts. The device drops out
> of the Link session and all clock output stops for about ten seconds.

The web UI has no warning of any kind. Its only signal is the button's label. That's the biggest
gap between the reference and what the app must be.

The commit control is `.write` ported literally — full-width, `KS.ledOn`, display 800 16pt
`.tracking(.14em)`, uppercase, 17pt padding, with the 6pt hard bottom shadow and the key-travel
press:

```swift
// .write:active{transform:translateY(4px);box-shadow:0 1px 0 #5e8a16}
.offset(y: pressed ? 4 : 0)
.shadow(color: Color(hex: 0x5E8A16), radius: 0, y: pressed ? 1 : 6)
.shadow(color: KS.led.opacity(0.5), radius: 15, y: pressed ? 4 : 16)
.animation(.easeOut(duration: 0.06), value: pressed)
```

Labelled, in the device's own words: **WRITE & REBOOT**. Behind an alert that **names the
device** — `"Write & Reboot kitchensync-a4f2?"` — because you probably have three of them on the
bench.

**3. The metronome trap gets physical separation.** In the web UI, metronome-enable and
metro-accent are the same `.sw` control, forty pixels apart, in the same box, and one of them
reboots the device. In the app, the METRONOME section on the detail screen contains **accent,
volume, and voice only**. Where the enable toggle would sit, there is a **read-only status row**:

```
ENABLE          ON  ›            ← mono value, chevron, KS.mut. Not a control.
                                   Tapping opens the Settings sheet, scrolled to it.
```

It cannot be flipped from a live surface. Follow Beat gets the same treatment, and it's free — the
web already renders it as a read-only status row (`ks_web.cpp:184`), so it just becomes a
`KSStatCell` in the meter bridge.

Sheet-side, the mirror: **every control in the sheet carries a `REBOOTS` tag** — an outlined
`KS.amberText` capsule, 9.5pt, `.tracking(.14em)`. Exactly three controls, exactly three tags:
WiFi, Metronome Enable, Follow Beat Enable. Generated from the `RebootRequired` list that the
partition test guards, so an untagged control in that sheet is impossible.

### Settings sheet contents (T-007)

Order matters, and it is **deliberately the reverse of the web's**. `build_wifi()` output is
rendered first (`ks_web.cpp:190-191`) because, as the source comment says, the DOM keeps WiFi
first "for the phone setup flow." That reasoning does not survive into the app: if you're in this
sheet, discovery already found the device — WiFi is the *least* likely thing you're changing and
by far the most dangerous thing to fat-finger. **Put it last.**

1. `METRONOME` — enable toggle. `[REBOOTS]`
2. `FOLLOW BEAT (MIC)` — enable toggle. `[REBOOTS]`
3. `WIFI NETWORKS` — three slots (`KS_WIFI_SLOTS`), each an SSID `KSField` and a `SecureField`
   PASS. `[REBOOTS]`

Passwords are write-only, and the UI has to teach that:

- Placeholder text is the firmware's own (`build_wifi()`, `ks_web.cpp:373-374`): `keep current`
  when `slot.passwordIsSet`, empty otherwise. `required` / `optional` on the SSID fields, slot 0
  vs. the rest — same as the device.
- A slot with `passwordIsSet` shows a small lime `SET` pill. **Never a row of dots** — dots imply
  an editable secret that could be selected and deleted, and there is no such thing here.
- Caption under each password field, in `KS.mut`: *"Leave blank to keep the saved password."* A
  blank field otherwise reads as "erase it."
- One more thing the web never says out loud although `build_wifi()`'s comment states it plainly
  ("Clearing an SSID forgets that slot"): caption it. *"Clear the SSID to forget this network."*
- `WifiCredentialEdit` is keyed by slot `id`, never array position. If the view filters or sorts,
  it carries the `id` — `saveFormFields` picks the `wifi_ssid` / `wifi_ssid1` / `wifi_ssid2`
  suffix from it, and getting that wrong silently overwrites the wrong network.

**Post-save state.** T-007 wants the device shown as rebooting. Model it — `.rebooting(since: Date)`
on the device. The tempo glass drops to **ghost layer only** (all segments unlit — the display is
genuinely dark, which is exactly what the hardware is doing), everything else dims to
`.opacity(0.35)`, and a mono caption reads `REBOOTING…`. Polling continues. The instant `/status`
answers, snap back and the beat dot starts flashing. This is precisely what the device's own page
does — `send_result(..., reboot: true)` renders `ui_result_page` with poll-until-alive so the
browser isn't stranded on `/save` (`ks_web.cpp:560-563, 611`). Same behaviour, ported.

**Firmware sheet (T-008), briefly:** same reboot vocabulary, same consequence band, plus the
reassurance the task asks for — *"A failed flash does not brick the device. Dual-slot OTA means it
stays on the current firmware."* — and the target acknowledgement, since nothing in the client
validates the binary against the chip. Progress in `KS.ledOn` on `KS.panel`. `.fileImporter`
limited to `.data` with a `.bin` extension check.

---

## 7. Component library to build

| Component | Web origin | Notes |
|---|---|---|
| `KSPanel` (ViewModifier) | `.unit` | Gradient `#191D22 → #101317`, hairline `KS.line`, radius 16, `.shadow(radius: 60, y: 22)`. **Drop the screws.** |
| `KSField<Content>` | `.fld` + `.pre` | The workhorse. Prefix at `KS.mut`, not `#4B535B`. |
| `KSStepperField` | `.fld.nudge` + `.stp` | 48pt steppers, step 5, clamped, drag-scrub. |
| `KSSwitchStyle: ToggleStyle` | `.sw` | 52×28 lime track, `#0A0D07` knob when on, glow. 44pt tap via padding. |
| `KSPill` | `.pill` / `.pill.on` | |
| `KSSectionRail<Content>` | `.sect` | 2pt rail + 28pt `KS.ledDim` cap. |
| `KSGlass` | `.scr` / `.readout` | Ghost + live segments. Reused at 58pt (detail) and 26pt (list). |
| `KSStatCell` | `.row` (desktop variant) | Label stacked over value. |
| `WriteAndRebootButton` | `.write` | `internal` to Settings. |
| `TransportButton` + `TransportAppearance` | `.tgl` | Appearance is a pure, testable function. |
| `OutputCardView` | `.frow.out` | |

## 8. Deliberate departures, summarized

| Web UI does | App does | Why |
|---|---|---|
| Corner screws (`.screw`) | Drop them | Skeuomorphic bolts on a 6" screen read as costume, and they crowd the corners where iOS wants air. |
| `.tgl` armed is a static amber | Blinks at beat rate, hard-edged, 35% duty | The load-bearing feedback for a quantized launch. The web UI under-delivers here. |
| `.tp` PLAY/STOP ≈26pt tall | ≥56pt, side by side | Below the 44pt floor. This is the control you hit under pressure. |
| `.tgl` ≈40pt | ≥64pt | Same. |
| `.hide{display:none!important}` on disabled sections | Dim + disable | Layout jump under the thumb; and you lose the ability to see what a disabled output is configured as. |
| `.pre` at `#4B535B` (~2.5:1) | `KS.mut` (~5.1:1) | Fails AA. Nothing about the look depends on it being unreadable. |
| `.foot` at `#3C444C` (~2:1) | `KS.mut` | Same. |
| WiFi first in the form | WiFi last in the sheet | The DOM order exists for the browser setup flow. In the app, discovery already worked — WiFi is the least likely and most dangerous edit. |
| Reboot vs. live is an invisible CSS class | Structural separation + lime confirmation pulse + `REBOOTS` tags + a partition test | The trap the whole app exists to fix. |
| Dark only | Dark by default; light mode supported; instrument surfaces stay dark in both | The device is dark, the room is dark. But an app unusable on a bright bench is broken. `#B6FF36` as text on white is 1.4:1 — hence the fill/text token split. |
| Keyboard shortcuts (`.kbd`) | No equivalent — flagged | The real mobile answer to "transport without unlocking" is a **Live Activity** showing the four launch states. Out of scope for T-003–T-008; worth its own task. |

---

**The one-line brief:** it's a rack unit that fits in a hand. Near-black, one lime LED, one amber
warning, a segmented tempo display with its unlit segments showing through, and a big ember-red
button that blinks on the beat while it waits for the bar line. Everything you can touch on the
main screen takes effect the instant you touch it, and pulses lime to prove it. The three things
that reboot the device live behind one door, wear a warning band, and are committed with a key
that has travel.
