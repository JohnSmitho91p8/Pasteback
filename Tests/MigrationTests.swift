import Foundation
import SwiftData
@main struct MigrationTests {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let rollback = CommandLine.arguments.last == "rollback"
        if CommandLine.arguments.last == "reopen" {
            let container = try HistoryDatabase.open(directory: directory)
            let records = try container.mainContext.fetch(FetchDescriptor<ClipItem>())
            let files = records.first { !$0.files.isEmpty }!.files
            precondition(records.count == 3 && files.count == 1 && files[0].name == "legacy.png")
            precondition(files[0].size == 4 && files[0].path == directory.appending(path: "legacy.png").path)
            let backups = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "MigrationBackups").path)
            precondition(backups.filter { $0.hasPrefix("before-v2-") }.count == 1)
            print("PASS: V2 reopen preserves file metadata without repeating migration backup")
            return
        }
        if rollback {
            enum Injected: Error { case failure }
            do {
                _ = try HistoryDatabase.open(directory: directory) { _ in
                    try Data("simulated interrupted migration".utf8).write(to: directory.appending(path: "History.store"))
                    throw Injected.failure
                }
                preconditionFailure("Expected migration failure")
            } catch Injected.failure { }
            let config = ModelConfiguration(url: directory.appending(path: "History.store"), cloudKitDatabase: .none)
            let restored = try ModelContainer(for: Schema(versionedSchema: PastebackSchemaV1.self), configurations: [config])
            let records = try restored.mainContext.fetch(FetchDescriptor<PastebackSchemaV1.ClipItem>())
            precondition(records.count == 2 && records.contains { $0.pinned && $0.text == "legacy code\n    print(1)" })
            print("PASS: failed migration restores a readable legacy database")
        } else {
            let container = try HistoryDatabase.open(directory: directory)
            let records = try container.mainContext.fetch(FetchDescriptor<ClipItem>())
            precondition(records.count == 2)
            let text = records.first { $0.contentHash == "text" }!
            precondition(text.pinned && text.id.uuidString.hasSuffix("000000000001") && text.date == Date(timeIntervalSince1970: 100))
            precondition(text.text == "legacy code\n    print(1)" && text.files.isEmpty)
            precondition(records.first { $0.contentHash == "image" }!.imageName == "legacy.png")
            let imageBytes = try Data(contentsOf: directory.appending(path: "legacy.png"))
            precondition(imageBytes == Data([1, 2, 3, 4]))
            let schemaVersion = try String(contentsOf: directory.appending(path: "schema-version"), encoding: .utf8)
            precondition(schemaVersion == "2")
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "MigrationBackups").path)
            precondition(files.contains { $0.hasPrefix("before-v2-") })
            let file = ClipItem(text: "", imageName: nil, hash: "file-reference", source: "Fixture", sourceID: "fixture")
            file.updateFiles(try JSONEncoder().encode([FileReference(path: directory.appending(path: "legacy.png").path, name: "legacy.png", isDirectory: false, size: 4, type: "public.png", modified: nil)]))
            container.mainContext.insert(file); try container.mainContext.save()
            print("PASS: genuine 0.2.1 history migrated with IDs, dates, pins, text and image references preserved; backup created")
        }
    }
}
