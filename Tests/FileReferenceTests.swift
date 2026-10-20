import AppKit
import Foundation
@main struct FileReferenceTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PastebackFiles-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = ["中文 (one).txt", "has'quote.txt", "folder"]
        let urls = names.map { directory.appending(path: $0) }
        try Data("first".utf8).write(to: urls[0]); try Data("second".utf8).write(to: urls[1])
        try FileManager.default.createDirectory(at: urls[2], withIntermediateDirectories: true)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let store = try ClipStore(inMemory: true, monitor: false, pasteboard: board, storageDirectory: directory)
        func settle() async {
            let start = Date()
            while (store.reading || store.processing) && Date().timeIntervalSince(start) < 5 { try? await Task.sleep(for: .milliseconds(2)) }
            precondition(!store.reading && !store.processing)
        }
        board.clearContents(); precondition(board.writeObjects(urls.map { $0 as NSURL }))
        board.setString("Finder file names must not become another history item", forType: .string)
        store.poll(); await settle()
        precondition(store.items.count == 1 && store.items[0].files.count == 3 && store.items[0].text.isEmpty)
        let item = store.items[0]
        precondition(item.files[2].isDirectory && item.files[0].size == 5)
        let copiedObjects = await store.copy(item)
        precondition(copiedObjects)
        let writtenURLs = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        precondition(writtenURLs.map(\.path) == urls.map(\.path))
        store.poll(); await settle(); precondition(store.items.count == 1, "Self copy recaptured")
        board.clearContents(); board.writeObjects(urls.reversed().map { $0 as NSURL }); store.poll(); await settle()
        precondition(store.items.count == 1, "File ordering must not defeat deduplication")
        let files = item.files
        precondition(FilePathFormat.raw.render(files) == files.map(\.path).joined(separator: "\n"))
        precondition(FilePathFormat.mention.render(files) == files.map { "@" + $0.path }.joined(separator: "\n"))
        let shell = FilePathFormat.shell.render(files)
        // Actually round-trip shell quoting using fixture paths, without executing file contents.
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s\\0' " + shell]
        let pipe = Pipe(); process.standardOutput = pipe; try process.run()
        let rendered = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let decoded = String(decoding: rendered, as: UTF8.self).split(separator: "\0").map(String.init)
        precondition(decoded == files.map(\.path))
        try FileManager.default.removeItem(at: urls[0])
        let missingObjectCopy = await store.copy(item)
        precondition(!missingObjectCopy, "Missing file objects copied")
        let missingPathCopy = await store.copy(item, mode: .paths)
        precondition(missingPathCopy, "Missing files must still allow path copy")
        store.clear(); await settle()
        precondition(store.items.isEmpty && FileManager.default.fileExists(atPath: urls[1].path) && FileManager.default.fileExists(atPath: urls[2].path))
        let many = (0..<201).map { directory.appending(path: "file-\($0)") }
        for url in many { try Data().write(to: url) }
        board.clearContents(); board.writeObjects(many.map { $0 as NSURL }); store.poll(); await settle()
        precondition(store.items[0].files.count == 200 && store.error != nil)
        let previous = store.items.count
        board.clearContents(); board.writeObjects([urls[1] as NSURL]); board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        store.poll(); await settle(); precondition(store.items.count == previous)
        print("PASS: file precedence, multiple files/folders, metadata, object writeback, self-copy suppression, deduplication, path formats/shell roundtrip, missing files, reference-only deletion, 200-file cap and sensitive flags")
    }
}
