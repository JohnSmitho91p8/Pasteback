import Foundation
@main struct UpdateCheckerTests {
    static func main() throws {
        precondition(ReleaseVersion("v0.1.1")! > ReleaseVersion("0.1.0")!)
        precondition(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.9")!)
        precondition(ReleaseVersion("1.0")! == ReleaseVersion("1.0.0")!)
        for value in ["latest", "1.0-beta", "1..0", "-1.2.3", "1.2.3.4"] { precondition(ReleaseVersion(value) == nil) }
        func release(_ url: String, tag: String = "v0.2.0", prerelease: Bool = false) -> GitHubRelease {
            GitHubRelease(tag_name: tag, html_url: URL(string: url)!, draft: false, prerelease: prerelease)
        }
        precondition(release("https://github.com/JohnSmitho91p8/Pasteback/releases/tag/v0.2.0").isTrusted())
        precondition(!release("https://evil.example/release").isTrusted())
        precondition(!release("https://github.com/other/Pasteback/releases/tag/v0.2.0").isTrusted())
        precondition(!release("https://github.com/JohnSmitho91p8/Pasteback/releases/tag/v0.2.0", prerelease: true).isTrusted())
        print("PASS: version comparisons, invalid versions and trusted stable release URLs.")
    }
}
