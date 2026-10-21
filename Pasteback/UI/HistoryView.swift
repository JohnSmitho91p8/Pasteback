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
        HistoryView(store: store, navigation: navigation, primary: primary, close: close, settings: { navigation.settings = true })
            .frame(minWidth: DesignTokens.Metrics.minimumWindow.width, minHeight: DesignTokens.Metrics.minimumWindow.height)
            .sheet(isPresented: $navigation.settings) {
                PreferencesView(back: { navigation.settings = false }, store: store, guide: { navigation.settings = false; navigation.onboarding = true })
                    .frame(width: 640, height: 560)
            }
            .sheet(isPresented: $navigation.onboarding) { PasteOnboardingView { UserDefaults.standard.set(true, forKey: "quickOnboardingComplete"); navigation.onboarding = false } }

        .environment(\.locale, AppLanguage.shared.locale)
    }
}

struct HistoryView: View {
    @Bindable var store: ClipStore
    @Bindable var navigation: WorkspaceNavigation
    var primary: (ClipItem, ClipStore.CopyMode) async -> Bool
    var close: () -> Void
    var settings: () -> Void
    @State private var copied = false
    @State private var preview: ClipItem?
    @State private var clearAction: ClearAction = .clipboard
    @State private var confirmClear = false
    @State private var searching = false
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var categorized: [ClipItem] { store.displayItems.filter { matches($0, category: navigation.category) } }
    private func matches(_ item: ClipItem, category: ClipCategory) -> Bool {
        category == .all || (category == .pinned ? item.pinned : ClipPresentationCache.shared.kind(item) == category)
    }
    private var filtered: [ClipItem] { categorized.filter { navigation.query.isEmpty || $0.text.localizedCaseInsensitiveContains(navigation.query) || $0.source.localizedCaseInsensitiveContains(navigation.query) || $0.files.contains { $0.name.localizedCaseInsensitiveContains(navigation.query) || $0.path.localizedCaseInsensitiveContains(navigation.query) } } }
    var body: some View {
        VStack(spacing: 0) {
            Group {
            if filtered.isEmpty {
                NavigationSplitView { sidebar } detail: { historyList.toolbar { settingsToolbar } }
            } else {
                NavigationSplitView { sidebar } content: { historyList.navigationSplitViewColumnWidth(min: 240, ideal: 310, max: 440) } detail: { detail.toolbar { settingsToolbar } }
            }
        }
            statusBar
        }
        .searchable(text: $navigation.query, isPresented: $searching, placement: .toolbar, prompt: tr("搜索复制过的内容…"))
        .animation(reduceMotion ? nil : DesignTokens.animation, value: filtered.isEmpty)
        .background(DesignTokens.ColorStyle.window)
        .environment(\.locale, AppLanguage.shared.locale)
        .onAppear { searching = true; if !filtered.contains(where: { $0.id == navigation.selection }) { navigation.selection = filtered.first?.id } }
        .onChange(of: navigation.query) { navigation.selection = filtered.first?.id }
        .onChange(of: navigation.category) { navigation.selection = filtered.first?.id }
        .onChange(of: store.displayItems.map { "\($0.id)-\($0.pinned)" }) { _, _ in
            if !filtered.contains(where: { $0.id == navigation.selection }) { navigation.selection = filtered.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard !navigation.settings && !navigation.onboarding else { return }
            searching = true
            if navigation.selection == nil { navigation.selection = filtered.first?.id }
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if let item = filtered.first(where: { $0.id == navigation.selection }) {
                activate(item, mode: press.modifiers.contains(.option) && !item.files.isEmpty ? .paths : .content)
            }
            return .handled
        }
        .alert(clearAction == .clipboard ? tr("清空当前剪贴板？") : tr("清空历史和剪贴板？"), isPresented: $confirmClear) {
            Button(tr("取消"), role: .cancel) {}
            Button(tr("清空"), role: .destructive) {
                if clearAction == .all { store.clear(); preview = nil; navigation.selection = nil }
                store.clearClipboard(); copied = false
            }
        } message: {
            Text(clearAction == .clipboard ? tr("只清空当前系统剪贴板，历史记录仍然保留。") : tr("删除全部历史（包括固定项）并清空当前系统剪贴板，无法撤销。"))
        }
        .sheet(item: $preview) { item in ClipDetailView(item: item, store: store) }
        .onExitCommand { navigation.query = ""; searching = false; listFocused = true }
        .background {
            WorkspaceSearchKeys(focusSearch: {
                searching = false
                Task { @MainActor in await Task.yield(); searching = true }
            }, move: move, activate: { paths in
                if let item = filtered.first(where: { $0.id == navigation.selection }) {
                    activate(item, mode: paths && !item.files.isEmpty ? .paths : .content)
                }
            }, escape: { navigation.query = ""; searching = false; listFocused = true })
            Group {
                Button("") { searching = true }.keyboardShortcut("f")
                ForEach(1...9, id: \.self) { number in
                    Button("") {
                        guard preview == nil, filtered.indices.contains(number - 1) else { return }
                        navigation.selection = filtered[number - 1].id
                        activate(filtered[number - 1])
                    }.keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                }
                Button("") { if let item = filtered.first(where: { $0.id == navigation.selection }) { store.pin(item) } }.keyboardShortcut("p")
                Button("") { if let item = filtered.first(where: { $0.id == navigation.selection }) { store.remove(item); navigation.selection = filtered.first?.id } }.keyboardShortcut(.delete)
            }.hidden()
        }
    }
    @ToolbarContentBuilder private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) { Spacer() }
        ToolbarItem(placement: .primaryAction) {
            Button(action: settings) { Image(systemName: "gearshape") }
                .help(tr("设置")).accessibilityLabel(tr("设置")).keyboardShortcut(",")
        }
    }
    private var sidebar: some View {
        List(selection: Binding<ClipCategory?>(get: { navigation.category }, set: { if let value = $0 { navigation.category = value } })) {
            ForEach(ClipCategory.allCases) { category in
                HStack {
                    Label(category.title, systemImage: category.symbol)
                    Spacer()
                    Text(String(store.items.filter { matches($0, category: category) }.count))
                        .monospacedDigit().foregroundStyle(.secondary)
                }.tag(category).padding(.vertical, DesignTokens.Space.xs)
            }
        }.listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
    }
    private var historyList: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                VStack(spacing: DesignTokens.Space.md) {
                    Image(systemName: navigation.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: DesignTokens.Metrics.emptySymbol)).foregroundStyle(.secondary)
                    Text(!navigation.query.isEmpty ? tr("没有找到匹配的内容") : (store.items.isEmpty ? tr("复制一下，随时找回。") : tr("这个分类还没有内容"))).font(DesignTokens.TypeStyle.title)
                    Text(!navigation.query.isEmpty ? tr("试试其他文字或应用名称。") : (store.items.isEmpty ? tr("复制文字或图片后，它们会出现在这里。\n所有历史仅保存在这台 Mac。") : tr("选择其他分类，或复制新的内容。")))
                        .font(DesignTokens.TypeStyle.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    if navigation.query.isEmpty && store.items.isEmpty {
                        Text(GlobalShortcut.shared.label + " " + tr("呼出快捷浮层"))
                            .font(DesignTokens.TypeStyle.shortcut)
                            .padding(DesignTokens.Space.sm).background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DesignTokens.Space.xs) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                                if index == 0 && item.pinned { Text(tr("固定")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DesignTokens.Space.md).padding(.top, DesignTokens.Space.xs) }
                                if !item.pinned && index > 0 && filtered[index - 1].pinned { Text(tr("最近记录")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DesignTokens.Space.md).padding(.top, DesignTokens.Space.sm) }
                                ClipRow(item: item, number: index < 9 ? index + 1 : nil, selected: navigation.selection == item.id, copy: { use(item) })
                                    .contentShape(Rectangle())
                                    .gesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { gesture in
                                        navigation.selection = item.id
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
                        }.padding(.horizontal, DesignTokens.Space.sm).padding(.bottom, DesignTokens.Space.md)
                    }.focusable().focused($listFocused)
                    .onChange(of: navigation.selection) { _, value in proxy.scrollTo(value) }
                }
            }

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.ColorStyle.content)
    }
    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: DesignTokens.Space.md) {
                Button { store.paused.toggle() } label: {
                    HStack(spacing: DesignTokens.Space.xs) {
                        Circle().fill(store.paused ? Color.secondary : .green).frame(width: 6, height: 6)
                        Text(store.paused ? tr("已暂停") : tr("正在记录"))
                    }
                }.buttonStyle(.plain).help(store.paused ? tr("继续记录") : tr("暂停记录"))
                ViewThatFits(in: .horizontal) {
                    Text(copied ? tr("已复制，切回应用按 ⌘V 粘贴") : tr("点击查看 · ↩ 复制 · ⌘P 固定")).lineLimit(1)
                    Color.clear.frame(width: 0, height: 0)
                }
                Spacer()
                Text(trCount(store.items.count)).monospacedDigit().fixedSize()
                Menu {
                    Button(tr("清空当前剪贴板…"), role: .destructive) { clearAction = .clipboard; confirmClear = true }
                    Button(tr("清空历史和剪贴板…"), role: .destructive) { clearAction = .all; confirmClear = true }
                } label: { Image(systemName: "trash").accessibilityLabel(tr("清理")) }
                    .menuStyle(.borderlessButton).fixedSize().help(tr("清理"))
            }.font(DesignTokens.TypeStyle.caption).foregroundStyle(.secondary).padding(.horizontal, DesignTokens.Space.lg).frame(height: DesignTokens.Metrics.statusHeight)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).padding(DesignTokens.Space.sm) }
        }.background(.bar)
    }
    @ViewBuilder private var detail: some View {
        if let item = filtered.first(where: { $0.id == navigation.selection }) ?? filtered.first {
            ClipDetailView(item: item, store: store, embedded: true).id(item.id)
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func activate(_ item: ClipItem, mode: ClipStore.CopyMode = .content) { Task { copied = await primary(item, mode) } }
    private func use(_ item: ClipItem, mode: ClipStore.CopyMode = .content) { Task { copied = await store.copy(item, mode: mode) } }
    private func move(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        let index = filtered.firstIndex(where: { $0.id == navigation.selection }) ?? 0
        navigation.selection = filtered[min(max(index + offset, 0), filtered.count - 1)].id
    }
}

struct ClipRow: View {
    let item: ClipItem
    let number: Int?
    let selected: Bool
    var copy: () -> Void
    @State private var filesAvailable = true
    @State private var hovering = false
    private var kind: ClipCategory { ClipPresentationCache.shared.kind(item) }
    private var domain: String? { kind == .link ? URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines))?.host : nil }
    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Space.md) {
            Group {
                if let name = item.imageName { ClipThumbnail(name: name) }
                else { Image(systemName: item.files.isEmpty ? kind.symbol : "doc").font(.system(size: 18)).foregroundStyle(.secondary) }
            }.frame(width: DesignTokens.Metrics.thumbnail, height: DesignTokens.Metrics.thumbnail).clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                HStack(alignment: .top, spacing: DesignTokens.Space.xs) {
                    Text(item.files.first?.name ?? (item.imageName == nil ? (domain.map { $0 + "\n" } ?? "") + String(item.text.prefix(240)) : tr("图片内容")))
                        .font(DesignTokens.TypeStyle.body).foregroundStyle(kind == .link ? Color.accentColor : .primary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if item.pinned { Image(systemName: "pin.fill").font(DesignTokens.TypeStyle.caption).foregroundStyle(.secondary).accessibilityLabel(tr("已固定")) }
                }
                HStack(spacing: DesignTokens.Space.xs) {
                    Image(nsImage: AppIconCache.shared.icon(item.sourceID)).resizable().frame(width: 12, height: 12).accessibilityHidden(true)
                    Text(item.source).lineLimit(1)
                    Text("·")
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(relativeDate(at: context.date)).lineLimit(1)
                    }
                }.font(DesignTokens.TypeStyle.caption).foregroundStyle(.secondary)
            }
            Button(action: copy) { Image(systemName: "doc.on.doc").frame(width: 20, height: 24) }
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
        }.padding(.horizontal, DesignTokens.Space.md).padding(.vertical, DesignTokens.Space.sm).frame(minHeight: DesignTokens.Metrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? DesignTokens.ColorStyle.selection : (hovering ? DesignTokens.ColorStyle.hover : .clear), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .onHover { hovering = $0 }
            .animation(DesignTokens.animation, value: hovering)
    }
    private func relativeDate(at now: Date) -> String {
        if now.timeIntervalSince(item.date) < 60 { return tr("刚刚") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.shared.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.date, relativeTo: now)
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
            }.padding(.horizontal, 20).padding(.vertical, DesignTokens.Space.md)
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
        }.clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
            HStack {
                Text(!files.isEmpty ? tr("文件内容") : imageName == nil ? tr("文字内容") : tr("图片内容")).font(.headline)
                Spacer()
                if !embedded { Button(tr("完成")) { dismiss() }.keyboardShortcut(.cancelAction) }
            }
            HStack(spacing: DesignTokens.Space.sm) {
                Image(nsImage: AppIconCache.shared.icon(item.sourceID)).resizable().frame(width: 14, height: 14)
                Text(source).lineLimit(1)
                Text("·")
                Text(item.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.shared.locale)))
            }.font(DesignTokens.TypeStyle.secondary).foregroundStyle(.secondary)
            if !files.isEmpty {
                ScrollView { LazyVStack(alignment: .leading, spacing: DesignTokens.Space.md) { ForEach(files, id: \.path) { FileReferenceRow(file: $0) } } }
                Button(tr("复制路径")) { Task { copied = await store.copy(item, mode: .paths) } }
                Text(tr("删除记录只移除引用，不删除原文件。")).font(.caption).foregroundStyle(.secondary)
            } else if let name = imageName {
                ClipThumbnail(name: name).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CppContentView(text: text)
            }
            Text(!files.isEmpty ? tr("文件只保存引用，原文件移动或删除后需重新复制。") : imageName == nil ? tr("拖选文字后按 ⌘C 可复制选中部分。") : tr("点击下方按钮复制原始图片。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(role: .destructive) { confirmDelete = true } label: { Label(tr("删除"), systemImage: "trash") }
                    .buttonStyle(.bordered)
                Button { store.pin(item) } label: {
                    ViewThatFits(in: .horizontal) {
                        Label(item.pinned ? tr("取消固定") : tr("固定"), systemImage: item.pinned ? "pin.slash" : "pin").fixedSize()
                        Image(systemName: item.pinned ? "pin.slash" : "pin")
                    }
                }.buttonStyle(.bordered).help(item.pinned ? tr("取消固定") : tr("固定")).accessibilityLabel(item.pinned ? tr("取消固定") : tr("固定"))
                Spacer()
                Button(copied ? tr("已复制 ✓") : tr("复制全部")) { Task { copied = await store.copy(item) } }
                    .disabled(!filesAvailable).buttonStyle(.borderedProminent).tint(.accentColor)
            }
        }.task {
            guard !files.isEmpty else { return }
            while !Task.isCancelled {
                var exists = true
                for file in files { if !(await FileReferenceService.shared.status(file).exists) { exists = false } }
                filesAvailable = exists
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }.padding(DesignTokens.Space.xl).frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, AppLanguage.shared.locale)
        .alert(tr("删除这条历史？"), isPresented: $confirmDelete) {
            Button(tr("取消"), role: .cancel) {}
            Button(tr("删除"), role: .destructive) { store.remove(item); if !embedded { dismiss() } }
        } message: { Text(tr("删除说明")) }
    }
}

