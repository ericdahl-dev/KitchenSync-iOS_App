# KitchenSync iOS

Companion iOS app for the [`link-devices`](https://github.com/ericdahl-dev/link-devices)
KitchenSync/X32Link fleet. Phase 1 of the plan in that repo's
[`docs/plans/2026-07-14-ios-kitchensync-app-plan.md`](https://github.com/ericdahl-dev/link-devices/blob/master/docs/plans/2026-07-14-ios-kitchensync-app-plan.md):
discover KitchenSync units on the LAN, show live status, edit config, control
per-output MIDI clock start/stop, push OTA updates. No Link SDK, no licensing
question — plain HTTP + Bonjour against the protocol `KitchenSync/main/ks_web.cpp`
already serves.

## ⚠️ Status: scaffold only, unbuilt

This was written in a headless container with **no Xcode/Swift toolchain
available** — nothing here has been compiled or run. The next session (on a
real Mac) should expect to spend its first stretch fixing whatever the
compiler finds, not just resuming feature work.

**Built and reasoned through carefully, but not compiled:**
- `Models/` — `KsConfig`, `KsStatus`, `KsLiveEdit`, `TransportLaunchState`,
  `TransportTapIntent`, `KitchenSyncDevice`
- `Networking/` — `KitchenSyncClient`, `FormURLEncoding`, `ManualDeviceStore`
- `Discovery/` — `KitchenSyncDiscovery` (Bonjour)
- `ViewModels/` — `DeviceListViewModel`
- `Tests/` — see below

**Not started yet:**
- `DeviceDetailViewModel` (per-device status polling + edit dispatch)
- Every SwiftUI view — `DeviceListView`, `DeviceDetailView`, `OutputCardView`,
  `TransportButton`, `AddDeviceView`, a device-settings (reboot-required) sheet,
  a firmware-update sheet
- The `@main` `App` entry point — **the project will not build yet**, there's
  no root view to launch

## Setup

```sh
brew install xcodegen
xcodegen generate
open KitchenSyncApp.xcodeproj
```

`project.yml` is the source of truth for the Xcode project (targets, deployment
target iOS 17, bundle ID `dev.ericdahl.kitchensync`); the generated
`.xcodeproj` is gitignored — regenerate it, don't hand-edit it.

## Tests

`Tests/KitchenSyncAppTests/` covers the pure logic test-first (TDD): each file
was written before or alongside its implementation, then traced by hand
against the corresponding `link-devices` firmware source since there's no
`swift test` available here. **Run them for real as the first thing you do**
locally — a hand-traced test is not a passing test.

- `TransportTapIntentTests` — written first; `TransportTapIntent` didn't exist
  before this file did.
- `FormURLEncodingTests`, `KsLiveEditTests`, `KsStatusDecodingTests`,
  `KsConfigTests` — backfilled for logic written earlier in the same session,
  fixtures hand-built against the firmware's actual `snprintf`/`ks_config_set()`
  output rather than "plausible JSON."

## Protocol contract

Every network call maps 1:1 to a route in `link-devices/KitchenSync/main/ks_web.cpp`:

| Endpoint | Method | Client method |
|---|---|---|
| `/status` | GET | `KitchenSyncClient.fetchStatus()` — telemetry (bpm, peers, playing, per-output launch state, tick/phase health) |
| `/config.json` | GET | `KitchenSyncClient.fetchConfig()` — actual current settings ([P4-041](https://github.com/ericdahl-dev/link-devices/blob/master/tasks/P4-041.md), added this session; **a device needs firmware built after 2026-07-14 for this to exist** — older units will 404 on it while everything else still works) |
| `/live` | POST | `KitchenSyncClient.postLive(_:)` — partial patch, live-safe fields only (`KsLiveEdit`'s closed case set), no reboot |
| `/save` | POST | `KitchenSyncClient.postSave(_:wifiEdits:)` — full form, persists + reboots |
| `/transport?out=N\|all&play=1\|0` | POST | `KitchenSyncClient.postTransport(output:play:)` — quantized per-output MIDI clock start/stop (ESP-011); poll `/status.launch[N]` to see it arm then run |
| `/update` | POST | `KitchenSyncClient.uploadFirmware(_:)` — raw `.bin`, OTA into the inactive slot |

Discovery browses `_http._tcp` via `NWBrowser` and filters by the `kitchensync-*`
hostname prefix (the firmware advertises no more specific service type yet —
see the plan doc for the small TXT-record fix that would make this exact
instead of prefix-matched).

## Next steps

1. `xcodegen generate`, open in Xcode, fix compile errors.
2. Run the existing tests for real.
3. `DeviceDetailViewModel` + the view layer, starting with `TransportButton`
   (dark/blinking/solid, driven by `TransportLaunchState` + `TransportTapIntent`
   — both already written and tested) and `OutputCardView` wrapping it, since
   per-output MIDI clock start/stop was the most recently requested piece.
4. `KitchenSyncApp.swift` (`@main`) once there's a root view to launch.
