import AppKit
import SwiftUI
import Carbon
import ApplicationServices

final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var dismissPanel: (() -> Void)?
    override func resignKey() { super.resignKey(); dismissPanel?() }
}

@MainActor @Observable final class GlobalShortcut {
    static let shared = GlobalShortcut()
    private(set) var keyCode = UInt32(UserDefaults.standard.object(forKey: "shortcutKey") as? Int ?? kVK_ANSI_V)
    private(set) var modifiers = UInt32(UserDefaults.standard.object(forKey: "shortcutModifiers") as? Int ?? Int(cmdKey | shiftKey))
    private(set) var label = UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⌘⇧V"
    var error: String?
    private var reference: EventHotKeyRef?
    static func valid(_ flags: NSEvent.ModifierFlags) -> Bool { !flags.intersection([.command, .control, .option]).isEmpty }
    @discardableResult func register(code: UInt32, flags: UInt32, label: String) -> Bool {
        if reference != nil && code == keyCode && flags == modifiers { return true }
        var candidate: EventHotKeyRef?
        guard RegisterEventHotKey(code, flags, EventHotKeyID(signature: 0x50415354, id: 1), GetApplicationEventTarget(), 0, &candidate) == noErr else {
            error = tr("快捷键已被占用，保留原快捷键。可使用菜单栏打开。"); return false
        }
        if let reference { UnregisterEventHotKey(reference) }
        reference = candidate; keyCode = code; modifiers = flags; self.label = label; error = nil
        UserDefaults.standard.set(Int(code), forKey: "shortcutKey"); UserDefaults.standard.set(Int(flags), forKey: "shortcutModifiers"); UserDefaults.standard.set(label, forKey: "shortcutLabel")
        return true
    }
    func start() { _ = register(code: keyCode, flags: modifiers, label: label) }
    func reset() { _ = register(code: UInt32(kVK_ANSI_V), flags: UInt32(cmdKey | shiftKey), label: "⌘⇧V") }
    func record(_ event: NSEvent) {
        guard Self.valid(event.modifierFlags), let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            error = tr("请包含 Command、Control 或 Option 修饰键。"); return
        }
        let f = event.modifierFlags; var flags: UInt32 = 0; var display = ""
        if f.contains(.control) { flags |= UInt32(controlKey); display += "⌃" }
        if f.contains(.option) { flags |= UInt32(optionKey); display += "⌥" }
        if f.contains(.shift) { flags |= UInt32(shiftKey); display += "⇧" }
        if f.contains(.command) { flags |= UInt32(cmdKey); display += "⌘" }
        display += characters.uppercased()
        _ = register(code: UInt32(event.keyCode), flags: flags, label: display)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Bindable var shortcut = GlobalShortcut.shared
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) { if !button.recording { button.title = shortcut.label } }
}
final class RecorderButton: NSButton {
    var recording = false
    private var monitor: Any?
    override init(frame: NSRect) {
        super.init(frame: frame); bezelStyle = .rounded; target = self; action = #selector(beginRecording)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func beginRecording() {
        if recording { stop(); return }
        recording = true; title = tr("按下新快捷键，Esc 取消")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode != UInt16(kVK_Escape) { GlobalShortcut.shared.record(event) }
            self.stop(); return nil
        }
    }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false; title = GlobalShortcut.shared.label
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { stop() }; super.viewWillMove(toWindow: newWindow) }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

