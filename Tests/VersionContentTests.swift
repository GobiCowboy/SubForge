import Foundation
import Testing
@testable import SubForge

@Test func semanticVersionsCompareNumerically() {
    #expect(AppVersion("1.0") == AppVersion("1.0.0"))
    #expect(AppVersion("1.9.0")! < AppVersion("1.10.0")!)
    #expect(AppVersion("2.0.0")! > AppVersion("1.99.99")!)
}

@Test func semanticVersionRejectsUnstableFormats() {
    #expect(AppVersion("1.2.3.4") == nil)
    #expect(AppVersion("1.2.beta") == nil)
    #expect(AppVersion("1..2") == nil)
}

@Test func versionContentManifestRequiresAppIdentityAndHashes() throws {
    let json = """
    {
      "schemaVersion": 1,
      "appID": "com.jago.subforge",
      "latestVersion": "1.0.7",
      "storeURL": "https://gobicowboy.cn/projects/subforge/",
      "channels": {},
      "releases": [{
        "version": "1.0.7",
        "releaseURL": "releases/1.0.7.json",
        "releaseSHA256": "sha256:abc",
        "helpVersion": "1.0.7",
        "helpURL": "help/1.0.7.json",
        "helpSHA256": "sha256:def"
      }]
    }
    """.data(using: .utf8)!

    let manifest = try JSONDecoder().decode(VersionContentManifest.self, from: json)
    #expect(manifest.appID == "com.jago.subforge")
    #expect(manifest.releases.first?.helpSHA256 == "sha256:def")
}

@Test func versionContentCacheComputesSha256() {
    #expect(
        VersionContentCache.sha256(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
}
