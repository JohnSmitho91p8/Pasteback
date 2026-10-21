import SwiftUI
import AppKit
import ServiceManagement

private enum ClearAction { case clipboard, all }

struct WorkspaceView: View {
    var quick: () -> Void = {}
    let store: ClipStore
    @Bindable var navigation: WorkspaceNavigation
    var primary: (ClipItem, ClipStore.CopyMode) async -> Bool
    var close: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 28, height: 28)
                    Text("Pasteback").font(.title3.bold())
                }.padding(.vertical, 18)
                Button { navigation.settings = false } label: { Label(tr("你的剪贴板"), systemImage: "doc.on.clipboard").frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                    .buttonStyle(.plain).background(!navigation.settings ? Color.teal.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                Button(action: quick) { Label(tr("快捷浮层"), systemImage: "rectangle.topthird.inset.filled").frame(maxWidth: .infinity, alignment: .leading).padding(10) }.buttonStyle(.plain)
                Spacer()
                Button { navigation.settings = true } label: { Label(tr("设置"), systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                    .buttonStyle(.plain).background(navigation.settings ? Color.teal.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.padding(14).frame(width: 180).background(.regularMaterial)
            Divider()
            ZStack {
                HistoryView(store: store, primary: primary, close: close, settings: { navigation.settings = true })
                    .disabled(navigation.settings).opacity(navigation.settings ? 0 : 1).allowsHitTesting(!navigation.settings).accessibilityHidden(navigation.settings)
                if navigation.settings { PreferencesView(back: { navigation.settings = false }, store: store, guide: { navigation.onboarding = true }).background(Color(nsColor: .windowBackgroundColor)) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 900, minHeight: 540)
        .sheet(isPresented: $navigation.onboarding) { PasteOnboardingView { UserDefaults.standard.set(true, forKey: "quickOnboardingComplete"); navigation.onboarding = false } }
        .environment(\.locale, AppLanguage.shared.locale)
    }
}

struct HistoryView: View {
    @Bindable var store: ClipStore
    var primary: (ClipItem, ClipStore.CopyMode) async -> Bool
    var close: () -> Void
    var settings: () -> Void
    @State private var query = ""
    @State private var selection: UUID?
    @State private var copied = false
    @State private var preview: ClipItem?
    @State private var clearAction: ClearAction = .clipboard
    @State private var confirmClear = false
    @FocusState private var searching: Bool
    private var filtered: [ClipItem] { store.displayItems.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query) || $0.files.contains { $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) } } }
    var body: some View {
        HSplitView {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit().frame(width: 26, height: 26)
                Text("Pasteback").font(.system(size: 18, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(tr("按住顶部标题或空白处拖动窗口"))
                Spacer()
                Circle().fill(store.paused ? Color.orange : .teal).frame(width: 6, height: 6)
                Text(store.paused ? tr("已暂停") : (store.processing ? tr("正在导入…") : tr("正在记录"))).font(.caption).foregroundStyle(.secondary)
                Button(action: settings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help(tr("设置")).accessibilityLabel(tr("设置"))
            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("搜索复制过的内容…"), text: $query).textFieldStyle(.plain).focused($searching)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(11).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 16)
            HStack {
                Text(query.isEmpty ? tr("你的剪贴板") : tr("搜索结果")).font(.system(size: 11, weight: .medium))
                if query.isEmpty { Text(tr("最近复制在前")).font(.system(size: 10)) }
                Spacer(); Text(trCount(filtered.count)).font(.system(size: 11, design: .monospaced))
            }.foregroundStyle(.secondary).padding(.horizontal, 21).padding(.top, 19).padding(.bottom, 8)
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.teal)
                    Text(query.isEmpty ? tr("复制一下，随时找回。") : tr("没有找到相关内容")).font(.headline)
                    Text(query.isEmpty ? tr("复制文字或图片后，它们会出现在这里。\n所有历史仅保存在这台 Mac。") : tr("试试其他文字或应用名称。"))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                                if index == 0 && item.pinned { Text(tr("固定")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 5) }
                                if !item.pinned && index > 0 && filtered[index - 1].pinned { Text(tr("最近记录")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 8) }
                                ClipRow(item: item, number: index < 9 ? index + 1 : nil, selected: selection == item.id, copy: { use(item) })
                                    .contentShape(Rectangle())
                                    .gesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { gesture in
                                        selection = item.id
                                        switch gesture {
                                        case .first: activate(item)
                                        case .second: break
                                        }
                                    })
                                    .contextMenu {
                                        Button(tr("复制到剪贴板")) { use(item) }
                                        if !item.files.isEmpty {
                                            Button(tr("复制路径")) { use(item, mode: .paths) }
                                            Button(tr("复制文件名")) { use(item, mode: .names) }
                                            Button(tr("在Finder中显示")) { NSWorkspace.shared.activateFileViewerSelecting(item.files.map(\.url)) }
                                        }
                                        Button(item.pinned ? tr("取消固定") : tr("固定")) { store.pin(item) }
                                        Button(tr("删除"), role: .destructive) { store.remove(item) }
                                    }.id(item.id)
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 12)
                    }.onChange(of: selection) { _, value in proxy.scrollTo(value) }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Text(copied ? tr("已复制，切回应用按 ⌘V 粘贴") : tr("点击查看 · ↩ 复制 · ⌘P 固定"))
                Spacer()
                Menu {
                    Button(tr("清空当前剪贴板…"), role: .destructive) { clearAction = .clipboard; confirmClear = true }
                    Button(tr("清空历史和剪贴板…"), role: .destructive) { clearAction = .all; confirmClear = true }
                } label: { Image(systemName: "trash").accessibilityLabel(tr("清理")) }
                    .menuStyle(.borderlessButton).fixedSize().help(tr("清理"))
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 37)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
        }
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 460, maxHeight: .infinity).background(Color(nsColor: .controlBackgroundColor))
        Group {
            if let item = filtered.first(where: { $0.id == selection }) {
                ClipDetailView(item: item, store: store, embedded: true).id(item.id)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.teal)
                    Text(tr("复制一下，随时找回。")).font(.headline)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, AppLanguage.shared.locale)
        .onAppear { searching = true; selection = filtered.first?.id }
        .onChange(of: query) { selection = filtered.first?.id }
        .onChange(of: store.displayItems.map { "\($0.id)-\($0.pinned)" }) { _, _ in
            if !filtered.contains(where: { $0.id == selection }) { selection = filtered.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searching = true
            if selection == nil { selection = filtered.first?.id }
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if let item = filtered.first(where: { $0.id == selection }) {
                activate(item, mode: press.modifiers.contains(.option) && !item.files.isEmpty ? .paths : .content)
            }
            return .handled
        }
        .alert(clearAction == .clipboard ? tr("清空当前剪贴板？") : tr("清空历史和剪贴板？"), isPresented: $confirmClear) {
            Button(tr("取消"), role: .cancel) {}
            Button(tr("清空"), role: .destructive) {
                if clearAction == .all { store.clear(); preview = nil; selection = nil }
                store.clearClipboard(); copied = false
            }
        } message: {
            Text(clearAction == .clipboard ? tr("只清空当前系统剪贴板，历史记录仍然保留。") : tr("删除全部历史（包括固定项）并清空当前系统剪贴板，无法撤销。"))
        }
        .sheet(item: $preview) { item in ClipDetailView(item: item, store: store) }
        .onExitCommand(perform: close)
        .background {
            Group {
                ForEach(1...9, id: \.self) { number in
                    Button("") {
                        guard preview == nil, filtered.indices.contains(number - 1) else { return }
                        selection = filtered[number - 1].id
                        activate(filtered[number - 1])
                    }.keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                }
                Button("") { if let item = filtered.first(where: { $0.id == selection }) { store.pin(item) } }.keyboardShortcut("p")
                Button("") { if let item = filtered.first(where: { $0.id == selection }) { store.remove(item); selection = filtered.first?.id } }.keyboardShortcut(.delete)
            }.hidden()
        }
    }
    private func activate(_ item: ClipItem, mode: ClipStore.CopyMode = .content) { Task { copied = await primary(item, mode) } }
    private func use(_ item: ClipItem, mode: ClipStore.CopyMode = .content) { Task { copied = await store.copy(item, mode: mode) } }
    private func move(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        let index = filtered.firstIndex(where: { $0.id == selection }) ?? 0
        selection = filtered[min(max(index + offset, 0), filtered.count - 1)].id
    }
}

