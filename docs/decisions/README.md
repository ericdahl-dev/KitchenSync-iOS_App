# Decision records — KitchenSync iOS

This app is one control plane in the KitchenSync platform. To keep a single source
of truth, decisions are split:

- **Platform-wide decisions** — anything true of the whole platform (firmware owns
  time, the config lifecycle, the wire contract, repository direction) — live in the
  firmware repo's ADR log:
  [`link-devices/docs/adr/`](https://github.com/ericdahl-dev/link-devices/tree/master/docs/adr).
  This app *follows* them and references them; it does **not** copy or renumber them.
  Most relevant here:
  - [ADR-0010](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0010-kitchensync-platform-identity.md) — platform identity.
  - [ADR-0011](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0011-control-plane-boundary.md) — firmware owns time; apps are control planes.
  - [ADR-0012](https://github.com/ericdahl-dev/link-devices/blob/master/docs/adr/0012-configuration-lifecycle.md) — live-safe vs reboot-required.

- **App-local decisions** — things true only of this Swift app — live here, numbered
  `IOS-NNNN` so they never collide with, or masquerade as, the platform ADR sequence.

> **Why not a local `0001-firmware-owns-timing.md`?** "Firmware owns timing" is a
> *platform* decision; duplicating it here would fork the source of truth and let the
> two copies drift. It lives once, as platform ADR-0011, and is referenced.

## Index

| ID | Title | Status |
|---|---|---|
| [IOS-0001](IOS-0001-structural-live-reboot-enforcement.md) | The app structurally prevents a reboot-on-live edit | accepted |
