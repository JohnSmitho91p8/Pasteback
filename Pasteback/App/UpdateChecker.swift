import AppKit
import Foundation
import Observation

struct ReleaseVersion: Comparable {
    let components: [Int]
    init?(_ value: String) {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    func isTrusted() -> Bool {
        html_url.scheme == "https" && html_url.host == "github.com"
            && html_url.user == nil && html_url.password == nil && html_url.port == nil
            && html_url.path.hasPrefix("/JohnSmitho91p8/Pasteback/releases/tag/")
            && !draft && !prerelease && ReleaseVersion(tag_name) != nil
    }
}

@MainActor @Observable final class UpdateChecker {
    static let shared = UpdateChecker()
    private(set) var checking = false
    static let releasesURL = URL(string: "https://github.com/JohnSmitho91p8/Pasteback/releases/latest")!
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/JohnSmitho91p8/Pasteback/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Pasteback/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 { show(title: tr("尚无可用版本"), message: tr("请稍后再检查更新。")); return }
            guard http.statusCode == 200, data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard release.isTrusted(), let latest = ReleaseVersion(release.tag_name), let current = ReleaseVersion(currentVersion) else { throw URLError(.cannotParseResponse) }
            if latest > current {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = tr("发现新版本") + " " + release.tag_name
                alert.informativeText = tr("更新下载安装说明")
                alert.addButton(withTitle: tr("前往下载")); alert.addButton(withTitle: tr("取消"))
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.html_url) }
            } else { show(title: tr("已经是最新版本"), message: "Pasteback \(currentVersion)") }
        } catch { show(title: tr("暂时无法检查更新"), message: tr("请检查网络后重试。")) }
    }
    private func show(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: tr("完成")); alert.runModal()
    }
}
