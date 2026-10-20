import Foundation
import CryptoKit

/// Verifies the real release bytes, not a second implementation of the updater.
@main struct UpdateCheckerTests {
    static func main() throws {
        precondition(CommandLine.arguments.count == 4, "Pass appcast.xml, update.zip and built Info.plist")
        let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let plist = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as! [String: Any]
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
        precondition(info["SURequireSignedFeed"] as? Bool == true)
        precondition(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        precondition(info["SUEnableAutomaticChecks"] as? Bool == false)
        precondition(info["SUAutomaticallyUpdate"] as? Bool == false)
        precondition(info["SUEnableSystemProfiling"] as? Bool == false)
        precondition(info["SUFeedURL"] as? String == "https://raw.githubusercontent.com/JohnSmitho91p8/Pasteback/main/appcast.xml")
        let xml = String(decoding: feed, as: UTF8.self)
        func capture(_ pattern: String) -> String {
            let regex = try! NSRegularExpression(pattern: pattern)
            let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml))!
            return String(xml[Range(match.range(at: 1), in: xml)!])
        }
        let feedSignature = Data(base64Encoded: capture("edSignature: ([A-Za-z0-9+/=]+)"))!
        let signedLength = Int(capture("length: ([0-9]+)"))!
        precondition(key.isValidSignature(feedSignature, for: feed.prefix(signedLength)))
        let archiveSignature = Data(base64Encoded: capture("sparkle:edSignature=\"([^\"]+)\""))!
        precondition(Int(capture(" length=\"([0-9]+)\"")) == archive.count)
        precondition(key.isValidSignature(archiveSignature, for: archive))
        var corrupted = archive; corrupted[0] ^= 1
        precondition(!key.isValidSignature(archiveSignature, for: corrupted))
        var badFeed = Data(feed.prefix(signedLength)); badFeed[0] ^= 1
        precondition(!key.isValidSignature(feedSignature, for: badFeed))
        print("PASS: signed feed + archive verified; tampered feed/archive rejected; manual-only privacy configuration verified.")
    }
}