struct ClipRow: View {
    let item: ClipItem
    let number: Int?
    let selected: Bool
    var copy: () -> Void
    @State private var filesAvailable = true
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            if let number { Text(String(number)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 8) }
            Image(nsImage: AppIconCache.shared.icon(item.sourceID))
                .resizable().frame(width: 25, height: 25).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                if let first = item.files.first {
                    if item.files.count > 1 { Text(String(format: tr("文件数量"), item.files.count)).font(.caption) }
                    FileReferenceRow(file: first)
                } else if let name = item.imageName {
                    ClipThumbnail(name: name).frame(maxWidth: 270, maxHeight: 90)
                } else { Text(String(item.text.prefix(240))).font(.system(size: 13)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
                HStack(spacing: 5) {
                    Text(trFormat("来源格式", item.source)); Text("·"); Text(item.date, style: .relative)
                    Spacer()
                    if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.teal) }
                    if item.imageName != nil { Image(systemName: "photo") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Button(action: copy) { Image(systemName: "doc.on.doc").frame(width: 24, height: 28) }
                .disabled(!filesAvailable).buttonStyle(.borderless).help(tr("复制整条内容")).accessibilityLabel(tr("复制整条内容"))
        }.task(id: item.filesData) {
            let files = item.files
            guard !files.isEmpty else { filesAvailable = true; return }
            while !Task.isCancelled {
                var exists = true
                for file in files { if !(await FileReferenceService.shared.status(file).exists) { exists = false } }
                filesAvailable = exists
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.teal.opacity(0.11) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.teal.opacity(0.22) : .clear, lineWidth: 1))
    }
}

