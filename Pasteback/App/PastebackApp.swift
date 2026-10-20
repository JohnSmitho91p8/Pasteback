import SwiftUI
import AppKit
import Carbon

@main struct PastebackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var dragOffset: NSPoint?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let point = event.locationInWindow
            let header = NSRect(x: 0, y: frame.height - 66, width: frame.width - 48, height: 66)
            if header.contains(point) {
                dragOffset = point
                makeKeyAndOrderFront(nil)
                return
            }
        case .leftMouseDragged:
            if let offset = dragOffset {
                let screenPoint = convertPoint(toScreen: event.locationInWindow)
                setFrameOrigin(NSPoint(x: screenPoint.x - offset.x, y: screenPoint.y - offset.y))
                return
            }
        case .leftMouseUp:
            if dragOffset != nil { dragOffset = nil; return }
        default: break
        }
        super.sendEvent(event)
    }

}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store: ClipStore!
    var status: NSStatusItem!
    var panel: HistoryPanel!
    var preferences: NSWindow?
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
        panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 480), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = true; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = HistoryView(store: store, primary: { [weak self] item, mode in await self?.perform(item, mode: mode) ?? false }, close: { [weak self] in self?.panel.orderOut(nil) }, settings: { [weak self] in self?.showPreferences() })
        let host = NSHostingView(rootView: root.clipShape(RoundedRectangle(cornerRadius: 16)))
        panel.contentView = host
        panel.delegate = self
        if let saved = UserDefaults.standard.string(forKey: "panelOrigin") {
            panel.setFrameOrigin(NSPointFromString(saved))
        }
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
    @objc private func languageChanged() { preferences?.title = tr("Pasteback 设置") }
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
        if !panel.isVisible { PasteAction.shared.rememberTarget(NSWorkspace.shared.frontmostApplication) }
        preferences?.orderOut(nil)
        if panel.isVisible { panel.orderOut(nil); return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main!
        let frame = screen.visibleFrame
        if UserDefaults.standard.string(forKey: "panelOrigin") == nil || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 210, y: frame.midY - 180))
        }
        store.poll()
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "panelOrigin")
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
        preferences?.orderOut(nil)
        if !panel.isVisible { toggle() }
        else { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === preferences else { return }
        showHistory()
    }
    @objc func showPreferences() {
        panel.orderOut(nil)
        if preferences == nil {
            preferences = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            preferences?.title = tr("Pasteback 设置"); preferences?.isReleasedWhenClosed = false
            preferences?.delegate = self
            preferences?.contentView = NSHostingView(rootView: PreferencesView(back: { [weak self] in self?.showHistory() }, store: store)); preferences?.center()
        }
        NSApp.activate(ignoringOtherApps: true); preferences?.makeKeyAndOrderFront(nil)
    }
}
