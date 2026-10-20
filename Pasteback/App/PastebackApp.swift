import SwiftUI
import AppKit
import Carbon

@main struct PastebackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor @Observable final class WorkspaceNavigation {
    var settings = false
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store: ClipStore!
    var status: NSStatusItem!
    var panel: NSWindow!
    let navigation = WorkspaceNavigation()
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        umask(0o077) // New databases, journals and images are private to this account.
        NSApp.setActivationPolicy(.accessory)
        UpdateChecker.shared.start()
        Task {
            do {
                let container = try await Task.detached(priority: .userInitiated) { try HistoryDatabase.open() }.value
                store = try ClipStore(preparedContainer: container)
                finishLaunching()
            } catch {
                let alert = NSAlert(); alert.messageText = tr("无法打开 Pasteback 历史库"); alert.informativeText = tr("历史升级未完成，已保留原数据，请勿删除本地历史。")
                alert.runModal(); NSApp.terminate(nil)
            }
        }
    }
    private func finishLaunching() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Pasteback")
        status.button?.target = self; status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        panel.title = "Pasteback"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 900, height: 580)
        panel.collectionBehavior = [.fullScreenPrimary]
        panel.tabbingMode = .disallowed
        panel.center()
        if panel.setFrameUsingName("PastebackWorkspace") {
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
        }
        panel.setFrameAutosaveName("PastebackWorkspace")
        let root = WorkspaceView(store: store, navigation: navigation, primary: { [weak self] item, mode in await self?.perform(item, mode: mode) ?? false }, close: { [weak self] in self?.panel.orderOut(nil) })
        panel.contentView = NSHostingView(rootView: root)
        panel.delegate = self
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
            Task { @MainActor in delegate.toggle() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x50415354, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { store.error = tr("⌘⇧V 已被其他应用占用，请使用菜单栏打开。") }
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .pastebackLanguageChanged, object: nil)
        toggle()
    }
    @objc private func languageChanged() { panel.title = "Pasteback" }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard panel != nil else { return false }
        if !panel.isVisible { toggle() }
        return true
    }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: tr("打开 Pasteback  ⌘⇧V"), action: #selector(toggle), keyEquivalent: "")
            menu.addItem(withTitle: store.paused ? tr("继续记录") : tr("暂停记录"), action: #selector(pause), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: tr("设置") + "…", action: #selector(showPreferences), keyEquivalent: ",")
            menu.addItem(withTitle: tr("检查更新…"), action: #selector(checkForUpdates), keyEquivalent: "")
            menu.addItem(withTitle: tr("退出 Pasteback"), action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else { toggle() }
    }
    @objc func toggle() {
        if panel.isMiniaturized { panel.deminiaturize(nil); panel.makeKeyAndOrderFront(nil); return }
        if !panel.isVisible { PasteAction.shared.rememberTarget(NSWorkspace.shared.frontmostApplication) }
        if panel.isVisible { panel.orderOut(nil); return }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        store.poll()
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    private var performingAction = false
    func perform(_ item: ClipItem, mode: ClipStore.CopyMode = .content) async -> Bool {
        guard !performingAction else { return false }
        performingAction = true
        defer { performingAction = false }
        let success = await store.copy(item, mode: mode)
        if success { await PasteAction.shared.pasteIfEnabled { [weak self] in self?.panel.orderOut(nil) } }
        return success
    }
    @objc func checkForUpdates() { Task { await UpdateChecker.shared.check() } }
    @objc func pause() { store.paused.toggle() }
    @objc func quit() { NSApp.terminate(nil) }
    func showHistory() {
        navigation.settings = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
    }
    @objc func showPreferences() {
        navigation.settings = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
    }
}
