import Foundation
import SwiftData
import SQLite3

enum PastebackSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ClipItem.self] }
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
}

enum PastebackSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ClipItem.self] }
@Model final class ClipItem {
    var id: UUID
    var text: String
    var imageName: String?
    var contentHash: String
    var source: String
    var sourceID: String
    var date: Date
    var filesData: Data? = nil
    var pinned: Bool
    init(text: String, imageName: String?, hash: String, source: String, sourceID: String) {
        id = UUID(); self.text = text; self.imageName = imageName; contentHash = hash
        self.source = source; self.sourceID = sourceID; date = .now; pinned = false
    }
    func updateFiles(_ data: Data?) { filesData = data; loadedFiles = nil }
    @Transient private var loadedFiles: [FileReference]? = nil
    var files: [FileReference] {
        if let loadedFiles { return loadedFiles }
        let decoded = filesData.flatMap { try? JSONDecoder().decode([FileReference].self, from: $0) } ?? []
        loadedFiles = decoded
        return decoded
    }
}
}
typealias ClipItem = PastebackSchemaV2.ClipItem

enum PastebackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PastebackSchemaV1.self, PastebackSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: PastebackSchemaV1.self, toVersion: PastebackSchemaV2.self)] }
}

enum HistoryDatabase {
    static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "Pasteback", directoryHint: .isDirectory)
    /// Called on a background task before the UI store is constructed.
    static func open(directory: URL = defaultDirectory, opener: ((ModelConfiguration) throws -> ModelContainer)? = nil) throws -> ModelContainer {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let store = directory.appending(path: "History.store")
        let marker = directory.appending(path: "schema-version")
        let current = (try? String(contentsOf: marker, encoding: .utf8)) == "2"
        var backup: URL?
        if !current && fm.fileExists(atPath: store.path) {
            let backupDir = directory.appending(path: "MigrationBackups", directoryHint: .isDirectory)
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let destination = backupDir.appending(path: "before-v2-\(UUID().uuidString).store")
            try sqliteSnapshot(from: store, to: destination)
            backup = destination
        }
        do {
            let config = ModelConfiguration(url: store, cloudKitDatabase: .none)
            let result = try opener?(config) ?? ModelContainer(for: Schema(versionedSchema: PastebackSchemaV2.self), migrationPlan: PastebackMigrationPlan.self, configurations: [config])
            try "2".write(to: marker, atomically: true, encoding: .utf8)
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
                let folder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                try fm.setAttributes([.posixPermissions: folder ? 0o700 : 0o600], ofItemAtPath: url.path)
            }
            return result
        } catch {
            if let backup {
                // Preserve the failed store for diagnosis; restore the pre-migration snapshot.
                let failed = directory.appending(path: "MigrationBackups/failed-\(UUID().uuidString)", directoryHint: .isDirectory)
                try fm.createDirectory(at: failed, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                for suffix in ["", "-wal", "-shm"] {
                    let path = URL(fileURLWithPath: store.path + suffix)
                    if fm.fileExists(atPath: path.path) { try fm.moveItem(at: path, to: failed.appending(path: path.lastPathComponent)) }
                }
                try fm.copyItem(at: backup, to: store)
                if fm.fileExists(atPath: marker.path) { try fm.removeItem(at: marker) }
            }
            throw error // Do not launch with an empty replacement database.
        }
    }
    private static func sqliteSnapshot(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?; var output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(output, "main", input, "main") else { throw CocoaError(.fileReadUnknown) }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
