#!/bin/bash
# Input: an app exported by Xcode with Developer ID signing. Never weakens Gatekeeper.
set -euo pipefail
: "${PASTEBACK_SIGNED_APP:?Set the path of the Developer ID-signed Pasteback.app}"
: "${PASTEBACK_NOTARY_PROFILE:?Set an existing notarytool Keychain profile name}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_source="$PASTEBACK_SIGNED_APP"
[[ -d "$app_source" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_source/Contents/Info.plist")" == com.pasteback.mac ]]
codesign --verify --deep --strict "$app_source"
codesign -dv --verbose=4 "$app_source" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:'
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_source/Contents/Info.plist")"
output_dir="$project_root/Build/Notarized-$version"
[[ ! -e "$output_dir" ]] || { echo 'Output already exists. Use a fresh version or retain and rename the old output.' >&2; exit 1; }
mkdir -p "$output_dir"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/PastebackNotarize.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_source" "$staging_dir/Pasteback.app"
ditto --norsrc --noextattr -c -k --keepParent "$staging_dir/Pasteback.app" "$staging_dir/notarization.zip"
xcrun notarytool submit "$staging_dir/notarization.zip" --keychain-profile "$PASTEBACK_NOTARY_PROFILE" --wait --output-format json > "$output_dir/notarization.json"
/usr/bin/python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted"' "$output_dir/notarization.json"
xcrun stapler staple "$staging_dir/Pasteback.app"
xcrun stapler validate "$staging_dir/Pasteback.app"
spctl --assess --type execute --verbose "$staging_dir/Pasteback.app"
rm "$staging_dir/notarization.zip"
ditto --norsrc --noextattr -c -k --keepParent "$staging_dir/Pasteback.app" "$output_dir/Pasteback-$version-universal.zip"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "Pasteback $version" -srcfolder "$staging_dir" -ov -format UDZO "$output_dir/Pasteback-$version-universal.dmg"
xcrun notarytool submit "$output_dir/Pasteback-$version-universal.dmg" --keychain-profile "$PASTEBACK_NOTARY_PROFILE" --wait --output-format json > "$output_dir/dmg-notarization.json"
/usr/bin/python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted"' "$output_dir/dmg-notarization.json"
xcrun stapler staple "$output_dir/Pasteback-$version-universal.dmg"
xcrun stapler validate "$output_dir/Pasteback-$version-universal.dmg"
(cd "$output_dir" && shasum -a 256 "Pasteback-$version-universal.dmg" "Pasteback-$version-universal.zip" > SHA256SUMS.txt)
printf 'Notarized artifacts: %s\nSign a new Sparkle feed for these exact bytes before publishing.\n' "$output_dir"
