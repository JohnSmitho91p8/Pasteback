// Exact unversioned 0.2.1 model, compiled in a separate executable/process.
import Foundation
import SwiftData
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
@main struct LegacyHistoryFixture {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: directory.appending(path: "History.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: ClipItem.self, configurations: config)
        let text = ClipItem(text: "legacy code\n    print(1)", imageName: nil, hash: "text", source: "Fixture", sourceID: "fixture")
        text.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!; text.pinned = true
        text.date = Date(timeIntervalSince1970: 100)
        let image = ClipItem(text: "", imageName: "legacy.png", hash: "image", source: "Fixture", sourceID: "fixture")
        try Data([1, 2, 3, 4]).write(to: directory.appending(path: "legacy.png"))
        container.mainContext.insert(text); container.mainContext.insert(image); try container.mainContext.save()
        print("PASS: created genuine unversioned 0.2.1 fixture")
    }
}
