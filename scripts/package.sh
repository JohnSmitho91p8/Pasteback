#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
version="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' Pasteback.xcodeproj/project.pbxproj | head -1)"
derived_path="${PASTEBACK_DERIVED_DATA:-${TMPDIR:-/tmp}/PastebackPackageBuild}"
xcodebuild -project Pasteback.xcodeproj -scheme Pasteback -configuration Release -derivedDataPath "$derived_path" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
package_dir="$project_root/Build/Release-$version"
mkdir -p "$package_dir/staging"
ditto "$derived_path/Build/Products/Release/Pasteback.app" "$package_dir/staging/Pasteback.app"
xattr -cr "$package_dir/staging/Pasteback.app"
codesign --force --deep --sign - "$package_dir/staging/Pasteback.app"
codesign --verify --deep --strict "$package_dir/staging/Pasteback.app"
architectures="$(lipo -archs "$package_dir/staging/Pasteback.app/Contents/MacOS/Pasteback")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]]
ln -sfn /Applications "$package_dir/staging/Applications"
cp README.md "$package_dir/staging/README.md"
hdiutil create -volname "Pasteback $version" -srcfolder "$package_dir/staging" -ov -format UDZO "$package_dir/Pasteback-$version-universal.dmg"
ditto -c -k --keepParent "$package_dir/staging/Pasteback.app" "$package_dir/Pasteback-$version-universal.zip"
(cd "$package_dir" && shasum -a 256 "Pasteback-$version-universal.dmg" "Pasteback-$version-universal.zip" > SHA256SUMS.txt)
printf 'Artifacts: %s\n' "$package_dir"
