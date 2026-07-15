# gstack

Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools directly.

Available gstack skills:
/office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /connect-chrome, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /setup-gbrain, /retro, /investigate, /document-release, /document-generate, /codex, /cso, /autoplan, /plan-devex-review, /devex-review, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade, /learn

# KitchenSync iOS

Companion app for the KitchenSync/X32Link fleet in [`link-devices`](https://github.com/ericdahl-dev/link-devices).
Plain HTTP + Bonjour against the protocol `KitchenSync/main/ks_web.cpp` already serves.

Architecture docs live in [`docs/architecture/`](docs/architecture/) and app-local decisions in
[`docs/decisions/`](docs/decisions/); platform-wide decisions are the `link-devices` ADRs (this
app follows and references them — it does not fork them).

## The firmware is the source of truth

Field names, value grammars, and option strings are copied from the firmware, not invented.
Where the Swift and the firmware disagree, **the firmware is right and the Swift is the bug.**
Each Swift type's doc comment names the C symbol it mirrors — keep that up.

When you need a protocol fact, read it in `link-devices`:
`KitchenSync/main/ks_web.cpp` (routes), `ks_config.c` (form grammar), `ks_config_json.c`
(`/config.json`), `ks_status.c` (`/status`), `wifi_link.c` (mDNS). The web UI's CSS lives in
`X32Link/ui_chrome.c`, which `ks_web.cpp` includes as `%CSS%`.

## Live vs reboot IS the `KsLiveEdit` case list

This is the single most important rule in the codebase, and it is **not guessable from field
names.**

- `POST /live` — partial patch, applied instantly, no reboot. Restricted to `KsLiveEdit`'s
  closed case set.
- `POST /save` — the full form. Persists to NVS and **reboots the device**: it drops out of the
  Link session and all clock output stops for several seconds. Mid-set, that is destructive.

The trap: `metro_accent`, `metro_vol` and `metro_voice` are live, but metronome **enable** is
not. `led` enable *is* live, but `follow_beat` enable is not. (The ES8311 codec and I2S only come
up at boot.) On the device's own web page those toggles are the identical component forty pixels
apart, with nothing on screen distinguishing them.

Three defenses, and **do not weaken any of them**:

1. Every control on `DeviceDetailView` routes through a `KsLiveEdit` case, so that screen
   *cannot* reboot the device — there is no case to hand a reboot-only field.
2. Reboot-required settings exist only in `DeviceSettingsSheet`, behind a consequence band and a
   confirmation that names the device.
3. `LiveRebootPartitionTests` asserts every key `saveFormFields` emits is either live-editable or
   declared in `KsConfig.rebootRequiredFormKeys` — exactly one, never both, never neither. Add a
   field without classifying it and CI fails.

Passwords are write-only. `/config.json` never returns one; blank means "keep current".
`WifiCredentialEdit` is keyed by slot `id`, **never array position** — get that wrong and you
silently overwrite the wrong saved network.

## Transport is quantized

Play **arms** and fires on the next bar line. Stop is immediate. The device computes
`TransportLaunchState` (stopped / armed / running) and reports it in `/status.launch[N]` on every
poll.

**Never predict the armed→running transition client-side.** No local timers, no optimistic state.
The device already computes it; guessing is how you show a running output that never started.

The armed state blinks at beat rate (`60/bpm` — the firmware's own `flashBeat` cadence) because
it is the only evidence a tap registered and it may persist for most of a bar. Hard-edged, not a
soft `repeatForever` throb: a throb reads as "loading", and armed is a cocked hammer.

## Build

`project.yml` is the source of truth. **XcodeGen *regenerates* `Sources/KitchenSyncApp/Info.plist`
on every run — hand-edits to that file are silently overwritten.** Plist keys go under
`info.properties` in `project.yml`. The `.xcodeproj` is gitignored; regenerate, don't hand-edit.

Two Info.plist keys are load-bearing and easy to lose: `NSLocalNetworkUsageDescription` and
`NSBonjourServices`. Without them iOS silently blocks Bonjour browsing *and* `.local` resolution
— discovery finds nothing, every request fails, and there is no useful error to go on.

```sh
xcodegen generate
xcodebuild -project KitchenSyncApp.xcodeproj -scheme KitchenSyncApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Tests

**TDD is the rule here: tests first, never backfilled.**

Network tests run the **real** `KitchenSyncClient` against `StubURLProtocol` — mocking the client
itself would only assert that our fake calls our fake. Build fixtures from the firmware's actual
`snprintf` / `ks_config_set()` output, not from plausible-looking JSON.

Logic that decides something (state→appearance mapping, tempo source, transport summary) belongs
on a model as a pure function where it can be asserted — not inside a `View`.

CI runs on a **self-hosted macOS runner** (GitHub bills hosted macOS at 10× on private repos).

## Known gap

**Nothing has ever spoken to a real device.** Every network test runs against a stub;
`KitchenSyncDiscovery` has never seen a live Bonjour responder. Use `link-devices/tools/linkcli`
to get a unit on the bench. Treat the protocol layer as verified against a *reading* of the
firmware, not against the firmware.
