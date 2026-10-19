# Pasteback

A lightweight clipboard history app for **macOS 14 or later**, built with SwiftUI, AppKit and SwiftData.

[Download the latest release](https://github.com/JohnSmitho91p8/Pasteback/releases/latest) · [中文功能说明](Pasteback功能说明.md) · [Privacy](PRIVACY.md)

## Install

1. Download `Pasteback-0.1.0-universal.dmg` (Apple silicon and Intel) from Releases.
2. Open the disk image and drag **Pasteback.app** into **Applications**.
3. Launch Pasteback. Click its menu-bar icon to open clipboard history; right-click for settings and quit.

**This initial testing build is ad-hoc signed, not Developer ID signed or Apple notarized. macOS Gatekeeper may block it. It is not yet a seamless public distribution build.** Users should review the source and follow their organisation’s security policy; building locally in Xcode is also available. Proper Developer ID signing and notarization remain required for production distribution. No security-disabling command is needed or recommended by this project.

## Features

- Local text and PNG/TIFF image history, saved across launches.
- Newest-first order, search, pin protection, individual deletion and clear controls.
- Full-text preview; copy all or select part of the text and press ⌘C.
- Menu-bar app, draggable panel with remembered position, ⌘⇧V shortcut.
- System language detection and English, Simplified Chinese, Japanese, French, German and Korean.
- Sensitive pasteboard flag filtering, excluded apps and pause recording.
- Background image storage, bounded capture queue and retries for delayed clipboard data.
- Manual **Check for Updates…** in Settings and the menu-bar menu.

Return copies an item; switch to the destination app and press ⌘V. Automatic paste is not implemented.

## Updates

Choose **Check for Updates…**. Pasteback queries this repository’s latest stable release. When a newer version exists, it offers to open that release’s download page. Download the DMG, quit Pasteback, and replace the app in Applications. Local history is kept separately.

This version checks and links to downloads; it does **not** silently download, replace or restart itself. There is no automatic background update check.

## Privacy

History is stored at `~/Library/Application Support/Pasteback/`, outside this source project. Pasteback does not upload clipboard contents or sync history. Local files are restricted to your account, but are **not encrypted by Pasteback**. Unmarked sensitive text may still be recorded. Software running under your account may be able to read history.

The only network feature is an explicit, user-triggered GitHub update check. It sends no clipboard contents, app-source history, device identifier or analytics. GitHub necessarily receives ordinary connection information such as IP address and the app version in the request’s User-Agent. See [PRIVACY.md](PRIVACY.md).

## Screenshot tips

Use Control–Shift–Command–4 (selection) or Control–Shift–Command–3 (screen) to copy a screenshot to the system clipboard. A screenshot saved only as a desktop file is not a clipboard item. Input images are limited to 128 MB and 80 million pixels; text is limited to 2 MB. Over-limit or unavailable data produces a message.

## Build

Open `Pasteback.xcodeproj` in Xcode, choose **Pasteback / My Mac**, then run. No third-party packages or API keys are required.

For a universal local build and distributable archives:

```sh
bash scripts/package.sh
```

The package script creates an ad-hoc signed testing build, a DMG, ZIP and SHA-256 checksums. Build output and runtime history must never be committed.

## Tests

```sh
python3 Tests/check_localizations.py
swiftc -O -swift-version 5 Pasteback/App/Localization.swift Pasteback/Storage/ClipStore.swift Tests/CapturePipelineTests.swift -o /tmp/PastebackCaptureTests
/tmp/PastebackCaptureTests
```

Additional tests cover newest-first sorting, deletion, clearing, language matching, update version comparison and trusted release URLs. Tests use temporary or in-memory data, not the user’s clipboard history.

## Release workflow

See [RELEASING.md](RELEASING.md). Keep changes in small commits, verify the app and tests, update the app version, then publish a matching stable GitHub release tag such as `v0.1.1` with the new DMG/ZIP attached. Existing installations discover it through Check for Updates.

Source is publicly available. An open-source licence has not yet been selected. This is an early testing release, with no guarantee of fitness for sensitive data.
