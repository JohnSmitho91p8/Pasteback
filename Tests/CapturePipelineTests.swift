import AppKit
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct CapturePipelineTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PastebackCaptureTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = try ClipStore(inMemory: true, monitor: false, pasteboard: board, storageDirectory: directory)
        func image(_ width: Int, _ height: Int, type: UTType) -> Data {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0.15, green: 0.6, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = NSMutableData()
            let dest = CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil)!
            let props: CFDictionary = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]] as CFDictionary
            CGImageDestinationAddImage(dest, context.makeImage()!, props)
            precondition(CGImageDestinationFinalize(dest))
            return bytes as Data
        }
        func settle() async {
            let deadline = Date().addingTimeInterval(5)
            while (store.reading || store.processing) && Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
            precondition(!store.reading && !store.processing, "Capture timeout")
        }
        let tiff = image(3000, 2200, type: .tiff)
        precondition(tiff.count > 20_000_000, "Fixture must exceed the old screenshot limit")
        board.clearContents(); board.setData(tiff, forType: .tiff)
        let start = Date()
        store.poll(); await settle()
        precondition(store.items.count == 1 && store.items[0].imageName?.hasSuffix(".tiff") == true)
        let saved = try Data(contentsOf: directory.appending(path: store.items[0].imageName!))
        precondition(saved == tiff, "Original screenshot bytes changed")
        print("PASS: first 3000×2200 TIFF (\(tiff.count / 1_000_000) MB) saved in \(Int(Date().timeIntervalSince(start) * 1000)) ms after detection.")
        let png = image(800, 600, type: .png)
        board.declareTypes([.png], owner: nil)
        let advertisedChange = board.changeCount
        store.poll(); await settle()
        precondition(store.items.count == 1)
        board.setData(png, forType: .png)
        precondition(board.changeCount == advertisedChange)
        store.poll(); await settle()
        precondition(store.items.count == 2, "Deferred bytes for the same change were missed")
        print("PASS: delayed provider data retried without needing a second copy.")
        for text in ["queue A", "queue B", "queue C"] {
            board.clearContents(); board.setString(text, forType: .string); store.poll()
            while store.reading { try? await Task.sleep(for: .milliseconds(1)) }
        }
        await settle()
        precondition(store.items.prefix(3).map(\.text) == ["queue C", "queue B", "queue A"])
        print("PASS: three snapshots queued while the worker was busy, in chronological order.")
        for type in [UTType.jpeg, .gif, .heic] {
            let data = image(80, 60, type: type)
            board.clearContents(); board.setData(data, forType: .init(type.identifier))
            store.poll(); await settle()
            precondition(store.items.first?.imageName != nil)
        }
        print("PASS: JPEG, GIF and HEIC image representations.")
        let prior = store.items.count
        board.clearContents(); board.setString("secret", forType: .string)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        store.poll(); await settle()
        precondition(store.items.count == prior, "Sensitive contents captured")
        store.paused = true
        board.clearContents(); board.setString("paused", forType: .string); store.poll()
        store.paused = false
        store.poll(); await settle()
        precondition(store.items.count == prior, "Paused contents captured after resume")
        print("PASS: sensitive flags and paused content stay excluded.")
        let code = "func greet() {\n    print(\"Hello, 世界\")\n}\n"
        board.clearContents(); board.setString(code, forType: .string); store.poll(); await settle()
        precondition(store.items.first?.text == code, "Code whitespace changed")
        // A newer owner must invalidate the old snapshot; never mix generations.
        board.clearContents(); board.setString("obsolete owner", forType: .string); store.poll()
        board.clearContents(); board.setString("latest owner", forType: .string)
        await settle(); store.poll(); await settle()
        precondition(store.items.first?.text == "latest owner")
        print("PASS: code whitespace preserved and rapid ownership changes settle to newest content.")
        board.clearContents(); board.setString("cancelled capture", forType: .string); store.poll()
        store.clear(); await settle()
        precondition(store.items.isEmpty, "An in-flight capture returned after clear")
        print("PASS: clear invalidated in-flight and queued captures.")
    }
}
