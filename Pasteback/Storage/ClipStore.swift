import AppKit
import SwiftData
import CryptoKit
import Observation
import ImageIO
import UniformTypeIdentifiers

@Model final class ClipItem {
    var id: UUID
    var text: String
    var imageName: String?
    var contentHash: String
    var source: String
    var sourceID: String
    var date: Date
    var pinned: Bool
    init(text: String, imageName: String?, hash: String, source: String, sourceID: String) {
        id = UUID(); self.text = text; self.imageName = imageName; contentHash = hash
        self.source = source; self.sourceID = sourceID; date = .now; pinned = false
    }
}

@MainActor @Observable final class ClipStore {
    let container: ModelContainer
    var items: [ClipItem] = []
    var paused = false
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
    private(set) var processing = false
    private struct Capture {
        let text: String
        let image: Data?
        let source: String
        let bundle: String
        let date: Date
        let generation: Int
        var byteCount: Int { image?.count ?? text.utf8.count }
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
    init(inMemory: Bool = false, monitor: Bool = true, pasteboard: NSPasteboard = .general, storageDirectory: URL? = nil) throws {
        self.pasteboard = pasteboard
        self.storageDirectory = storageDirectory ?? Self.directory
        count = pasteboard.changeCount
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        if !inMemory {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directory.path)
        // Tighten permissions on historical files from earlier builds as well.
        for url in try FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil) {
            let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            try FileManager.default.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
        }
        }
        let config = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(url: Self.directory.appending(path: "History.store"), cloudKitDatabase: .none)
        container = try ModelContainer(for: ClipItem.self, configurations: config)
        reload()
        guard monitor else { return }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                if app.bundleIdentifier != Bundle.main.bundleIdentifier { self?.lastExternalApp = app }
            }
        }
        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.025
        if let timer { RunLoop.main.add(timer, forMode: .common) }
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
        let p = pasteboard
        let change = p.changeCount
        guard change != count else { return }
        guard !paused else { count = change; return }
        if retryChange != change { retryChange = change; readAttempts = 0 }
        let types = Set((p.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "de.petermaurer.TransientPasteboardType"]) else { count = change; return }
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? lastExternalApp : front
        let bundle = app?.bundleIdentifier ?? ""
        guard !isExcluded(bundle) else { count = change; return }
        let date = Date.now
        let text = p.string(forType: .string) ?? ""
        if !text.isEmpty, let ownBundle = Bundle.main.bundleIdentifier, front?.bundleIdentifier == ownBundle { count = change; return }
        var image: Data?
        if text.isEmpty && recordImages {
            if types.contains(NSPasteboard.PasteboardType.png.rawValue) { image = p.data(forType: .png) }
            if image == nil && types.contains(NSPasteboard.PasteboardType.tiff.rawValue) { image = p.data(forType: .tiff) }
        }
        // A provider may advertise an image before its bytes are ready. Do not
        // acknowledge that change until a snapshot is available or retries expire.
        guard p.changeCount == change else { return }
        if text.isEmpty && image == nil {
            let supported = types.contains(NSPasteboard.PasteboardType.string.rawValue)
                || (recordImages && (types.contains(NSPasteboard.PasteboardType.png.rawValue) || types.contains(NSPasteboard.PasteboardType.tiff.rawValue)))
            readAttempts += 1
            if (supported || types.isEmpty) && readAttempts < 14 { return }
            count = change
            if supported { error = tr("剪贴板数据尚未就绪，请重新复制。") }
            return
        }
        count = change
        guard text.utf8.count <= 2_000_000, (image?.count ?? 0) <= 128_000_000 else {
            error = tr("内容过大，未记录：图片最多128MB，文字最多2MB。")
            return
        }
        let capture = Capture(text: text, image: image, source: app?.localizedName ?? tr("未知应用"), bundle: bundle, date: date, generation: captureGeneration)
        guard pending.count < 8, pending.reduce(0, { $0 + $1.byteCount }) + capture.byteCount <= 256_000_000 else {
            error = tr("待处理内容过多，请稍候再复制。")
            return
        }
        pending.append(capture)
        error = nil
        if !processing { processPending() }
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
                    let prepared = try await ClipProcessor.shared.prepare(text: capture.text, image: capture.image, outputDirectory: storageDirectory)
                    guard capture.generation == captureGeneration, !paused, !isExcluded(capture.bundle), capture.image == nil || recordImages else {
                        if let name = prepared.imageName { await ClipProcessor.shared.remove(name, from: storageDirectory) }
                        continue
                    }
                    if let old = items.first(where: { $0.contentHash == prepared.hash }) {
                        old.date = capture.date; old.source = capture.source; old.sourceID = capture.bundle
                        if let name = prepared.imageName { await ClipProcessor.shared.remove(name, from: storageDirectory) }
                    } else {
                        let item = ClipItem(text: capture.text, imageName: prepared.imageName, hash: prepared.hash, source: capture.source, sourceID: capture.bundle)
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
    func copy(_ item: ClipItem) async -> Bool {
        let generation = captureGeneration
        let p = NSPasteboard.general
        if let name = item.imageName {
            guard let data = await ClipProcessor.shared.read(name, from: storageDirectory) else { error = tr("图片文件无法读取"); return false }
            guard generation == captureGeneration else { return false }
            p.clearContents(); p.setData(data, forType: name.hasSuffix(".tiff") ? .tiff : .png)
        } else { p.clearContents(); p.setString(item.text, forType: .string) }
        count = p.changeCount
        return true
    }
}

// Image conversion, hashing and file IO never run on the UI actor.
actor ClipProcessor {
    static let shared = ClipProcessor()
    struct Prepared: Sendable { let hash: String; let imageName: String? }
    private var directory: URL { URL.applicationSupportDirectory.appending(path: "Pasteback", directoryHint: .isDirectory) }
    func prepare(text: String, image: Data?, outputDirectory: URL? = nil) throws -> Prepared {
        let data = image ?? Data(text.utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var name: String?
        if let image {
            guard let source = CGImageSourceCreateWithData(image as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let type = CGImageSourceGetType(source) as String?,
                  type == UTType.png.identifier || type == UTType.tiff.identifier,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 80_000_000 / height else { throw CocoaError(.fileReadCorruptFile) }
            // Preserve the original bytes. Full-size decode and PNG recompression
            // are unnecessary for history storage and made first screenshots slow.
            name = "\(UUID().uuidString).\(type == UTType.png.identifier ? "png" : "tiff")"
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
