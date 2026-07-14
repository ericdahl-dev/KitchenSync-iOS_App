# KitchenSync iOS

Companion iOS app for the [`link-devices`](https://github.com/ericdahl-dev/link-devices)
KitchenSync/X32Link fleet: discover units on the LAN, show live status, edit config, control
per-output MIDI clock start/stop, push OTA updates. No Link SDK, no licensing question — plain
HTTP + Bonjour against the protocol `KitchenSync/main/ks_web.cpp` already serves.

## Status

Builds, runs, and is tested. **86 tests, 0 failures.**

Phase 2 landed the whole view layer, TDD throughout (see `tasks/`, tracked with `ordna`):

| | |
|---|---|
| T-001 – T-002 | Builds and launches; the existing suite runs for the first time |
| T-003 – T-008 | Transport button, output cards, device list, detail screen, settings sheet, OTA |
| T-009 – T-010 | Old-firmware degradation; unreachable devices |
| T-012 | The partition test (below) |

**⚠️ The one real gap: nothing has ever spoken to a real device.** Every network test runs the
real `KitchenSyncClient` against a stubbed `URLProtocol`, so URL building, form encoding and
status checking are all exercised — but `KitchenSyncDiscovery` has never seen a live Bonjour
responder, and no request has ever reached hardware. Use `link-devices/tools/linkcli` to get a
unit on the bench and verify for real. That is the highest-value next step.

Still open: **T-011** (firmware-side TXT record — lives in `link-devices`, not here) and
**T-013** (Live Activity — needs scoping; our poll loop is foreground-only, so lock-screen
updates may need push infrastructure).

## Setup

```sh
brew install xcodegen
xcodegen generate
open KitchenSyncApp.xcodeproj
```

`project.yml` is the source of truth. **XcodeGen *generates* `Sources/KitchenSyncApp/Info.plist`
on every run** — hand-edits to that file are silently overwritten. Plist keys go under
`info.properties` in `project.yml`. The generated `.xcodeproj` is gitignored; regenerate it,
don't hand-edit it.

Two Info.plist keys are load-bearing and easy to lose: `NSLocalNetworkUsageDescription` and
`NSBonjourServices`. Without them iOS silently blocks Bonjour browsing *and* `.local`
resolution — discovery finds nothing and every request fails, with no useful error.

## The one thing to understand before changing anything

**The split between live-editable and reboot-required is exactly the `KsLiveEdit` enum's case
list, and it is not guessable from field names.**

- `POST /live` — a partial patch, applied instantly, no reboot. Restricted to `KsLiveEdit`'s
  closed case set.
- `POST /save` — the full form. Persists to NVS and **reboots the device**: it drops out of the
  Link session and all clock output stops for several seconds.

The trap, straight from the firmware: `metro_accent`, `metro_vol` and `metro_voice` are live,
but metronome **enable** is not. `led` enable *is* live, but `follow_beat` enable is not. On the
device's own web page those toggles are the identical component forty pixels apart, and one of
them restarts the box mid-set. Nothing on that screen says so.

This app fixes that, structurally rather than with a warning label:

1. Every control on `DeviceDetailView` routes through a `KsLiveEdit` case, so that screen
   **cannot** reboot the device — there is no case to hand a reboot-only field.
2. Reboot-required settings exist only in `DeviceSettingsSheet`, behind a consequence band, a
   confirmation that names the device, and a `WRITE & REBOOT` key.
3. `LiveRebootPartitionTests` (T-012) asserts that every key `saveFormFields` emits is either
   live-editable or declared in `KsConfig.rebootRequiredFormKeys` — **exactly one, never both,
   never neither.** Add a field without classifying it and the test fails. If firmware later
   makes a field live-safe, this is what tells you, instead of a user finding out on stage.

Passwords are write-only: `/config.json` never returns one, blank means "keep current", and
`WifiCredentialEdit` is keyed by slot `id` — never array position, or you overwrite the wrong
saved network.

## Transport is quantized

Play **arms** and fires on the next bar line; Stop is immediate. The device computes
`TransportLaunchState` (stopped / armed / running) and reports it in `/status.launch[N]` every
poll. **Never predict the armed→running transition client-side.**

The armed state blinks at beat rate (`60/bpm` — the firmware's own cadence), because it is the
only evidence a tap registered and it may persist for most of a bar. Hard-edged, not a soft
throb: a throb reads as "loading", and armed is a cocked hammer.

## Protocol contract

Every client method maps 1:1 to a route in `KitchenSync/main/ks_web.cpp`.

| Endpoint | Method | Client |
|---|---|---|
| `/status` | GET | `fetchStatus()` — telemetry. Poll it; never cache it |
| `/config.json` | GET | `fetchConfig()` — actual settings (P4-041). **404s on firmware older than 2026-07-14** |
| `/live` | POST | `postLive(_:)` — partial patch, live-safe fields only |
| `/save` | POST | `postSave(_:wifiEdits:)` — full form, persists + **reboots** |
| `/transport?out=N\|all&play=1\|0` | POST | `postTransport(output:play:)` — quantized start/stop |
| `/update` | POST | `uploadFirmware(_:)` — raw `.bin`, dual-slot OTA |

Discovery browses `_http._tcp` and filters by the `kitchensync-*` hostname prefix — the firmware
advertises no distinguishing TXT record (T-011), so this is a heuristic with a real
false-positive.

## Design

`docs/design/2026-07-14-view-layer-design-direction.md` — derived by reading the device's own web
UI rather than inventing a look. The palette lives in `link-devices/X32Link/ui_chrome.c` (which
`ks_web.cpp` includes as `%CSS%`), not in `ks_web.cpp`: eight colors, three faces.

## Tests

```sh
xcodebuild -project KitchenSyncApp.xcodeproj -scheme KitchenSyncApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Network tests run the **real** `KitchenSyncClient` against `StubURLProtocol` — mocking the client
itself would only assert that our fake calls our fake. Fixtures are built from the firmware's
actual `snprintf` / `ks_config_set()` output, not plausible-looking JSON.
