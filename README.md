# Pasteback

Find the text, code and images you copied — right from your Mac’s menu bar.

[Download for Mac](https://github.com/JohnSmitho91p8/Pasteback/releases/latest) · [中文使用指南](Pasteback功能说明.md) · [Privacy](PRIVACY.md)

## Features

- Search text, code, images and file references, with your latest copies first.
- Preview text and images; copy a whole item or select just the text you need.
- Read C++ with syntax highlighting, line numbers, a monospaced font and horizontal scrolling. Original whitespace is preserved; tabs display at four spaces. Choose Automatic, Plain text or C++ for each preview.
- Use ⌘1–9 for the first nine search results. Copy files as objects or paths (⌥↩).
- Optionally paste into the previous app with Return or a double-click; Accessibility permission is required and the default remains copy-only.
- Pin useful items, delete individual entries or clear your history.
- Browse history and full previews side by side in a resizable window, with a persistent sidebar for Settings. Move, minimize or use full screen; your window size and position are remembered.
- Choose English, 简体中文, 日本語, Français, Deutsch or 한국어.
- Check for updates and install new versions inside the app.

## Install

Requires **macOS 14 or later**. Supports Apple silicon and Intel Macs.

1. Download the latest **DMG** from the link above.
2. Open it and drag **Pasteback** into **Applications**.
3. Launch Pasteback and click its menu-bar icon, or press **⌘⇧V**.

The current testing release is not Apple notarized. macOS may block the first launch.

## Use

Copy text, code or an image in another app, then open Pasteback to find it. Select an item to preview it and choose **Copy All**, or select part of its text and press **⌘C**. Switch to your destination app and press **⌘V** to paste.

For a screenshot, use **⌃⇧⌘4** to copy a selection or **⌃⇧⌘3** to copy the screen. Screenshots saved only as files are not added to clipboard history.

Use the sidebar to switch between history and Settings. **Back to History** or **⌘[** returns to your previous search and selection. Closing the window keeps recording active; reopen it from the menu bar or **⌘⇧V**.

For file references, right-click to copy paths, copy names or reveal files in Finder. Only references are saved; deleting history never deletes original files. Moved or deleted files must be copied again. Paths can use shell quoting (default), raw text or @ references.

## Updates

Choose **Check for Updates…** in Settings or the menu-bar menu, then follow the prompts to install and restart. Your history is preserved. Users on 0.1.x need to install a current version manually once.

## Privacy

Clipboard history stays on your Mac and is not uploaded or synced. You can pause recording and exclude apps. History is not encrypted by Pasteback, and unmarked passwords may still be recorded. File references include names and local paths. Automatic pasting is optional and falls back to copying when permission, target focus or secure input prevents pasting.

Checking for and downloading updates connects to GitHub without sending clipboard contents. See the [privacy details](PRIVACY.md).

## License

Pasteback is open source under the [MIT License](LICENSE). Third-party components retain their respective licenses.
