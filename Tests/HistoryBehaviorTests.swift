import Foundation
import AppKit
import SwiftData

@main struct HistoryBehaviorTests {
    @MainActor static func main() throws {
        let store = try ClipStore(inMemory: true, monitor: false)
        func add(_ label: String, time: Double, pinned: Bool = false) -> ClipItem {
            let item = ClipItem(text: label, imageName: nil, hash: label, source: "Test", sourceID: "test")
            item.date = Date(timeIntervalSince1970: time); item.pinned = pinned
            store.container.mainContext.insert(item); store.items.append(item)
            return item
        }
        let oldest = add("old pinned", time: 100, pinned: true)
        let newest = add("newest", time: 300)
        let middle = add("middle", time: 200)
        store.save()
        precondition(store.items.map(\.text) == ["newest", "middle", "old pinned"])
        store.pin(newest)
        precondition(store.items.map(\.text) == ["newest", "middle", "old pinned"])
        store.reload()
        precondition(store.items.map(\.text) == ["newest", "middle", "old pinned"])
        middle.date = Date(timeIntervalSince1970: 400); store.save()
        precondition(store.items.first?.id == middle.id)
        store.remove(middle)
        precondition(store.items.map(\.text) == ["newest", "old pinned"])
        let afterDelete = try store.container.mainContext.fetchCount(FetchDescriptor<ClipItem>())
        precondition(afterDelete == 2)
        let board = NSPasteboard.withUniqueName()
        board.setString("disposable test clipboard", forType: .string)
        store.clearClipboard(board)
        precondition(board.string(forType: .string) == nil)
        precondition(store.items.count == 2)
        store.clear()
        precondition(store.items.isEmpty)
        let afterClear = try store.container.mainContext.fetchCount(FetchDescriptor<ClipItem>())
        precondition(afterClear == 0)
        board.releaseGlobally()
        _ = oldest
        print("PASS: newest-first order, pin stability, reload order, recopy order, deletion, isolated clipboard clear and history clear.")
    }
}
