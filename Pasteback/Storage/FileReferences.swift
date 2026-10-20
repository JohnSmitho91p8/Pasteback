import AppKit
import Foundation
import UniformTypeIdentifiers

struct FileReference: Codable, Hashable, Sendable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let type: String?
    let modified: Date?
    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }
    var abbreviatedFolder: String { ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath }
}

enum FilePathFormat: String, CaseIterable {
    case shell, raw, mention
    // Keep these separators explicit: terminal commands use spaces, references use lines.
    static let shellSeparator = " "
    static let referenceSeparator = "\n"
    func render(_ files: [FileReference]) -> String {
        switch self {
        case .raw: return files.map(\.path).joined(separator: Self.referenceSeparator)
        case .mention: return files.map { "@" + $0.path }.joined(separator: Self.referenceSeparator)
        case .shell: return files.map { Self.shellQuote($0.path) }.joined(separator: Self.shellSeparator)
        }
    }
    static func shellQuote(_ value: String) -> String {
        // Quote every path, including embedded quotes and newlines; never evaluate paths.
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

actor FileReferenceService {
    static let shared = FileReferenceService()
    static let maximumFiles = 200
    struct Status: Sendable { let exists: Bool }
    private var cached: [String: (Date, Bool)] = [:]
    func references(_ urls: [URL]) -> [FileReference] {
        urls.filter { $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") }
            .prefix(Self.maximumFiles).compactMap { url in
                let url = url.standardizedFileURL
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey, .contentModificationDateKey]),
                      FileManager.default.fileExists(atPath: url.path) else { return nil }
                return FileReference(path: url.path, name: url.lastPathComponent, isDirectory: values.isDirectory == true,
                    size: values.fileSize.map(Int64.init), type: values.contentType?.identifier, modified: values.contentModificationDate)
            }
    }
    func status(_ file: FileReference, fresh: Bool = false) -> Status {
        if !fresh, let entry = cached[file.path], Date().timeIntervalSince(entry.0) < 2 { return Status(exists: entry.1) }
        let exists = FileManager.default.fileExists(atPath: file.path)
        if cached.count > 2048 { cached.removeAll(keepingCapacity: true) }
        cached[file.path] = (Date(), exists)
        return Status(exists: exists)
    }
    func allExist(_ files: [FileReference]) -> Bool { !files.isEmpty && files.allSatisfy { status($0, fresh: true).exists } }
}
