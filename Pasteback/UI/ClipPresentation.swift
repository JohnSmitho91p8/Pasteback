import Foundation

/// Display-only categories. No persisted type field or clipboard mutation.
enum ClipCategory: String, CaseIterable, Identifiable {
    case all, text, image, link, code, pinned
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .all: return tr("全部")
        case .text: return tr("文本")
        case .image: return tr("图片")
        case .link: return tr("链接")
        case .code: return tr("代码")
        case .pinned: return tr("已固定")
        }
    }
    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .pinned: return "pin"
        }
    }
    static func classify(text: String, image: Bool, files: Bool) -> ClipCategory {
        if files { return .all } // File references stay accessible in All and Pinned.
        if image { return .image }
        let sample = String(text.prefix(8192)).trimmingCharacters(in: .whitespacesAndNewlines)
        if (sample.lowercased().hasPrefix("https://") || sample.lowercased().hasPrefix("http://")),
           let url = URL(string: sample), url.host != nil, !sample.contains(where: \.isWhitespace) { return .link }
        let cpp = sample.contains("#include") || sample.contains("std::") || sample.contains("using namespace std")
        let structured = sample.contains("{") && sample.contains("}") && sample.contains(";")
        return cpp || structured ? .code : .text
    }
}

@MainActor final class ClipPresentationCache {
    static let shared = ClipPresentationCache()
    private let cache = NSCache<NSString, CategoryBox>()
    private init() { cache.countLimit = 1200 }
    func kind(_ item: ClipItem) -> ClipCategory {
        let key = (item.contentHash + ":" + (item.imageName ?? "") + ":" + String(item.filesData?.count ?? 0)) as NSString
        if let result = cache.object(forKey: key) { return result.value }
        let kind = ClipCategory.classify(text: item.text, image: item.imageName != nil, files: !item.files.isEmpty)
        cache.setObject(CategoryBox(kind), forKey: key)
        return kind
    }
    private final class CategoryBox {
        let value: ClipCategory
        init(_ value: ClipCategory) { self.value = value }
    }
}
