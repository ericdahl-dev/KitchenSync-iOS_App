# Shipping the app to a device owner (TestFlight)

How a customer like Dan gets the KitchenSync app onto their phone once you ship them a unit.
TestFlight is the right tool while the app is pre-App-Store; the App Store is the eventual home
once you're shipping to more than a handful of people (a free companion app anyone can download,
no per-person invites, no 90-day expiry).

The bundle ID (`dev.ericdahl.kitchensync`) and team (`5HR8E5CWR7`) are already set in
`project.yml`; automatic signing mints the distribution cert on the first archive. So the moving
parts are: build the `.ipa`, upload it, invite the tester.

## One-time setup (per app, per machine)

1. **Xcode account.** Xcode > Settings > Accounts: sign in with the Apple ID that owns the
   Developer Program membership for team `5HR8E5CWR7`. This is what lets `-allowProvisioningUpdates`
   create the Apple Distribution cert + App Store profile without hand-wrangling.
2. **Register the app in App Store Connect.** appstoreconnect.apple.com > Apps > **+** > New App:
   iOS, the `dev.ericdahl.kitchensync` bundle ID (register it under Certificates, IDs & Profiles
   first if it isn't there), an app name, primary language, SKU. This app record only has to be
   created once; every build uploads into it.
3. **(For scripted upload) an API key.** App Store Connect > Users and Access > **Keys** > **+**.
   Give it "App Manager" access. Note the **Key ID** and the **Issuer ID** (top of the page), and
   download the `AuthKey_<KEYID>.p8` **once** (you can't re-download it). Put it in
   `~/.appstoreconnect/private_keys/`. This is optional — the first time, Xcode's Organizer GUI is
   easier (see below).

## Build a TestFlight build

```sh
Tools/build-testflight.sh            # archive + export build/testflight/export/*.ipa
Tools/build-testflight.sh --upload   # ...and upload (needs ASC_KEY_ID / ASC_ISSUER_ID env + the .p8)
```

The build number is the git commit count, so it climbs on its own — but TestFlight rejects a
**re-used** build number, so commit between uploads (or bump `CURRENT_PROJECT_VERSION`).

**First-timer path (no API key):** run `Tools/build-testflight.sh` (no `--upload`), then open the
`.xcarchive` in **Xcode > Window > Organizer > Distribute App > App Store Connect > Upload**. Xcode
handles cert creation, upload, and shows any validation errors inline. Once you've done it once and
have the API key, `--upload` makes it one command.

## Invite Dan

App Store Connect > your app > **TestFlight**:

- Wait for the build to finish **processing** (~5–15 min after upload; you get an email).
- Add Dan as a tester. **Internal** (needs him on your team, no review, instant) or **External**
  (by email; the first external build needs a one-time **Beta App Review**, usually cleared within
  a day). For shipping to customers, external is normal.
- Dan installs Apple's **TestFlight** app from the App Store, opens your email invite (or a **public
  link** you generate under External Testing — anyone with the link can join, no email needed), and
  the build installs. Updates you push later just appear for him.

## Gotchas

- **Builds expire after 90 days.** Push a fresh build periodically or Dan's copy stops opening. This
  is the main reason to move to the App Store once you're shipping in volume.
- **Local Network permission.** On first launch iOS prompts for it; if Dan denies it, the app finds
  no devices at all (Bonjour + `.local` both die silently). Worth a line in the ship note to him.
- External testers cap at 10,000; internal at 100.
