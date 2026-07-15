# IOS-0001. The app structurally prevents a reboot-on-live edit

Date: 2026-07-15
Status: accepted

Implements the client half of platform
[ADR-0012](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0012-configuration-lifecycle.md)
(configuration lifecycle).

## Context

`POST /save` reboots the device, which drops it out of the Link session and stops
all clock output for several seconds — destructive mid-set. `POST /live` applies a
whitelisted set of live-safe fields with no reboot. The dangerous part is that the
split is **not guessable from field names**: metronome *volume* is live but metronome
*enable* is not; `led` enable is live but `follow_beat` enable is not. On the device's
own web page those are the identical toggle forty pixels apart, and one restarts the
box.

A warning label is not enough — it is essentially what the device web page already
has. This app should make the dangerous mistake *unrepresentable*.

## Decision

Enforce the live/reboot partition with three defenses, none of which may be weakened:

1. **`KsLiveEdit` is a closed case set.** It mirrors the firmware's
   `ks_config_live_safe_copy` whitelist. Reboot-only fields (metronome/Follow-Beat
   *enable*, WiFi credentials) have no case, so a caller *cannot* route them to
   `/live` even by mistake. Every control on `DeviceDetailView` goes through a
   `KsLiveEdit` case, so that screen cannot reboot the device.
2. **Reboot-required settings are quarantined** in `DeviceSettingsSheet`, behind a
   consequence band, a confirmation that names the device, and a `WRITE & REBOOT` key.
3. **A partition test keeps the two sets disjoint and exhaustive.**
   `LiveRebootPartitionTests` asserts every key `saveFormFields` emits is either
   live-editable or in `KsConfig.rebootRequiredFormKeys` — exactly one, never both,
   never neither. Add a field without classifying it and CI fails.

## Alternatives considered

- **A warning dialog on reboot-only fields.** Rejected: relies on the user reading it
  mid-set, and does nothing to stop a *developer* wiring a reboot-only control onto the
  live screen. The closed enum makes that a compile-time impossibility.
- **Trust the firmware to ignore reboot-only fields on `/live`.** The firmware does
  drop them (by construction), but silently — the user would see "nothing happened,"
  not "that field needs a reboot." Classifying client-side gives correct UX and
  catches the field at the right layer.
- **A single flat settings screen** (like the device web page). Rejected: it is the
  exact source of the hazard this decision removes.

## Consequences

- Adding a config control forces a lifecycle decision: give it a `KsLiveEdit` case
  (live) or place it in the settings sheet + `rebootRequiredFormKeys` (reboot).
  Skipping the choice fails the partition test.
- If firmware later promotes a field to live-safe, the partition test is what surfaces
  it here, instead of a user discovering it on stage.
- This is the client counterpart to the firmware's construction-level guarantee; both
  halves are required (platform ADR-0012).
