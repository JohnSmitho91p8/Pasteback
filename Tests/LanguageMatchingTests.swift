import Foundation

@main struct LanguageMatchingTests {
    @MainActor static func main() {
        let cases: [([String], String)] = [
            (["zh-Hans-CN"], "zh-Hans"), (["zh-Hant-TW"], "zh-Hans"),
            (["en-GB"], "en"), (["ja-JP"], "ja"), (["fr-CA"], "fr"),
            (["de-DE"], "de"), (["ko-KR"], "ko"),
            (["es-ES", "ja-JP"], "ja"), (["es-ES"], "en"), ([], "en")
        ]
        for (input, expected) in cases { precondition(AppLanguage.match(input) == expected, "Language match failed: \(input)") }
        print("PASS: 10 language preference and English fallback cases.")
    }
}
