import Foundation
import AppKit

@main struct CppPreviewTests {
    static func main() {
        let sample = "#include <iostream>\r\nusing namespace std;\r\nint main() {\r\n\tstring s = \"hello 中文🙂 \\\"world\\\"\"; // return 42\r\n\tcout << s << 0xFF;\r\n\treturn 0;\r\n}\r\n"
        let result = CppSyntax.analyze(sample)
        precondition(result.detected && result.text == sample && !result.truncated && result.lines == 8)
        let ns = sample as NSString
        func has(_ text: String, _ kind: CppSyntax.Kind) -> Bool { result.tokens.contains { $0.kind == kind && ns.substring(with: $0.range) == text } }
        precondition(has("#include", .directive) && has("return", .keyword) && has("int", .type) && has("main", .function) && has("0xFF", .number) && has("// return 42", .comment))
        precondition(result.tokens.contains { $0.kind == .string && ns.substring(with: $0.range).contains("中文🙂") })
        precondition(!CppSyntax.analyze("Remember to return 42 tomorrow. This is ordinary prose.").detected)
        precondition(!CppSyntax.analyze("// #include <vector>\n/* int main() {} */\n\"std::cout\"").detected)
        let raw = "auto s = R\"tag(中文 { \\\" // return\nnext)tag\"; int main() {}"
        let rawResult = CppSyntax.analyze(raw)
        precondition(rawResult.detected && rawResult.tokens.filter { $0.kind == .string }.count == 1)
        precondition(CppSyntax.analyze("/* unclosed").tokens.count == 1)
        precondition(CppSyntax.analyze("\"escaped\\\" string\"").tokens.count == 1)
        precondition(CppSyntax.analyze("").lines == 1)
        precondition(CppSyntax.analyze("a\rb\nc\r\nd").lines == 4)
        let long = String(repeating: "int main() { return 0; }\n", count: 20_000)
        let start = Date(); let bounded = CppSyntax.analyze(long)
        precondition(bounded.truncated && bounded.text.utf16.count <= 100_000 && bounded.detected)
        for token in bounded.tokens { precondition(NSMaxRange(token.range) <= bounded.text.utf16.count) }
        let emoji = CppSyntax.analyze(String(repeating: "🙂", count: 100_000))
        precondition(emoji.text.utf16.count == 100_000 && !emoji.text.contains("�"))
        print("PASS: C++ detection, tokens, Unicode/CRLF/raw strings, unchanged original whitespace and bounded preview; large analysis \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
}