struct QuickAccessView: View {
    @Bindable var store: ClipStore
    let session: UUID
    var use: (ClipItem, ClipStore.CopyMode) async -> Bool
    var openWorkspace: () -> Void
    var close: () -> Void
    @State private var query = ""
    @State private var selection: UUID?
    @State private var busy = false
    @FocusState private var searching: Bool
    private var matches: [ClipItem] { Array(store.displayItems.filter { item in query.isEmpty || item.text.localizedCaseInsensitiveContains(query) || item.source.localizedCaseInsensitiveContains(query) || item.files.contains { $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) } }.prefix(12)) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("搜索复制过的内容…"), text: $query).textFieldStyle(.plain).focused($searching)
                Button(action: openWorkspace) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.plain).help(tr("打开完整窗口"))
            }.padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                            if index == 0 && item.pinned { Text(tr("固定")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10) }
                            if !item.pinned && index > 0 && matches[index - 1].pinned { Text(tr("最近记录")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 5) }
                            HStack(spacing: 10) {
                                Text(String(index + 1)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 16)
                                if let image = item.imageName { ClipThumbnail(name: image).frame(width: 36, height: 32) }
                                else { Image(systemName: item.files.isEmpty ? "doc.text" : "folder").foregroundStyle(Color.accentColor).frame(width: 26) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.files.first?.name ?? (item.imageName == nil ? String(item.text.prefix(100)) : tr("图片内容"))).lineLimit(1).font(.system(size: 13))
                                    Text(item.source).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.accentColor) }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == item.id ? DesignTokens.ColorStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle()).onTapGesture { selection = item.id; activate(item) }
                                .id(item.id)
                        }
                    }.padding(7)
                    if matches.isEmpty { Text(tr("没有找到相关内容")).foregroundStyle(.secondary).padding(30) }
                }.onChange(of: selection) { _, id in proxy.scrollTo(id) }
            }
            Divider()
            HStack {
                Text(PasteAction.shared.enabled ? tr("↑↓ 选择 · ↩ 粘贴 · Esc 关闭") : tr("↑↓ 选择 · ↩ 复制 · Esc 关闭"))
                Spacer()
                Button(tr("打开完整窗口"), action: openWorkspace).buttonStyle(.plain).keyboardShortcut("o", modifiers: .command)
            }.font(.caption2).foregroundStyle(.secondary).padding(12)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).padding(8).lineLimit(2) }
        }.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { reset() }.onChange(of: session) { reset() }
        .onChange(of: query) { selection = matches.first?.id }
        .onChange(of: matches.map(\.id)) { if !matches.contains(where: { $0.id == selection }) { selection = matches.first?.id } }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if let item = matches.first(where: { $0.id == selection }) { activate(item, mode: press.modifiers.contains(.option) && !item.files.isEmpty ? .paths : .content) }; return .handled
        }
        .onExitCommand(perform: close)
        .background {
            ForEach(1...9, id: \.self) { number in
                Button("") { if matches.indices.contains(number - 1) { activate(matches[number - 1]) } }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }.hidden()
        }
    }
    private func reset() { query = ""; selection = matches.first?.id; searching = true; busy = false }
    private func move(_ delta: Int) { guard !matches.isEmpty else { return }; let i = matches.firstIndex(where: { $0.id == selection }) ?? 0; selection = matches[min(max(0, i + delta), matches.count - 1)].id }
    private func activate(_ item: ClipItem, mode: ClipStore.CopyMode = .content) { guard !busy else { return }; busy = true; Task { _ = await use(item, mode); busy = false } }
}

struct PasteOnboardingView: View {
    var done: () -> Void
    @Bindable private var paste = PasteAction.shared
    @State private var requested = false
    @State private var demo = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 36, weight: .light)).foregroundStyle(Color.accentColor)
            Text(tr("选中，粘贴，继续工作。")).font(.title2.bold())
            Text(tr("快捷浮层帮你找回内容。开启辅助功能后，回车可粘贴回原应用；历史始终只在本机。")).foregroundStyle(.secondary)
            if paste.enabled {
                Label(tr("自动粘贴已就绪"), systemImage: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                if demo {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("操作示例")).font(.caption).foregroundStyle(.secondary)
                        Text("↑↓ → ↩ → ✓").font(.system(.title3, design: .monospaced))
                        Text(tr("呼出浮层，选中内容，回车粘贴，浮层消失。"))
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text(tr("权限仅用于向原应用发送粘贴快捷键，可随时关闭。也可以暂时只复制。")).font(.callout)
                Button(tr("开启自动粘贴")) { requested = true; paste.setEnabled(true); if paste.enabled { demo = true } }.buttonStyle(.borderedProminent).tint(.accentColor)
            }
            HStack {
                Button(tr("暂时只复制")) { done() }
                Spacer()
                Button(tr("开始使用")) { done() }.buttonStyle(.borderedProminent).disabled(!paste.enabled)
            }
        }.padding(30).frame(width: 460)
        .task {
            while !Task.isCancelled {
                if requested && AXIsProcessTrusted() && !paste.enabled { paste.setEnabled(true); demo = true }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
