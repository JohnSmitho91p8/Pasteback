import Foundation

@main struct WorkspacePresentationTests {
    @MainActor static func main() throws {
        precondition(ClipCategory.classify(text: "Hello, world.", image: false, files: false) == .text)
        precondition(ClipCategory.classify(text: "https://example.com/a?x=2", image: false, files: false) == .link)
        precondition(ClipCategory.classify(text: "HTTPS://example.com", image: false, files: false) == .link)
        precondition(ClipCategory.classify(text: "http:// is just a prefix", image: false, files: false) == .text)
        precondition(ClipCategory.classify(text: "https://example.com\nnotes", image: false, files: false) == .text)
        precondition(ClipCategory.classify(text: "#include <iostream>\nint main() { return 0; }", image: false, files: false) == .code)
        precondition(ClipCategory.classify(text: "A sentence; with punctuation.", image: false, files: false) == .text)
        precondition(ClipCategory.classify(text: "{}", image: true, files: false) == .image)
        precondition(ClipCategory.classify(text: "#include", image: false, files: true) == .all)
        let source = "#include <iostream>\n\tint main() {\n return 0;\n}\n"
        let item = ClipItem(text: source, imageName: nil, hash: "fixture", source: "Test", sourceID: "test")
        precondition(ClipPresentationCache.shared.kind(item) == .code)
        item.pinned = true
        precondition(ClipPresentationCache.shared.kind(item) == .code)
        precondition(item.text == source)
        precondition(ClipCategory.allCases.count == 6)
        print("PASS: display categories, URL/code heuristics, file/image precedence, cached pin independence and original content preservation.")
    }
}
