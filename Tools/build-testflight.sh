#!/usr/bin/env bash
# Build a signed archive and export a TestFlight-ready .ipa (T-020).
#
#   Tools/build-testflight.sh            # archive + export the .ipa
#   Tools/build-testflight.sh --upload   # ...and upload to App Store Connect (needs API key, below)
#
# The first archive on a fresh machine mints the Apple Distribution cert + App Store provisioning
# profile automatically (-allowProvisioningUpdates) -- as long as Xcode is signed into the Apple ID
# that owns team 5HR8E5CWR7 (Xcode > Settings > Accounts). No cert wrangling by hand.
#
# BUILD NUMBER: derived from the git commit count, so every archive gets a unique, monotonically
# increasing CFBundleVersion without hand-editing project.yml. TestFlight rejects a re-used build
# number, so commit (or let CI bump) between uploads. The marketing version (0.1.0) still lives in
# project.yml -- bump it there for a user-facing version change.
#
# UPLOAD (--upload) needs an App Store Connect API key (App Store Connect > Users and Access > Keys):
#   export ASC_KEY_ID=XXXXXXXXXX          # the key's ID
#   export ASC_ISSUER_ID=xxxxxxxx-....    # the issuer UUID at the top of that page
#   place the AuthKey_<ASC_KEY_ID>.p8 in ~/.appstoreconnect/private_keys/ (altool finds it by ID)
# Without a key, skip --upload and use Xcode's Organizer (Window > Organizer > Distribute App) once;
# it does the same upload through a GUI and is the gentler first-timer path.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=KitchenSyncApp
PROJECT=KitchenSyncApp.xcodeproj
OUT=build/testflight
ARCHIVE="$OUT/KitchenSyncApp.xcarchive"
BUILDNUM=$(git rev-list --count HEAD)

echo "==> regenerating the project (project.yml is the source of truth)"
xcodegen generate

echo "==> archiving $SCHEME (Release, build $BUILDNUM)"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILDNUM" \
  -allowProvisioningUpdates

echo "==> exporting the App Store .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Tools/ExportOptions.plist \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates

IPA=$(ls "$OUT"/export/*.ipa 2>/dev/null | head -1)
[ -n "$IPA" ] || { echo "no .ipa produced -- check the export log above" >&2; exit 1; }
echo "==> built: $IPA (build $BUILDNUM)"

if [ "${1:-}" = "--upload" ]; then
  : "${ASC_KEY_ID:?set ASC_KEY_ID to upload}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID to upload}"
  echo "==> uploading to App Store Connect (TestFlight)"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "==> uploaded. It appears under TestFlight after ~5-15 min of processing."
else
  echo "Next: run with --upload (API key set), or open $ARCHIVE in Xcode's Organizer and Distribute App."
fi
