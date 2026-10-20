import AppKit
import Foundation
import CoreFoundation

@main struct MonitorLatencyTests {
    @MainActor private static func pumpEvents() { CFRunLoopRunInMode(.defaultMode, 0.002, false) }
    @MainActor static func main() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appending(path: "PastebackMonitor-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipStore(inMemory: true, monitor: true, pasteboard: board, storageDirectory: directory)
        var times: [Double] = []
        for index in 0..<100 {
            let code = "// Capture \(index)\nlet message = \"你好 / Hello\"\n"
            board.clearContents(); board.setString(code, forType: .string)
            let start = Date()
            while store.items.first?.text != code && Date().timeIntervalSince(start) < 2 {
                pumpEvents()
                try await Task.sleep(for: .milliseconds(1))
            }
            precondition(store.items.first?.text == code, "Monitor missed item \(index)")
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        precondition(store.items.count == 100)
        times.sort()
        print("PASS: 100/100 automatically monitored Unicode/code copies; median \(Int(times[50])) ms, p95 \(Int(times[95])) ms, max \(Int(times.last!)) ms (copy to visible model).")
        // Generous regression guard for CI scheduling; reported values are measurements, not an SLA.
        precondition(times[95] < 500, "Capture latency regression")
    }
}
