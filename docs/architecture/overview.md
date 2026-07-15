# KitchenSync iOS — Architecture Overview

> **Status:** living document. Describes how this app is structured and *why*. The
> platform-wide decisions it obeys (firmware owns time, the config lifecycle, the
> wire contract) live in the firmware repo and are **referenced, not restated**, so
> there is one source of truth. See
> [`link-devices/docs/adr/`](https://github.com/ericdahl-dev/link-devices/tree/master/docs/adr)
> and [`../decisions/`](../decisions/).

## 1. What this app is

A companion iOS app for the KitchenSync / X32Link device fleet: discover units on
the LAN, show live status, edit config, control per-output MIDI clock start/stop,
and push OTA updates. It talks to devices over **plain HTTP + Bonjour** — no Ableton
Link SDK, no licensing question.

It is a **control plane**: it sends intent and renders reported state, and it owns
no musical time. That is a platform decision
([ADR-0011](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0011-control-plane-boundary.md)),
not an app-local one; this app is one of its clients (the on-device web UI is
another).

## 2. Layering

Standard MVVM, with the discipline that **logic that decides something lives on a
model as a pure function**, not inside a `View`:

```
Views (SwiftUI)              DeviceListView, DeviceDetailView, *Sheet, cards, controls
   │  observe
ViewModels                   DeviceListViewModel, DeviceDetailViewModel
   │  call                   (poll loop, apply intent, no local time)
Networking / Discovery       KitchenSyncClient (HTTP), KitchenSyncDiscovery (Bonjour)
   │  decode / mirror
Models (pure)                KsStatus, KsConfig, KsLiveEdit, TransportLaunchState,
                             KsStatusTempoSource, TransportAppearance, DeviceMatch …
```

- **Models are pure and testable.** State→appearance mapping, tempo-source labelling,
  transport summary, and device-match logic are pure functions with unit tests —
  never buried in a view.
- **The firmware is the source of truth for the models.** Field names, value grammars,
  and option strings are copied from the firmware, not invented; each Swift type's doc
  comment names the C symbol it mirrors. Where Swift and firmware disagree, the
  firmware is right.

## 3. Discovery

`KitchenSyncDiscovery` browses Bonjour `_http._tcp` and delegates the match decision
to the pure `DeviceMatch`:

- When the device's `dev` TXT record is present, it is authoritative
  (`dev == "kitchensync"`; the `x32link` product is excluded).
- When TXT is absent (older firmware), fall back to a hostname prefix
  (`kitchensync-*` / `kstouch-*`) — a heuristic that can false-positive on a
  stranger's device.

See [`firmware-contract.md`](firmware-contract.md) for the wire details and the
current TXT-record state.

## 4. Musical time stays on the device

This app deliberately owns no clock (see
[ADR-0011](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0011-control-plane-boundary.md)):

- No `Timer` / `CADisplayLink` / `DispatchSourceTimer` anywhere in `Sources/`.
  Polling is a plain `Task` sleep loop.
- Transport actions do **not** mutate local state or predict the armed→running
  transition — the device computes launch state and reports it every poll.
- The effective BPM shown is the firmware's (`status.bpm`).
- The only local `60/bpm` arithmetic drives a cosmetic beat-blink at the *reported*
  cadence; it is not phase-locked and sends nothing over the wire.
- **Tap tempo** is computed locally as a *value* and sent once as a `bpm` field —
  never as tap events over the network (local timing avoids WiFi jitter). Optimistic
  UI is cleared once the device's reported tempo converges.

## 5. Configuration lifecycle — enforced structurally

The live-safe vs reboot-required split is a platform invariant
([ADR-0012](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0012-configuration-lifecycle.md)):
`/live` applies live-safe fields instantly; `/save` reboots, dropping the device out
of the Link session. Because the split is **not guessable from field names**, this
app enforces it structurally rather than with a warning label — see the app-local
decision [`../decisions/IOS-0001-structural-live-reboot-enforcement.md`](../decisions/IOS-0001-structural-live-reboot-enforcement.md).

## 6. Testing

- **TDD is the rule** — tests first, never backfilled.
- Network tests run the **real** `KitchenSyncClient` against a `StubURLProtocol`, with
  fixtures built from the firmware's actual `snprintf` / `ks_config_set()` output —
  not plausible-looking JSON. Mocking the client would only assert that a fake calls a
  fake.
- `LiveRebootPartitionTests` enforces the config-lifecycle partition (§5) in CI.

## 7. Known gap

**Nothing has ever spoken to a real device.** Every network test runs against a stub;
`KitchenSyncDiscovery` has never seen a live Bonjour responder. Treat the protocol
layer as verified against a *reading* of the firmware, not against the firmware. Use
`link-devices/tools/linkcli` to get a unit on the bench and verify for real — the
highest-value next step.

## 8. See also

- [`firmware-contract.md`](firmware-contract.md) — the client's view of the wire contract.
- [`../decisions/`](../decisions/) — app-local decisions + pointers to platform ADRs.
- Firmware source of truth:
  [`link-devices/docs/contracts/firmware-http-contract.md`](https://github.com/ericdahl-dev/link-devices/blob/master/docs/contracts/firmware-http-contract.md).
