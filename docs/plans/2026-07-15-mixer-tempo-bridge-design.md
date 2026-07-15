# Mixer Tempo Bridge — design

**Date:** 2026-07-15
**Status:** design, not yet scheduled
**Working title:** "mixer tempo bridge" (deliberately neutral — see [Naming](#naming))

> A standalone iOS app that turns the phone itself into the tempo bridge the X32Link
> *hardware* does: take a tempo (Ableton Link, MIDI clock in, or an in-app tap), and drive a
> mixing console's tempo over its own protocol (OSC for the Behringer X32/M32 to start). Sell it
> cheap, and let the app's own limits sell the hardware.

## How this idea arrived

It started as "X32Link could be its own app" — splitting the headless X32Link device out of the
unified KitchenSync companion app. That much was already well-motivated: X32Link serves a different
user (a front-of-house / console engineer, not a KitchenSync clock musician), speaks its **own**
firmware web surface (`X32Link/web_config.cpp`, `X32Link/ks_status.c` in `link-devices` — *not*
`KitchenSync/main/ks_web.cpp`), and its lineage is separate — it began life as a **MIDI-in → OSC**
box that syncs an X32's tempo, growing Link and MIDI-out only later. It *converged* on the
KitchenSync web protocol; it wasn't born from it.

Then the idea grew a second, larger half: **the app can replace the firmware.** iOS runs Ableton
Link natively (Link is a network protocol — no hardware required), computes the beat, and sends OSC
straight to the console over WiFi. That is exactly what the box does, minus the box.

So the product is two things at once:

1. **A $1 app** that bridges tempo → console for anyone with a phone on the same network.
2. **A storefront for the hardware**, upsold at the exact moments the app can't win.

## Why the funnel is honest

The phone *cannot* be the always-on bridge: iOS suspends apps, the phone leaves the venue in
someone's pocket, and it has no DIN/USB MIDI out. So the $1 app is the "soundcheck / small gig / try
it" tier, and the box is the "patch once, forget, survives the show, real MIDI I/O" tier. **The
limitation of the app literally is the sales pitch for the hardware.** That makes the upsell truthful
rather than nagging.

## Architecture

One deep module in the middle; everything else is an adapter at a seam.

```
 TempoSource ──▶ BridgeEngine ──▶ MixerTempoSink ──▶ console
  Link            (the core)       ├─ X32/M32 (OSC/UDP :10023)   ◀ build now
  manual tap                       ├─ Allen & Heath              ◀ later
  MIDI-in                          └─ Yamaha / …                 ◀ later
```

This is the same `source → master clock → output` spine the firmware runs
(`X32Link/master_clock.h`, `beat_source.h`), which is why it ports cleanly — and keeps *the firmware
is the source of truth* alive even in a rewrite.

### `BridgeEngine` — the deep module

Owns the current `{ bpm, isPlaying, beatPhase }`, decides when the console needs an update, and
**never predicts transport client-side** — the source is the truth, the engine mirrors it (the same
rule the KitchenSync app lives by: never render a lock that isn't real). It mentions neither Link nor
OSC. Pure and testable: feed it a source event, assert the sink intent it produces.

### `TempoSource` — the input seam

Interface emitting `{ bpm, beatPhase, isPlaying }`. Adapters:

- `LinkTempoSource` — LinkKit; the phone joins the network Link session. *Gated on Ableton
  licensing.*
- `ManualTempoSource` — in-app tap / BPM entry; works standalone with nothing else on the network.
- `MidiClockTempoSource` — Core MIDI (USB camera-kit or network/RTP MIDI); mirrors the device's
  original MIDI-in heritage. **Additive** — same interface, so it can land after v1.

### `MixerTempoSink` — the output seam

Interface: *"a console you can hand a tempo to."* Given engine state, deliver it however **this**
console wants — tap-tempo messages, a tempo parameter, whatever — and own **finding and connecting
to** that console (an X32 answers its own OSC `/info` handshake; another mixer won't). Protocol-
agnostic on purpose: not every console speaks OSC.

- `X32MixerSink` — OSC/UDP :10023, the one concrete adapter for v1 (covers X32 and M32).
- Other consoles drop in against the same interface later, without the engine knowing.

**Deletion test, both seams:** delete `MixerTempoSink` and the X32's OSC quirks leak into the
engine; delete `TempoSource` and three tempo inputs each grow their own copy of the engine. Both earn
their keep the moment the second adapter exists — which the roadmap guarantees.

## Reliability, background execution, and failure

This is where a live-audio tool is won or lost.

- **Background — best-effort, and say so.** Stay alive when locked via the standard Link pattern:
  `UIBackgroundModes: audio` + a live `AVAudioSession` keep-alive; disable auto-lock
  (`isIdleTimerDisabled`) on the bridge screen. v1 can be **foreground-first**, background a bonus.
  The ceiling isn't hidden — it's surfaced at the moment it bites, as the hardware pitch.
- **Timing is coarse, which is why this works over WiFi.** We *set a tempo* (a BPM value / tap), we
  do **not** stream a sample-accurate clock. OSC-over-WiFi jitter is tolerable for a BPM set. The
  engine sends on meaningful change (debounced) plus a slow keepalive — not a packet per beat.
- **Failure gets distinct signals** — the recurring lesson of this codebase (T-009/010/016/018/021):
  three problems, three fixes, never collapsed.
  - **No tempo in** — Link peers gone / MIDI-in silent / manual unset.
  - **Console unreachable** — network or mixer gone.
  - **Console reachable but not accepting** — connected, wrong dialect / rejected.
  A pure, testable `BridgeStatus` classifier owns that three-way decision (same shape as
  `TransportAppearance` / the `DeviceFault` idea in T-021). The "lock is holding" indicator is the
  primary UI and shows **truth, never optimism.**

## Product surface (v1)

- **Bridge only.** Do *not* also build "configure my hardware box" for launch — the box already has
  its own web UI (`web_config.cpp`), so a box owner isn't stranded. Box-config is a later feature.
- **Upsell is limitation-triggered**, not a banner: phone-about-to-sleep, wants-MIDI-out,
  leave-it-at-the-venue — each nudge is the app honestly naming what it can't do, plus one store
  link.
- **Apple constraint:** physical hardware must **not** use in-app purchase; physical goods sell via
  an external link out. So "$1" is the app (paid up front, or a $1 unlock), and the hardware is a
  link, never an IAP. That's the compliant path anyway.

The app surface stays small: a bridge screen (source picker, mixer connection, a big "lock is
holding" indicator) and a "get the hardware" route.

## The shared core with KitchenSync — deferred on purpose

The bridge pivot **dissolves** the original "shared package, two apps" premise. When X32Link was a
*companion* app it shared KitchenSync's whole substrate (`KitchenSyncClient`, `KsConfig`/`KsStatus`
decode, discovery, the form machinery). A *bridge* app shares almost none of that — its spine
(`TempoSource`, `BridgeEngine`, `MixerTempoSink`) is brand new and, in v1, never talks to a
KitchenSync device's web API at all. The overlap is a Bonjour helper and some UI tokens: a
coincidence, not a seam.

So **v1 is a clean standalone app; no shared package.** Forcing a share now is exactly the
premature-abstraction the architecture review warns against — one weak overlap is a *hypothetical*
seam.

The package (`LinkDeviceKit`) earns its place **later**, at one trigger: when the bridge app grows
the deferred box-config feature, which reuses KitchenSync's companion substrate (discovery +
`/status`/`/config.json` decode against the box's `web_config.cpp`). Two real consumers — then
extract. Not before.

## Testing

The seams exist so the whole bridge is testable against fakes — no hardware, no phone-on-network, no
console, no Link session. Same discipline as the KitchenSync app's `StubURLProtocol` (test the *real*
thing against a stub, never a mock of ourselves).

- **`BridgeEngine` in isolation** — scripted `TempoSource` events in, assert `MixerTempoSink` intents
  out: change-detection, debounce, keepalive, transport-truth. Pure, no I/O; gets the most tests.
- **In-memory adapters at both seams** — a fake source (drive sequences) and a recording sink
  (capture what would be sent) exercise the bridge end-to-end with zero real dependencies.
- **`BridgeStatus` classifier** — pure function, tested directly: (source-state × sink-state) →
  three-way signal.
- **`X32MixerSink` against golden OSC fixtures** — the one place encoding a real external protocol,
  so build fixtures from *actual* X32 OSC bytes (real wire output, not plausible-looking messages).
- **Named known gap** (house style): LinkKit joining a real session, iOS background survival, WiFi
  jitter, a real console accepting the OSC — none unit-testable. Needs a bench (real X32 + a Link
  source). Until then, verified against a *reading* of the X32 OSC spec, not against a console.

TDD carries over: tests first.

## Open questions

These are gates and unknowns to resolve before (or early in) implementation — parked here so they
don't get lost:

1. **Naming.** *Both* halves of "X32Link" are trademarks: "X32" is Behringer's, "Link" is Ableton's
   (the Link license restricts putting "Link" in an app name). The app needs a neutral, likely
   made-up brand. This is a real gate on shipping, not cosmetic. → run a dedicated naming pass.
2. **Ableton Link licensing.** LinkKit is free but requires registering the app with Ableton and
   accepting the Link license. This gates the `LinkTempoSource` adapter and the whole "sync to a
   session" story. Confirm terms (and any branding/attribution requirements) before building on it.
3. **X32 OSC dialect — exactly which messages.** Tap-tempo vs. setting an FX tempo parameter vs.
   both; how the console is discovered (`/info` handshake); ports and rate limits. Needs the X32 OSC
   spec pinned down and a bench unit to confirm.
4. **Background-execution reality.** How reliable is `audio`-mode keep-alive across current iOS
   versions and lock/background/network-change transitions? Decide whether v1 claims background at
   all, or ships foreground-first.
5. **Pricing mechanics.** $1 paid-up-front vs. free + $1 unlock IAP. And the hardware store-link flow
   (must stay outside IAP for physical goods).
6. **Box-config timing.** When (if) the bridge app grows "configure my hardware box," that's the
   trigger to extract the shared `LinkDeviceKit` package with KitchenSync. Not a v1 concern; flagged
   so the future extraction has a defined cause.
7. **MIDI-in scope.** `MidiClockTempoSource` is additive but non-trivial on iOS (Core MIDI, camera-
   kit vs. network MIDI). Confirm it's post-v1 unless a specific user needs it at launch.

## Relationship to existing work

Standalone app; **not** part of the current KitchenSync iOS codebase in v1. It mirrors the firmware's
`source → master clock → output` architecture (`X32Link/` in `link-devices`), and reuses this
project's house disciplines wholesale: distinct-signals error classification, decisions-as-pure-
functions, truth-never-optimism UI, firmware-derived test fixtures, and naming a known gap rather
than pretending it's covered.
