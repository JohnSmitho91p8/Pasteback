import SwiftUI
import AppKit

/// Lexical preview only: original text, whitespace and clipboard bytes are never rewritten.
enum CppSyntax {
    enum Kind: Sendable { case comment, string, keyword, type, number, directive, function }
    struct Token: Sendable { let range: NSRange; let kind: Kind }
    struct Result: Sendable { let text: String; let tokens: [Token]; let detected: Bool; let truncated: Bool; let lines: Int }
    static let keywords = Set("alignas alignof asm auto break case catch class concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do dynamic_cast else enum explicit export extern false for friend goto if inline mutable namespace new noexcept nullptr operator private protected public register reinterpret_cast requires return sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid typename union using virtual volatile while".split(separator: " ").map(String.init))
    static let types = Set("bool char char8_t char16_t char32_t double float int long short signed unsigned void wchar_t string vector map set unordered_map unordered_set pair tuple size_t std cin cout cerr endl".split(separator: " ").map(String.init))
    static func analyze(_ original: String) -> Result {
        var prefix = Array(original.utf16.prefix(100_000))
        if let last = prefix.last, (0xD800...0xDBFF).contains(last) { prefix.removeLast() }
        let text = String(decoding: prefix, as: UTF16.self)
        let units = Array(text.utf16)
        var tokens: [Token] = []; var i = 0
        func at(_ index: Int) -> UInt16 { index < units.count ? units[index] : 0 }
        func alpha(_ c: UInt16) -> Bool { (65...90).contains(c) || (97...122).contains(c) || c == 95 || c > 127 }
        func digit(_ c: UInt16) -> Bool { (48...57).contains(c) }
        func add(_ start: Int, _ end: Int, _ kind: Kind) { tokens.append(Token(range: NSRange(location: start, length: end - start), kind: kind)) }
        func rawQuote(_ index: Int) -> Int? {
            guard [82, 76, 85, 117].contains(at(index)) else { return nil }
            for prefix in ["u8R\"", "uR\"", "UR\"", "LR\"", "R\""] {
                let candidate = Array(prefix.utf16)
                if index + candidate.count <= units.count && Array(units[index..<(index + candidate.count)]) == candidate { return index + candidate.count - 1 }
            }
            return nil
        }
        while i < units.count {
            if Task.isCancelled { break }
            let start = i; let c = at(i)
            if c == 47 && at(i + 1) == 47 {
                i += 2; while i < units.count && at(i) != 10 && at(i) != 13 { i += 1 }; add(start, i, .comment)
            } else if c == 47 && at(i + 1) == 42 {
                i += 2; while i < units.count && !(at(i) == 42 && at(i + 1) == 47) { i += 1 }; i = min(i + 2, units.count); add(start, i, .comment)
            } else if let quote = rawQuote(i) { // C++ raw string, including u8/u/U/L prefixes
                var open = quote + 1
                while open < min(quote + 18, units.count) && at(open) != 40 && at(open) != 10 { open += 1 }
                if at(open) == 40 {
                    let delimiter = Array(units[(quote + 1)..<open]); let endMarker: [UInt16] = [41] + delimiter + [34]
                    i = open + 1
                    while i < units.count {
                        if i + endMarker.count <= units.count && Array(units[i..<(i + endMarker.count)]) == endMarker { i += endMarker.count; break }; i += 1
                    }
                    add(start, i, .string)
                } else { i += 1 }
            } else if c == 34 || c == 39 {
                i += 1
                while i < units.count {
                    if at(i) == 92 { i = min(i + 2, units.count) }
                    else if at(i) == c { i += 1; break }
                    else { i += 1 }
                }; add(start, i, .string)
            } else if c == 35 {
                i += 1; while at(i) == 32 || at(i) == 9 { i += 1 }
                while alpha(at(i)) { i += 1 }; add(start, i, .directive)
            } else if digit(c) {
                i += 1
                while digit(at(i)) || alpha(at(i)) || at(i) == 46 || at(i) == 39 || ((at(i) == 43 || at(i) == 45) && [69,101,80,112].contains(at(i - 1))) { i += 1 }
                add(start, i, .number)
            } else if alpha(c) {
                i += 1; while alpha(at(i)) || digit(at(i)) { i += 1 }
                let word = String(decoding: units[start..<i], as: UTF16.self)
                if keywords.contains(word) { add(start, i, .keyword) }
                else if types.contains(word) { add(start, i, .type) }
                else {
                    var next = i; while at(next) == 32 || at(next) == 9 { next += 1 }
                    if at(next) == 40 { add(start, i, .function) }
                }
            } else { i += 1 }
        }
        var code = units
        for token in tokens where token.kind == .comment || token.kind == .string {
            for n in token.range.location..<NSMaxRange(token.range) where code[n] != 10 && code[n] != 13 { code[n] = 32 }
        }
        let masked = String(decoding: code, as: UTF16.self)
        let detected = masked.range(of: #"(?m)^\s*#\s*include\b|\busing\s+namespace\s+std\b|\bstd\s*::|\b(?:int|signed|auto)\s+main\s*\(|\b(?:cin|cout|cerr)\s*(?:<<|>>)"#, options: .regularExpression) != nil
        // NSString line boundaries handle CRLF without counting it twice.
        var lines = 1; var n = 0
        while n < units.count { if units[n] == 13 { lines += 1; if n + 1 < units.count && units[n + 1] == 10 { n += 1 } } else if units[n] == 10 { lines += 1 }; n += 1 }
        return Result(text: text, tokens: tokens, detected: detected, truncated: text != original, lines: lines)
    }
}

struct CppContentView: View {
    let text: String
    @State private var mode = "auto"
    @State private var result: CppSyntax.Result?
    private var code: Bool { mode == "cpp" || (mode == "auto" && result?.detected == true) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if code { Text("C++").font(.system(.caption, design: .monospaced)).foregroundStyle(.teal) }
                Spacer()
                Picker(tr("预览方式"), selection: $mode) {
                    Text(tr("自动识别")).tag("auto")
                    Text(tr("纯文本")).tag("text")
                    Text("C++").tag("cpp")
                }.labelsHidden().frame(width: 130).accessibilityLabel(tr("预览方式"))
            }
            if let result {
                if code {
                    CppTextPreview(result: result)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(tr("保留原始缩进 · Tab 宽度 4 · 复制内容不变")).font(.caption2).foregroundStyle(.secondary)
                } else {
                    ScrollView { Text(text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
                if code && result.truncated { Text(tr("内容较长，仅预览前十万字符；复制全部仍保留完整内容。")).font(.caption).foregroundStyle(.secondary) }
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: text) {
            let input = text
            let worker = Task.detached(priority: .userInitiated) { CppSyntax.analyze(input) }
            let value = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            if !Task.isCancelled { result = value }
        }
    }
}

struct CppTextPreview: NSViewRepresentable {
    let result: CppSyntax.Result
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        let view = NSTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isHorizontallyResizable = true; view.isVerticallyResizable = true
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.containerSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainerInset = NSSize(width: 14, height: 14)
        view.setAccessibilityLabel("C++")
        scroll.documentView = view
        scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        scroll.verticalRulerView = CppLineRuler(scrollView: scroll, orientation: .verticalRuler)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let key = (colorScheme == .dark ? "dark" : "light") + result.text
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        let background = NSColor.textBackgroundColor
        let foreground = NSColor.labelColor
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let style = NSMutableParagraphStyle(); style.minimumLineHeight = 20; style.maximumLineHeight = 20
        style.tabStops = []; style.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width * 4
        let attributed = NSMutableAttributedString(string: result.text, attributes: [.font: font, .foregroundColor: foreground, .paragraphStyle: style])
        for token in result.tokens {
            let color: NSColor
            switch token.kind {
            case .comment: color = .systemGreen
            case .string: color = .systemRed
            case .keyword: color = .systemPurple
            case .type, .directive: color = .systemBlue
            case .number: color = .systemTeal
            case .function: color = .systemOrange
            }
            attributed.addAttribute(.foregroundColor, value: color, range: token.range)
        }
        view.backgroundColor = background; scroll.backgroundColor = background
        view.textStorage?.setAttributedString(attributed)
        view.sizeToFit()
        if let ruler = scroll.verticalRulerView as? CppLineRuler { ruler.lineCount = result.lines; ruler.needsDisplay = true }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var key = "" }
}

final class CppLineRuler: NSRulerView {
    var lineCount = 1
    override var isFlipped: Bool { true }
    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation); ruleThickness = 52
        clientView = scrollView?.documentView
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let scrollView else { return }
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        let offset = scrollView.contentView.bounds.minY
        let first = max(0, Int((offset - 14) / 20))
        let last = min(lineCount - 1, first + Int(bounds.height / 20) + 2)
        guard first <= last else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        for line in first...last {
            let label = String(line + 1) as NSString
            label.draw(at: NSPoint(x: ruleThickness - label.size(withAttributes: attrs).width - 12, y: CGFloat(line) * 20 + 16 - offset), withAttributes: attrs)
        }
    }
}
