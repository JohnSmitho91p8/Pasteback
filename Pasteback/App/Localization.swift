import Foundation
import Observation

extension Notification.Name {
    static let pastebackLanguageChanged = Notification.Name("PastebackLanguageChanged")
}

@MainActor @Observable final class AppLanguage {
    static let shared = AppLanguage()
    static let options: [(code: String, name: String)] = [
        ("en", "English"), ("zh-Hans", "简体中文"), ("ja", "日本語"),
        ("fr", "Français"), ("de", "Deutsch"), ("ko", "한국어")
    ]
    var selection: String {
        didSet {
            UserDefaults.standard.set(selection, forKey: "appLanguage")
            NotificationCenter.default.post(name: .pastebackLanguageChanged, object: nil)
        }
    }
    private let strings: [String: [String: String]]
    init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "auto"
        selection = saved == "auto" || Self.options.contains(where: { $0.code == saved }) ? saved : "auto"
        if let url = Bundle.main.url(forResource: "Localizations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            strings = decoded
        } else { strings = [:] }
    }
    static func match(_ preferred: [String]) -> String {
        for language in preferred {
            let base = language.lowercased().split(separator: "-").first.map(String.init) ?? ""
            if base == "zh" { return "zh-Hans" }
            if options.contains(where: { $0.code == base }) { return base }
        }
        return "en"
    }
    var code: String { selection == "auto" ? Self.match(Locale.preferredLanguages) : selection }
    var locale: Locale { Locale(identifier: code) }
    func text(_ key: String) -> String { strings[key]?[code] ?? strings[key]?["en"] ?? key }
}

@MainActor func tr(_ key: String) -> String { AppLanguage.shared.text(key) }
@MainActor func trCount(_ count: Int) -> String {
    String(format: tr("条数"), locale: AppLanguage.shared.locale, count)
}
@MainActor func trFormat(_ key: String, _ value: String) -> String {
    String(format: tr(key), locale: AppLanguage.shared.locale, value)
}