struct PreferencesView: View {
    var back: () -> Void
    @Bindable var store: ClipStore
    var guide: () -> Void = {}
    @State private var confirmClear = false
    @State private var launch = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @Bindable private var language = AppLanguage.shared
    @Bindable private var updater = UpdateChecker.shared
    @Bindable private var pasteAction = PasteAction.shared
    @AppStorage("filePathFormat") private var pathFormat = "shell"
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) { Label(tr("返回历史"), systemImage: "chevron.left") }
                    .keyboardShortcut("[", modifiers: .command)
                Spacer()
                Text(tr("设置")).font(.headline)
                Spacer()
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            Form {
            Section(tr("通用")) {
                Picker(tr("语言"), selection: $language.selection) {
                    Text(tr("跟随系统")).tag("auto")
                    ForEach(AppLanguage.options, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                Text(tr("语言说明")).font(.caption).foregroundStyle(.secondary)
                Toggle(tr("选中后自动粘贴"), isOn: Binding(get: { pasteAction.enabled }, set: { pasteAction.setEnabled($0) }))
                Text(tr("默认只复制。开启后，回车、双击或⌘1–9会粘贴到呼出面板前的应用。")).font(.caption).foregroundStyle(.secondary)
                Picker(tr("复制路径格式"), selection: $pathFormat) {
                    Text(tr("终端安全格式")).tag("shell")
                    Text(tr("原样路径")).tag("raw")
                    Text(tr("@引用格式")).tag("mention")
                }
                Text(tr("文件只保存引用。⌥↩复制路径；终端格式用空格分隔，其他格式每行一个。")).font(.caption).foregroundStyle(.secondary)
                Toggle(tr("暂停记录"), isOn: $store.paused)
                Toggle(tr("登录时启动 Pasteback"), isOn: $launch).onChange(of: launch) { _, value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { launchError = error.localizedDescription; launch = SMAppService.mainApp.status == .enabled }
                }
                HStack { Text(tr("快捷浮层")); Spacer(); ShortcutRecorder().frame(width: 220, height: 26) }
                Button(tr("恢复默认快捷键")) { GlobalShortcut.shared.reset() }
                if let error = GlobalShortcut.shared.error { Text(error).font(.caption).foregroundStyle(.red) }
                Button(tr("自动粘贴使用引导"), action: guide)
                Text(tr("初版使用固定快捷键。回车复制后，切回原应用按 ⌘V 粘贴。自动粘贴与快捷键录制将在下一阶段接入。"))
                    .font(.caption).foregroundStyle(.secondary)
                if let launchError { Text(launchError).foregroundStyle(.red) }
            }
            Section(tr("版本与更新")) {
                LabeledContent("Pasteback", value: updater.currentVersion)
                Button(updater.checking ? tr("正在检查…") : tr("检查更新…")) { Task { await updater.check() } }
                    .disabled(updater.checking)
                Text(tr("检查更新隐私说明")).font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("存储")) {
                Picker(tr("历史数量上限"), selection: $store.limit) { ForEach([100, 250, 500, 1000], id: \.self) { Text(trCount($0)).tag($0) } }
                Text(tr("固定条目不自动清理。单张图片最多 128 MB，文字最多 2 MB。")) .font(.caption).foregroundStyle(.secondary)
                Button(tr("清空全部历史…"), role: .destructive) { confirmClear = true }
            }
            Section(tr("隐私")) {
                Toggle(tr("记录图片"), isOn: $store.recordImages)
                Text(tr("忽略的应用 Bundle ID（每行一个）")).font(.caption)
                TextEditor(text: $store.blacklist).font(.system(.caption, design: .monospaced)).frame(height: 70)
                Label(tr("仅存本机 · 不联网 · 不上传"), systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Text(tr("本地数据说明")).font(.caption).foregroundStyle(.secondary)
                Text(tr("保护范围说明")).font(.caption).foregroundStyle(.secondary)
                Button(tr("打开本地数据文件夹")) { NSWorkspace.shared.open(ClipStore.directory) }
            }
        }.formStyle(.grouped)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, AppLanguage.shared.locale)
        .alert(tr("清空全部历史？"), isPresented: $confirmClear) {
            Button(tr("取消"), role: .cancel) {}
            Button(tr("清空"), role: .destructive) { store.clear() }
        } message: { Text(tr("包括固定条目，此操作无法撤销。")) }
    }
}


