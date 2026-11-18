import Foundation
import Testing
@testable import ScriptCore

struct StudioReleaseTests {
    func json(prerelease: Bool = false, host: String = "https://github.com/debpalash/VoiceStudio/releases/download/v0.5.8/") -> Data {
        Data("""
        {"tag_name":"v0.5.8","draft":false,"prerelease":\(prerelease),"assets":[
         {"name":"VoiceStudio-0.5.8-mac-arm64.zip","browser_download_url":"\(host)VoiceStudio-0.5.8-mac-arm64.zip"},
         {"name":"VoiceStudio-0.5.8-mac-x64.zip","browser_download_url":"\(host)VoiceStudio-0.5.8-mac-x64.zip"},
         {"name":"VoiceStudio-0.5.8-mac-arm64.dmg","browser_download_url":"\(host)VoiceStudio-0.5.8-mac-arm64.dmg"},
         {"name":"SHA256SUMS.txt","browser_download_url":"\(host)SHA256SUMS.txt"}]}
        """.utf8)
    }

    @Test func picksTheZipForThisProcessor() throws {
        let a = try #require(StudioRelease.asset(fromJSON: json(), arch: "arm64"))
        #expect(a.version == "0.5.8")
        #expect(a.zipName == "VoiceStudio-0.5.8-mac-arm64.zip")
        #expect(StudioRelease.asset(fromJSON: json(), arch: "x64")?.zipName == "VoiceStudio-0.5.8-mac-x64.zip")
    }

    @Test func refusesTestVersionsAndOtherHosts() {
        #expect(StudioRelease.asset(fromJSON: json(prerelease: true), arch: "arm64") == nil)
        #expect(StudioRelease.asset(fromJSON: json(host: "https://example.com/"), arch: "arm64") == nil)
    }

    @Test func readsChecksums() {
        let list = """
        378db9d7bf71a69a227b0f442d40acfe957a09d1a8ce17566059b235b8ed209e  VoiceStudio-0.5.8-mac-arm64.dmg
        d8a3929175c1c051c78513ceb71e39a2f2c76a623a3d3a4011e380501561f44a  VoiceStudio-0.5.8-mac-arm64.zip
        200715d04d2e6f655e1e0106d0e461c039ea73e875676a1e1ecc641717421987  VoiceStudio-0.5.8-mac-arm64.zip.blockmap
        """
        #expect(StudioRelease.checksum(for: "VoiceStudio-0.5.8-mac-arm64.zip", in: list) == "d8a3929175c1c051c78513ceb71e39a2f2c76a623a3d3a4011e380501561f44a")
        #expect(StudioRelease.checksum(for: "missing.zip", in: list) == nil)
        #expect(StudioRelease.checksum(for: "x.zip", in: "nothex  x.zip") == nil)
    }
}
