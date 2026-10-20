#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
version="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' Pasteback.xcodeproj/project.pbxproj | head -1)"
derived_path="${PASTEBACK_DERIVED_DATA:-${TMPDIR:-/tmp}/PastebackPackageBuild}"
xcodebuild -project Pasteback.xcodeproj -scheme Pasteback -configuration Release -derivedDataPath "$derived_path" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
package_dir="$project_root/Build/Release-$version"
mkdir -p "$package_dir"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/PastebackRelease.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$derived_path/Build/Products/Release/Pasteback.app" "$staging_dir/Pasteback.app"
xattr -cr "$staging_dir/Pasteback.app"
codesign --force --deep --sign - "$staging_dir/Pasteback.app"
codesign --verify --deep --strict "$staging_dir/Pasteback.app"
architectures="$(lipo -archs "$staging_dir/Pasteback.app/Contents/MacOS/Pasteback")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]]
ln -sfn /Applications "$staging_dir/Applications"
cp README.md "$staging_dir/README.md"
hdiutil create -volname "Pasteback $version" -srcfolder "$staging_dir" -ov -format UDZO "$package_dir/Pasteback-$version-universal.dmg"
ditto --norsrc --noextattr -c -k --keepParent "$staging_dir/Pasteback.app" "$package_dir/Pasteback-$version-universal.zip"
(cd "$package_dir" && shasum -a 256 "Pasteback-$version-universal.dmg" "Pasteback-$version-universal.zip" > SHA256SUMS.txt)
verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/PastebackVerify.XXXXXX")"
ditto -x -k "$package_dir/Pasteback-$version-universal.zip" "$verify_dir"
codesign --verify --deep --strict "$verify_dir/Pasteback.app"
rm -rf "$verify_dir"
printf 'Artifacts: %s\n' "$package_dir"
