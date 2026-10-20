#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
: "${SPARKLE_BIN:?Set SPARKLE_BIN to the official Sparkle 2.10.0 bin directory}"
version="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' Pasteback.xcodeproj/project.pbxproj | head -1)"
package_dir="$project_root/Build/Release-$version"
feed_dir="$package_dir/update-feed"
mkdir -p "$feed_dir"
cp "$package_dir/Pasteback-$version-universal.zip" "$feed_dir/"
printf 'Pasteback %s: signed in-app updates. Clipboard history stays on your Mac.\n' "$version" > "$feed_dir/Pasteback-$version-universal.txt"
"$SPARKLE_BIN/generate_appcast" --account Pasteback --maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/JohnSmitho91p8/Pasteback/releases/download/v$version/" "$feed_dir"
printf 'Publish release assets first, then upload unchanged signed feed: %s/appcast.xml\n' "$feed_dir"
