#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir="$(mktemp -d "${TMPDIR:-/tmp}/PastebackTests.XXXXXX")"
trap 'rm -rf "$output_dir"' EXIT
sources=(Pasteback/App/Localization.swift Pasteback/Storage/HistorySchema.swift Pasteback/Storage/FileReferences.swift Pasteback/Storage/ClipStore.swift)
python3 Tests/check_localizations.py
for name in CapturePipeline HistoryBehavior LanguageMatching MonitorLatency MonitorImage FileReference; do
    swiftc -O -swift-version 5 "${sources[@]}" "Tests/${name}Tests.swift" -o "$output_dir/$name"
    "$output_dir/$name"
done
swiftc -O -swift-version 5 Pasteback/App/Localization.swift Pasteback/App/PasteAction.swift Tests/PasteActionTests.swift -o "$output_dir/PasteAction"
"$output_dir/PasteAction"
swiftc -O -parse-as-library -swift-version 5 Tests/LegacyHistoryFixture.swift -o "$output_dir/Legacy"
swiftc -O -swift-version 5 Pasteback/Storage/HistorySchema.swift Pasteback/Storage/FileReferences.swift Tests/MigrationTests.swift -o "$output_dir/Migrate"
"$output_dir/Legacy" "$output_dir/fixture-upgrade"
"$output_dir/Migrate" "$output_dir/fixture-upgrade"
"$output_dir/Migrate" "$output_dir/fixture-upgrade" reopen
"$output_dir/Legacy" "$output_dir/fixture-rollback"
"$output_dir/Migrate" "$output_dir/fixture-rollback" rollback
# Signed public release archive tests run after packaging (see prepare-update.sh).
