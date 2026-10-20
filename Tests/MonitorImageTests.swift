import AppKit
import Foundation
import CoreFoundation
import ImageIO
import UniformTypeIdentifiers
@main struct MonitorImageTests {
    @MainActor private static func pumpEvents() { CFRunLoopRunInMode(.defaultMode, 0.002, false) }
    @MainActor static func main() async throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appending(path: "PastebackImages-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipStore(inMemory: true, monitor: true, pasteboard: board, storageDirectory: directory)
        var times: [Double] = []
        for index in 0..<100 {
            let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: CGFloat(index) / 100, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            let bytes = NSMutableData(); let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "fixture-\(index)"]] as CFDictionary); precondition(CGImageDestinationFinalize(destination))
            board.clearContents(); board.setData(bytes as Data, forType: .png)
            let start = Date()
            while store.items.count != index + 1 && Date().timeIntervalSince(start) < 2 {
                pumpEvents(); try await Task.sleep(for: .milliseconds(1))
            }
            precondition(store.items.count == index + 1, "Image fixture \(index), count \(store.items.count), error \(store.error ?? "none"), images \(store.recordImages), limit \(store.limit)")
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        times.sort(); precondition(times[95] < 500)
        print("PASS: 100/100 automatically monitored PNG images; median \(Int(times[50])) ms, p95 \(Int(times[95])) ms, max \(Int(times.last!)) ms")
    }
}
