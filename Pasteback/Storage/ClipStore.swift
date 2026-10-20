import AppKit
import SwiftData
import CryptoKit
import Observation
import ImageIO
import UniformTypeIdentifiers

@MainActor @Observable final class ClipStore {
    let container: ModelContainer
    var items: [ClipItem] = []
    var paused = false {
        didSet {
            captureGeneration += 1
            pending.removeAll()
            count = pasteboard.changeCount
        }
    }
    var error: String?
    var recordImages = UserDefaults.standard.object(forKey: "recordImages") as? Bool ?? true {
        didSet { UserDefaults.standard.set(recordImages, forKey: "recordImages") }
    }
    var limit = UserDefaults.standard.object(forKey: "limit") as? Int ?? 500 {
        didSet { UserDefaults.standard.set(limit, forKey: "limit"); trim(); save() }
    }
    var blacklist = UserDefaults.standard.string(forKey: "blacklist") ?? "com.1password.1password\ncom.agilebits.onepassword7\ncom.bitwarden.desktop" {
        didSet { UserDefaults.standard.set(blacklist, forKey: "blacklist") }
    }
    static let directory = URL.applicationSupportDirectory.appending(path: "Pasteback", directoryHint: .isDirectory)
    private var timer: Timer?
    private let reader = PasteboardReader()
    private(set) var reading = false
    private var wakeObserver: NSObjectProtocol?
    static let pollInterval: TimeInterval = 0.05
    private(set) var processing = false
    private struct Capture {
        let text: String
        let image: Data?
        let files: [FileReference]
        let source: String
        let bundle: String
        let date: Date
        let generation: Int
        var byteCount: Int { image?.count ?? (text.utf8.count + files.reduce(0) { $0 + $1.path.utf8.count }) }
    }
    private var pending: [Capture] = []
    private var retryChange = -1
    private var readAttempts = 0
    private let pasteboard: NSPasteboard
    private let storageDirectory: URL
    private var lastExternalApp: NSRunningApplication?
    private var appObserver: NSObjectProtocol?
    private var captureGeneration = 0
    private var count: Int
    init(inMemory: Bool = false, monitor: Bool = true, pasteboard: NSPasteboard = .general, storageDirectory: URL? = nil, preparedContainer: ModelContainer? = nil) throws {
        self.pasteboard = pasteboard
        self.storageDirectory = storageDirectory ?? Self.directory
        count = pasteboard.changeCount
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        if let preparedContainer { container = preparedContainer }
        else if inMemory {
            container = try ModelContainer(for: Schema(versionedSchema: PastebackSchemaV2.self), configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        } else { container = try HistoryDatabase.open(directory: self.storageDirectory) }
        reload()
        guard monitor else { return }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                if app.bundleIdentifier != Bundle.main.bundleIdentifier { self?.lastExternalApp = app }
            }
        }
        timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.01
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
    func reload() {
        do { items = try container.mainContext.fetch(FetchDescriptor<ClipItem>()).sorted {
            $0.date == $1.date ? $0.id.uuidString > $1.id.uuidString : $0.date > $1.date
        } } catch { self.error = error.localizedDescription }
    }
    func save() {
        do { try container.mainContext.save(); sortItems() } catch { self.error = error.localizedDescription }
    }
    private func sortItems() {
        items.sort { $0.date == $1.date ? $0.id.uuidString > $1.id.uuidString : $0.date > $1.date }
    }
    func poll() {
        let change = pasteboard.changeCount
        guard change != count, !reading else { return }
        guard !paused else { count = change; return }
        if retryChange != change { retryChange = change; readAttempts = 0 }
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? lastExternalApp : front
        let bundle = app?.bundleIdentifier ?? ""
        guard !isExcluded(bundle) else { count = change; return }
        let source = app?.localizedName ?? tr("未知应用")
        let date = Date.now
        let generation = captureGeneration
        let previousCount = count
        let boardName = pasteboard.name.rawValue
        let includeImages = recordImages
        reading = true
        Task {
            defer { reading = false }
            // Delayed providers and large screenshot transfers must not block the UI.
            let snapshot = await reader.read(name: boardName, change: change, includeImages: includeImages)
            guard generation == captureGeneration, count == previousCount, !paused, !isExcluded(bundle) else { return }
            guard let snapshot else { return } // Ownership changed while reading: poll again.
            if snapshot.sensitive { count = change; return }
            if snapshot.text.isEmpty && snapshot.image == nil && snapshot.files.isEmpty {
                readAttempts += 1
                if (snapshot.supported || snapshot.emptyTypes) && readAttempts < 50 { return }
                count = change
                if snapshot.supported { error = tr("剪贴板数据尚未就绪，请重新复制。") }
                return
            }
            count = change
            guard snapshot.text.utf8.count <= 2_000_000, (snapshot.image?.count ?? 0) <= 128_000_000 else {
                error = tr("内容过大，未记录：图片最多128MB，文字最多2MB。")
                return
            }
            let capture = Capture(text: snapshot.text, image: snapshot.image, files: snapshot.files, source: source, bundle: bundle, date: date, generation: generation)
            guard pending.count < 32, pending.reduce(0, { $0 + $1.byteCount }) + capture.byteCount <= 256_000_000 else {
                error = tr("待处理内容过多，请稍候再复制。")
                return
            }
            pending.append(capture)
            error = snapshot.truncated ? tr("文件过多，仅记录前200个。") : nil
            if !processing { processPending() }
        }
    }
    private func isExcluded(_ bundle: String) -> Bool {
        blacklist.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == bundle }
    }
    private func processPending() {
        processing = true
        Task {
            defer { processing = false }
            while !pending.isEmpty {
                let capture = pending.removeFirst()
                guard capture.generation == captureGeneration, !paused, !isExcluded(capture.bundle), capture.image == nil || recordImages else { continue }
                do {
                    let prepared = try await ClipProcessor.shared.prepare(text: capture.text, image: capture.image, files: capture.files, outputDirectory: storageDirectory)
                    guard capture.generation == captureGeneration, !paused, !isExcluded(capture.bundle), capture.image == nil || recordImages else {
                        if let name = prepared.imageName { await ClipProcessor.shared.remove(name, from: storageDirectory) }
                        continue
                    }
                    if let old = items.first(where: { $0.contentHash == prepared.hash }) {
                        old.date = capture.date; old.source = capture.source; old.sourceID = capture.bundle
                        if prepared.filesData != nil { old.updateFiles(prepared.filesData) }
                        if let name = prepared.imageName { await ClipProcessor.shared.remove(name, from: storageDirectory) }
                    } else {
                        let item = ClipItem(text: capture.text, imageName: prepared.imageName, hash: prepared.hash, source: capture.source, sourceID: capture.bundle)
                        item.updateFiles(prepared.filesData)
                        item.date = capture.date
                        container.mainContext.insert(item); items.append(item)
                    }
                    sortItems(); trim(); save()
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    func trim() {
        let unpinned = items.filter { !$0.pinned }
        let capacity = max(0, limit - items.filter(\.pinned).count)
        for item in unpinned.dropFirst(capacity) { remove(item, persist: false) }
    }
    func remove(_ item: ClipItem, persist: Bool = true) {
        if let name = item.imageName { Task { await ClipProcessor.shared.remove(name, from: storageDirectory); await ThumbnailLoader.shared.remove(name) } }
        items.removeAll { $0.id == item.id }
        container.mainContext.delete(item)
        if persist { save() }
    }
    func clearClipboard(_ pasteboard: NSPasteboard = .general) {
        captureGeneration += 1
        pending.removeAll()
        pasteboard.clearContents()
        if pasteboard === self.pasteboard { count = pasteboard.changeCount }
    }
    func clear() { captureGeneration += 1; pending.removeAll(); count = pasteboard.changeCount; for item in items { remove(item, persist: false) }; save() }
    func pin(_ item: ClipItem) { item.pinned.toggle(); save() }
    enum CopyMode { case content, paths, names }
    func copy(_ item: ClipItem, mode: CopyMode = .content, to destination: NSPasteboard? = nil) async -> Bool {
        let generation = captureGeneration
        let p = destination ?? pasteboard
        let files = item.files
        let imageName = item.imageName
        let text = item.text
        if !files.isEmpty {
            if mode == .content {
                guard await FileReferenceService.shared.allExist(files) else { error = tr("文件已不存在，仍可复制路径。"); return false }
            }
            guard generation == captureGeneration else { return false }
            p.clearContents()
            let success: Bool
            switch mode {
            case .content: success = p.writeObjects(files.map { $0.url as NSURL })
            case .paths:
                let format = FilePathFormat(rawValue: UserDefaults.standard.string(forKey: "filePathFormat") ?? "shell") ?? .shell
                success = p.setString(format.render(files), forType: .string)
            case .names: success = p.setString(files.map(\.name).joined(separator: "\n"), forType: .string)
            }
            if p.name == pasteboard.name { count = p.changeCount }
            return success
        }
        if let name = imageName {
            guard let data = await ClipProcessor.shared.read(name, from: storageDirectory) else { error = tr("图片文件无法读取"); return false }
            guard generation == captureGeneration else { return false }
            p.clearContents(); p.setData(data, forType: NSPasteboard.PasteboardType(UTType(filenameExtension: (name as NSString).pathExtension)?.identifier ?? UTType.png.identifier))
        } else { p.clearContents(); p.setString(text, forType: .string) }
        if p.name == pasteboard.name { count = p.changeCount }
        return true
    }

}

// Image conversion, hashing and file IO never run on the UI actor.
actor ClipProcessor {
    static let shared = ClipProcessor()
    struct Prepared: Sendable { let hash: String; let imageName: String?; var filesData: Data? = nil }
    private var directory: URL { URL.applicationSupportDirectory.appending(path: "Pasteback", directoryHint: .isDirectory) }
    func prepare(text: String, image: Data?, files: [FileReference] = [], outputDirectory: URL? = nil) throws -> Prepared {
        if !files.isEmpty {
            let paths = files.map(\.path).sorted()
            let identity = try JSONEncoder().encode(paths)
            let hash = SHA256.hash(data: Data("files\0".utf8) + identity).map { String(format: "%02x", $0) }.joined()
            return Prepared(hash: hash, imageName: nil, filesData: try JSONEncoder().encode(files))
        }
        let data = image ?? Data(text.utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var name: String?
        if let image {
            guard let source = CGImageSourceCreateWithData(image as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let type = CGImageSourceGetType(source) as String?,
                  let imageType = UTType(type), imageType.conforms(to: .image),
                  [UTType.png, .tiff, .jpeg, .heic, .gif, .webP].contains(imageType),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 80_000_000 / height else { throw CocoaError(.fileReadCorruptFile) }
            // Preserve the original bytes. Full-size decode and PNG recompression
            // are unnecessary for history storage and made first screenshots slow.
            name = "\(UUID().uuidString).\(imageType.preferredFilenameExtension ?? "png")"
            try image.write(to: (outputDirectory ?? directory).appending(path: name!), options: .atomic)
        }
        return Prepared(hash: hash, imageName: name)
    }
    func read(_ name: String, from outputDirectory: URL? = nil) -> Data? { try? Data(contentsOf: (outputDirectory ?? directory).appending(path: name)) }
    func remove(_ name: String, from outputDirectory: URL? = nil) { try? FileManager.default.removeItem(at: (outputDirectory ?? directory).appending(path: name)) }

}

actor ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.totalCostLimit = 24 * 1024 * 1024 }
    func remove(_ name: String) { cache.removeObject(forKey: name as NSString) }
    func load(_ name: String) -> CGImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let url = URL.applicationSupportDirectory.appending(path: "Pasteback").appending(path: name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        cache.setObject(image, forKey: name as NSString, cost: image.bytesPerRow * image.height)
        return image
    }
}

actor PasteboardReader {
    struct Snapshot: Sendable {
        let text: String
        let image: Data?
        let supported: Bool
        let sensitive: Bool
        let emptyTypes: Bool
        var files: [FileReference] = []
        var truncated = false
    }
    func read(name: String, change: Int, includeImages: Bool) async -> Snapshot? {
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        guard board.changeCount == change else { return nil }
        let types = Set((board.types ?? []).map(\.rawValue))
        let sensitive = !types.isDisjoint(with: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "de.petermaurer.TransientPasteboardType"])
        if sensitive { return Snapshot(text: "", image: nil, supported: false, sensitive: true, emptyTypes: false) }
        // Finder commonly supplies file URLs, names and icons together. Files win.
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            let files = await FileReferenceService.shared.references(urls)
            guard board.changeCount == change else { return nil }
            if !files.isEmpty {
                return Snapshot(text: "", image: nil, supported: true, sensitive: false, emptyTypes: false, files: files, truncated: urls.count > FileReferenceService.maximumFiles)
            }
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier), .init(UTType.gif.identifier), .init(UTType.webP.identifier)]
        let supported = types.contains(NSPasteboard.PasteboardType.string.rawValue) || (includeImages && imageTypes.contains { types.contains($0.rawValue) })
        let text = board.string(forType: .string) ?? ""
        var image: Data?
        if text.isEmpty && includeImages {
            for type in imageTypes where types.contains(type.rawValue) {
                if let data = board.data(forType: type), !data.isEmpty { image = data; break }
            }
        }
        guard board.changeCount == change else { return nil }
        return Snapshot(text: text, image: image, supported: supported, sensitive: false, emptyTypes: types.isEmpty)
    }
}
