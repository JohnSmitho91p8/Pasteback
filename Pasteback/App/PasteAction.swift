import AppKit
import ApplicationServices
import Carbon
import Observation

@MainActor @Observable final class PasteAction {
    static let shared = PasteAction()
    private(set) var enabled = UserDefaults.standard.bool(forKey: "autoPaste")
    private var target: NSRunningApplication?
    private var targetGeneration = 0
    private var notices = Set<String>()
    static let activationDelay: Duration = .milliseconds(90)

    func rememberTarget(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { target = nil; targetGeneration += 1; return }
        target = app; targetGeneration += 1
    }
    static func allowed(enabled: Bool, trusted: Bool, secureInput: Bool, targetValid: Bool) -> Bool {
        enabled && trusted && !secureInput && targetValid
    }
    func setEnabled(_ value: Bool) {
        if !value { persist(false); return }
        guard AXIsProcessTrusted() else {
            persist(false)
            let alert = NSAlert()
            alert.messageText = tr("自动粘贴需要辅助功能权限")
            alert.informativeText = tr("权限仅用于把选中内容粘贴到原应用。请在系统设置授权后重新开启；未授权时仅复制。")
            alert.addButton(withTitle: tr("打开系统设置")); alert.addButton(withTitle: tr("取消"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }
        persist(true); notices.removeAll()
    }
    private func persist(_ value: Bool) { enabled = value; UserDefaults.standard.set(value, forKey: "autoPaste") }
    func pasteIfEnabled(closePanel: () -> Void) async {
        guard enabled else { return }
        guard AXIsProcessTrusted() else {
            persist(false); warnOnce("permission", "辅助功能权限不可用，已恢复只复制。请授权后重新开启自动粘贴。")
            return
        }
        guard !IsSecureEventInputEnabled() else { warnOnce("secure", "检测到安全输入，仅复制，未自动粘贴。"); return }
        guard let target, !target.isTerminated, target.bundleIdentifier != Bundle.main.bundleIdentifier else {
            warnOnce("target", "原应用不可用，内容已复制，请手动粘贴。"); return
        }
        let generation = targetGeneration
        closePanel()
        guard target.activate(options: []) else { warnOnce("target", "原应用不可用，内容已复制，请手动粘贴。"); return }
        try? await Task.sleep(for: Self.activationDelay)
        guard targetGeneration == generation, Self.allowed(enabled: enabled, trusted: AXIsProcessTrusted(), secureInput: IsSecureEventInputEnabled(),
              targetValid: !target.isTerminated && NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier) else {
            warnOnce("focus", "未能确认粘贴目标或权限，内容已复制，请手动粘贴。"); return
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    private func warnOnce(_ key: String, _ message: String) {
        guard notices.insert(key).inserted else { return }
        let alert = NSAlert(); alert.messageText = tr("已复制"); alert.informativeText = tr(message)
        alert.addButton(withTitle: tr("完成")); NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
}
