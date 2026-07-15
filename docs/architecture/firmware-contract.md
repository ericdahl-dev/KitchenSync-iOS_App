# Firmware Contract — client view

> **The firmware repository owns this contract.** The authoritative document is
> [`link-devices/docs/contracts/firmware-http-contract.md`](https://github.com/ericdahl-dev/link-devices/blob/master/docs/contracts/firmware-http-contract.md).
> This file records only how *this app* maps onto it and the caveats specific to the
> Swift client. When the two disagree, the firmware doc — and ultimately the firmware
> source — wins. Do not duplicate field grammars here; read them from the firmware.

## Client ↔ route mapping

Every `KitchenSyncClient` method targets exactly one registered firmware route
(`ks_web.cpp` `ks_web_start`):

| `KitchenSyncClient` method | Route | Notes |
|---|---|---|
| `fetchStatus()` | `GET /status` | Telemetry. Poll ~1 Hz; never cache. |
| `fetchConfig()` | `GET /config.json` | Persisted settings. 404s on firmware older than 2026-07-14. |
| `postLive(_:)` | `POST /live` | Live-safe fields only (see below). No reboot. |
| `postSave(_:wifiEdits:)` | `POST /save` | Full form; persists and **reboots** the device. |
| `postTransport(output:play:)` | `POST /transport?out=<N>\|all&play=1\|0` | Quantized Start/Stop. |
| `uploadFirmware(_:)` | `POST /update` | Raw `.bin` body (`application/octet-stream`), dual-slot OTA. |

The firmware also serves `GET /` (the human web UI) and `GET /update` (the upload
page); this app uses `/config.json` instead of scraping HTML and does not call those.

## Invariants this client must uphold

These are platform invariants, not app choices — see the firmware contract doc and
the referenced ADRs:

1. **Own no musical time.** Send intent, render reported state. Never predict the
   quantized armed→running transport transition; never run a local beat/phase clock.
   ([ADR-0011](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0011-control-plane-boundary.md))
2. **Keep the live/reboot partition disjoint and exhaustive.** `KsLiveEdit` is a
   closed case set (only live-safe fields reach `/live`); `KsConfig.rebootRequiredFormKeys`
   is its complement; `LiveRebootPartitionTests` fails CI if any save field is
   unclassified or double-classified. Do not weaken any of the three defenses.
   ([ADR-0012](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0012-configuration-lifecycle.md),
   [IOS-0001](../decisions/IOS-0001-structural-live-reboot-enforcement.md))
3. **Passwords are write-only.** `/config.json` never returns one; blank means "keep
   current". WiFi edits are keyed by slot `id`, never array position.

## Discovery caveat (current)

- The firmware advertises a **generic** `_http._tcp` on port 80 and disambiguates with
  a `dev`/`model`/`target`/`fw` **TXT record** (firmware ESP-031/ESP-037).
- `DeviceMatch` prefers the TXT `dev` key and falls back to a hostname prefix when TXT
  is absent.
- **Known skew (2026-07):** some code comments in this app assume the TXT record is
  absent "for every unit in the field," but current firmware emits it. Treat TXT as
  present on up-to-date firmware; the hostname fallback covers older units. This is a
  contract-mirroring drift to reconcile — exactly the kind of thing a future
  `ks-protocol` would remove
  ([roadmap](https://github.com/ericdahl-dev/link-devices/blob/master/docs/architecture/repository-roadmap.md)).

## How to keep this honest

- Each Swift type's doc comment names the C symbol it mirrors — keep those current.
- Build test fixtures from the firmware's real serialized output, not hand-written
  JSON.
- The one true end-to-end verification is a real device on the bench via
  `link-devices/tools/linkcli`; the stub-based suite verifies a *reading* of the
  firmware, not the firmware.
