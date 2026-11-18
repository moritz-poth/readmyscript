import Foundation

/// Where VoiceStudio comes from and how a download is recognised as genuine. Used by the app's installer.
public enum StudioRelease {
    /// Latest stable release (no test versions) of the official repository.
    public static let api = URL(string: "https://api.github.com/repos/debpalash/VoiceStudio/releases/latest")!
    public static let page = URL(string: "https://github.com/debpalash/VoiceStudio/releases/latest")!
    public static let bundleID = "com.voicestudio.desktop"
    /// Apple Developer ID team that signs and notarises VoiceStudio. A download signed by anyone else is rejected.
    public static let teamID = "CR8M2NTH2K"
    /// Downloads must come from this repository's releases.
    public static let downloadPrefix = "https://github.com/debpalash/VoiceStudio/releases/download/"

    public struct Asset: Equatable, Sendable {
        public var version: String
        public var zip: URL
        public var zipName: String
        public var checksums: URL
    }

    /// The Mac zip for this processor ("arm64" or "x64") and the checksum list, from GitHub's release JSON.
    public static func asset(fromJSON data: Data, arch: String) -> Asset? {
        struct A: Decodable { let name: String; let browser_download_url: URL }
        struct R: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool; let assets: [A] }
        guard let r = try? JSONDecoder().decode(R.self, from: data), !r.draft, !r.prerelease else { return nil }
        let version = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        guard let zip = r.assets.first(where: { $0.name == "VoiceStudio-\(version)-mac-\(arch).zip" }),
              let sums = r.assets.first(where: { $0.name == "SHA256SUMS.txt" }),
              [zip, sums].allSatisfy({ $0.browser_download_url.absoluteString.hasPrefix(downloadPrefix) })
        else { return nil }
        return Asset(version: version, zip: zip.browser_download_url, zipName: zip.name, checksums: sums.browser_download_url)
    }

    /// SHA-256 (lower-case hex) of `file` in a `sha256sum` list ("<hex>  <name>").
    public static func checksum(for file: String, in list: String) -> String? {
        for line in list.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == file else { continue }
            let hex = parts[0].lowercased()
            if hex.count == 64, hex.allSatisfy(\.isHexDigit) { return hex }
        }
        return nil
    }
}
