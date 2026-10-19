# Publishing an update

1. Make a feature/fix branch. Implement and test the change; merge the tested result into `main`.
2. Change `MARKETING_VERSION` in both target configurations in `Pasteback.xcodeproj/project.pbxproj`; increment `CURRENT_PROJECT_VERSION` too.
3. Run tests and `bash scripts/package.sh`. Check the DMG, both binary architectures, version, signature and checksums. For public production distribution, sign with Developer ID and notarize the app before packaging. The current script produces an ad-hoc testing build only.
4. Commit and push source changes. Do not commit `Build/`, `.app`, database files, personal screenshots, certificates or keys.
5. On GitHub, draft a release using a matching tag, e.g. `v0.1.1`, targeting the tested commit on `main`.
6. Upload the version’s universal DMG, ZIP and `SHA256SUMS.txt`; write release notes and mention signing/notarization status. Verify attachments before publishing.
7. Publish as a stable release and make it the latest. The current update checker ignores draft/prerelease versions and compares numeric two- or three-part versions.
8. In an older installation, choose **Check for Updates…** and verify that it offers the new release page. Users download and replace the app; history stays in Application Support.

Do not overwrite an old version’s assets with different bytes. Publish a new version/tag when the build changes. The updater currently supports notification/download-page opening, not automatic installation or a Sparkle update feed.
