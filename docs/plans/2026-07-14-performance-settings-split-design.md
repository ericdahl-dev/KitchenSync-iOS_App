# Performance / Settings split

**Date:** 2026-07-14
**Status:** agreed, implementing

## Why

The device screen is one long scroll: tempo, transport, output cards, per-output cable/rate/nudge/
swing, metronome, LED, diagnostics. On stage you want transport and nothing you can fat-finger. At
soundcheck you want the knobs. Right now they're interleaved, so the stage case carries the
soundcheck case's clutter — and its hazards.

## The split criterion

Not "advanced vs basic". **What do you actually reach for MID-SET?**

- **Transport** — obviously.
- **Nudge** — yes. The firmware's own comment says it "slides the RC-505 into the pocket", it's live
  via `/nudge`, no reboot. That's a playing control, not a setup one.
- **Swing** — yes. A groove control you feel your way to while the band plays.
- Everything else — cable, PPQN, follow-Link, click volume, LED, WiFi, diagnostics — is set once and
  left alone.

## The three surfaces

### PERFORMANCE — the device screen, where you always land

- Tempo glass, beat dot, tempo source
- Meter bridge: peers, USB-MIDI, MIDI clock in, follow beat, transport, clock pulses (read-only)
- Master `PLAY` / `STOP`
- Per output: the big transport button, **NUDGE**, **SWING**

Nothing else. **Nothing on this screen changes your sound** — only your timing and your transport.
You cannot knock a cable assignment or a clock division loose mid-set, because they are not there to
knock.

### SETTINGS (⚙ sheet) — everything LIVE

Applies instantly; the field pulses lime to prove it.

- Per output: enable, CABLE, RATE, follow-Link
- Click: volume, voice, accent — **only if a speaker is fitted**
- LED: brightness, mode, fade, colours — **only if a strip is wired**
- Diagnostics (tick / phase health)
- A door at the bottom → **Device Setup**

### DEVICE SETUP (sheet from Settings) — everything that REBOOTS

- Metronome **enable**, follow-beat **enable**, WiFi
- Consequence band, `REBOOTS` tags, `WRITE & REBOOT` key, confirmation naming the device

## The invariant, restated

**No surface ever mixes live and reboot controls.**

That is not decoration. The device's own web page puts the metronome **enable** toggle and the
**accent** toggle forty pixels apart, as the identical component, in the same box — one applies
instantly, the other reboots the device mid-set, and nothing on screen says so. That trap is what
this app exists to fix, and it is fixed *structurally*, not with labels:

- `KSLiveControl` cannot be constructed without a `KsLiveEdit` case, and no such case exists for a
  reboot-only field.
- `LiveRebootPartitionTests` fails CI if any `saveFormFields` key is neither live-editable nor
  declared reboot-required.

Merging everything into one Settings sheet would have re-created that adjacency with better
labelling. Better labelling is not the same as impossible.

## Capability still drives visibility

Sections appear only for hardware the device reports (`link-devices` ESP-030). No speaker, no click
section. No strip, no LED section. Solder a strip onto a Touch, flip one firmware flag, and the LED
section appears — with no change to this app.

## Firmware update stays in the toolbar

**Not** inside Settings. Settings needs `/config.json`, which 404s on old firmware — and a firmware
update is how you *escape* that state. Gating the escape behind the thing that's broken would strand
the user (T-009).

## What this does NOT change

- The quantized transport model (arm → bar line → run), and never predicting it client-side.
- The blink at beat rate on `.armed`.
- The reboot flow: `WRITE & REBOOT` → `isRebooting` → clears when `/status` answers.