/// SwiftUI's toolbar search is an NSSearchField outside the content focus tree.
/// Route only its navigation keys, scoped to this hosting window; leave IME input intact.
private struct WorkspaceSearchKeys: NSViewRepresentable {
    var focusSearch: () -> Void
    var move: (Int) -> Void
    var activate: (Bool) -> Void
    var escape: () -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let window = coordinator.view?.window,
                  event.window === window, window.isKeyWindow, window.attachedSheet == nil else { return event }
            if event.modifierFlags.intersection([.command, .control, .option]) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                coordinator.actions.focusSearch()
                if let field = window.toolbar?.items.compactMap({ ($0 as? NSSearchToolbarItem)?.searchField }).first { window.makeFirstResponder(field) }
                return nil
            }
            guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                  let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                  editor.delegate is NSSearchField, !editor.hasMarkedText() else { return event }
            switch event.keyCode {
            case 125: coordinator.actions.move(1)
            case 126: coordinator.actions.move(-1)
            case 36, 76: coordinator.actions.activate(event.modifierFlags.contains(.option))
            case 53: coordinator.actions.escape()
            default: return event
            }
            return nil
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.actions = self }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var actions: WorkspaceSearchKeys
        init(_ actions: WorkspaceSearchKeys) { self.actions = actions }
    }
}
