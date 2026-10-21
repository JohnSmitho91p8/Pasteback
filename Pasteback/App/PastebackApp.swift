import SwiftUI
import AppKit
import Carbon

@main struct PastebackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor @Observable final class WorkspaceNavigation {
    var settings = false
    var onboarding = false
    var query = ""
    var selection: UUID?
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store: ClipStore!
    var status: NSStatusItem!
    var panel: NSWindow!
    var quickPanel: QuickPanel!
    private var quickGeneration = 0
    private var flashTask: Task<Void, Never>?
    let navigation = WorkspaceNavigation()
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
        panel.contentView = nil
        panel.delegate = self
        quickPanel = QuickPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        quickPanel.title = tr("快捷浮层")
        quickPanel.isFloatingPanel = true; quickPanel.level = .floating
        quickPanel.hidesOnDeactivate = false; quickPanel.isReleasedWhenClosed = false
        quickPanel.isOpaque = false; quickPanel.backgroundColor = .clear; quickPanel.hasShadow = true
        quickPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        quickPanel.dismissPanel = { [weak self] in self?.hideQuick() }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
            Task { @MainActor in delegate.toggle() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        GlobalShortcut.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(copyFeedback), name: .pastebackCopySucceeded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .pastebackLanguageChanged, object: nil)
        if !UserDefaults.standard.bool(forKey: "quickOnboardingComplete") {
            navigation.onboarding = true
            showHistory()
        }
    }
    @objc private func languageChanged() { panel.title = "Pasteback" }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard panel != nil else { return false }
        showHistory()
        return true
    }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: tr("快捷浮层") + "  " + GlobalShortcut.shared.label, action: #selector(toggle), keyEquivalent: "")
            menu.addItem(withTitle: tr("打开完整窗口"), action: #selector(showHistory), keyEquivalent: "")
            menu.addItem(withTitle: store.paused ? tr("继续记录") : tr("暂停记录"), action: #selector(pause), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: tr("设置") + "…", action: #selector(showPreferences), keyEquivalent: ",")
            menu.addItem(withTitle: tr("检查更新…"), action: #selector(checkForUpdates), keyEquivalent: "")
            menu.addItem(withTitle: tr("退出 Pasteback"), action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else { showHistory() }
    }
    @objc func toggle() {
        if quickPanel.isVisible { hideQuick(); return }
        quickGeneration += 1
        PasteAction.shared.rememberTarget(NSWorkspace.shared.frontmostApplication)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let rows = min(store.displayItems.count, 8)
        let height = min(540, max(240, 116 + rows * 54 + (store.items.contains(where: \.pinned) ? 32 : 0)))
        quickPanel.setContentSize(NSSize(width: min(480, area.width - 24), height: min(CGFloat(height), area.height - 24)))
        quickPanel.setFrameOrigin(NSPoint(x: area.midX - quickPanel.frame.width / 2, y: area.midY - quickPanel.frame.height / 2))
        quickPanel.contentView = NSHostingView(rootView: QuickAccessView(store: store, session: UUID(), use: { [weak self] item, mode in await self?.perform(item, mode: mode, quick: true) ?? false }, openWorkspace: { [weak self] in self?.showHistory() }, close: { [weak self] in self?.hideQuick() }))
        store.poll()
        quickPanel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        quickPanel.makeKeyAndOrderFront(nil) // Do not activate Pasteback: the destination app stays active.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.10
            quickPanel.animator().alphaValue = 1
        }
    }
    func hideQuick() { quickGeneration += 1; quickPanel?.orderOut(nil); quickPanel?.contentView = nil }
    private func ensureWorkspace() {
        guard panel.contentView == nil else { return }
        let root = WorkspaceView(quick: { [weak self] in self?.toggle() }, store: store, navigation: navigation, primary: { [weak self] item, mode in await self?.perform(item, mode: mode) ?? false }, close: { [weak self] in self?.closeWorkspace() })
        panel.contentView = NSHostingView(rootView: root)
    }
    private func closeWorkspace() { panel.orderOut(nil); panel.contentView = nil }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { panel.contentView = nil }
    }
    func windowDidMiniaturize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { panel.contentView = nil }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { ensureWorkspace() }
    }
    @objc private func copyFeedback() {
        flashTask?.cancel()
        status.button?.image = NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: tr("已复制"))
        flashTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            self?.status.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Pasteback")
        }
    }
    private var performingAction = false
    func perform(_ item: ClipItem, mode: ClipStore.CopyMode = .content, quick: Bool = false) async -> Bool {
        guard !performingAction else { return false }
        performingAction = true
        defer { performingAction = false }
        let generation = quickGeneration
        let success = await store.copy(item, mode: mode)
        guard !quick || (generation == quickGeneration && quickPanel.isVisible) else { return false }
        if success {
            if quick { hideQuick() }
            await PasteAction.shared.pasteIfEnabled { [weak self] in self?.hideQuick(); self?.closeWorkspace() }
        }
        return success
    }
    @objc func checkForUpdates() { Task { await UpdateChecker.shared.check() } }
    @objc func pause() { store.paused.toggle() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showHistory() {
        hideQuick()
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier { PasteAction.shared.rememberTarget(NSWorkspace.shared.frontmostApplication) }
        navigation.settings = false
        ensureWorkspace()
        NSApp.activate(ignoringOtherApps: true)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
    }
    @objc func showPreferences() {
        hideQuick()
        navigation.settings = true
        ensureWorkspace()
        NSApp.activate(ignoringOtherApps: true)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
    }
}