@MainActor final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]
    func icon(_ bundle: String) -> NSImage {
        if let icon = icons[bundle] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!
        icon.size = NSSize(width: 25, height: 25)
        icons[bundle] = icon
        return icon
    }
}

struct ClipThumbnail: View {
    let name: String
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 2).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary).frame(height: 64) }
        }.clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: name) { image = await ThumbnailLoader.shared.load(name) }
    }
}

struct ClipDetailView: View {
    let item: ClipItem
    let store: ClipStore
    let embedded: Bool
    // Snapshot values remain valid while the sheet dismisses after deletion.
    private let text: String
    private let imageName: String?
    private let files: [FileReference]
    @State private var filesAvailable = true
    private let source: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmDelete = false
    init(item: ClipItem, store: ClipStore, embedded: Bool = false) {
        self.embedded = embedded
        self.item = item; self.store = store
        text = item.text; imageName = item.imageName; source = item.source; files = item.files
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(!files.isEmpty ? tr("文件内容") : imageName == nil ? tr("文字内容") : tr("图片内容")).font(.headline)
                Spacer()
                if !embedded { Button(tr("完成")) { dismiss() }.keyboardShortcut(.cancelAction) }
            }
            if !files.isEmpty {
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(files, id: \.path) { FileReferenceRow(file: $0) } } }
                Button(tr("复制路径")) { Task { copied = await store.copy(item, mode: .paths) } }
                Text(tr("删除记录只移除引用，不删除原文件。")).font(.caption).foregroundStyle(.secondary)
            } else if let name = imageName {
                ClipThumbnail(name: name).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CppContentView(text: text)
            }
            Text(!files.isEmpty ? tr("文件只保存引用，原文件移动或删除后需重新复制。") : imageName == nil ? tr("拖选文字后按 ⌘C 可复制选中部分。") : tr("点击下方按钮复制原始图片。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(trFormat("来源格式", source)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(role: .destructive) { confirmDelete = true } label: { Label(tr("删除"), systemImage: "trash") }
                    .buttonStyle(.bordered)
                Spacer()
                Button(copied ? tr("已复制 ✓") : tr("复制全部")) { Task { copied = await store.copy(item) } }
                    .disabled(!filesAvailable).buttonStyle(.borderedProminent).tint(.teal)
            }
        }.task {
            guard !files.isEmpty else { return }
            while !Task.isCancelled {
                var exists = true
                for file in files { if !(await FileReferenceService.shared.status(file).exists) { exists = false } }
                filesAvailable = exists
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, AppLanguage.shared.locale)
        .alert(tr("删除这条历史？"), isPresented: $confirmDelete) {
            Button(tr("取消"), role: .cancel) {}
            Button(tr("删除"), role: .destructive) { store.remove(item); if !embedded { dismiss() } }
        } message: { Text(tr("删除说明")) }
    }
}
