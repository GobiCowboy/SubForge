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
      "storeURL": "https://apps.apple.com/cn/mac/search?term=SubForge",
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

@Test func helpDocumentDecodesRichContentBlocks() throws {
    let json = """
    {
      "version": "1.0.7",
      "title": "SubForge 使用帮助",
      "sections": [{
        "title": "五步完成字幕",
        "body": "兼容旧客户端的摘要",
        "bullets": [],
        "style": "feature",
        "icon": "wand.and.stars",
        "blocks": [
          {"type": "steps", "items": ["导入", "导出"]},
          {
            "type": "image",
            "url": "https://gobicowboy.cn/projects/subforge/content/media/workflow.png",
            "sha256": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "alt": "字幕工作流"
          }
        ]
      }]
    }
    """.data(using: .utf8)!

    let document = try JSONDecoder().decode(VersionHelpDocument.self, from: json)
    #expect(document.sections.first?.style == "feature")
    #expect(document.sections.first?.blocks?.count == 2)
    #expect(document.sections.first?.blocks?.last?.sha256?.hasPrefix("sha256:") == true)
}

@Test func versionContentImageURLsStayOnContentDomain() {
    #expect(
        VersionContentRuntime.isAllowedContentURL(
            URL(string: "https://gobicowboy.cn/projects/subforge/content/media/help.png")!
        )
    )
    #expect(
        !VersionContentRuntime.isAllowedContentURL(
            URL(string: "https://example.com/help.png")!
        )
    )
}

@Test func appStoreUpdateURLsOpenTheMacAppStoreScheme() {
    let url = URL(string: "https://apps.apple.com/cn/mac/search?term=SubForge")!
    #expect(VersionContentRuntime.appStoreURL(for: url)?.scheme == "macappstore")
    #expect(VersionContentRuntime.appStoreURL(for: url)?.host == "apps.apple.com")
    #expect(VersionContentRuntime.appStoreURL(for: URL(string: "https://gobicowboy.cn/projects/subforge/")!) == nil)
}

@Test func feedbackMailPrefillsContextWithoutPrivateAttachments() throws {
    let url = try #require(
        FeedbackComposer.mailURL(
            type: .problemReport,
            section: .updates,
            details: "点击意见反馈后没有看到输入框。"
        )
    )
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(components.scheme == "mailto")
    #expect(components.path == FeedbackComposer.recipient)
    #expect(query["subject"]?.contains("问题反馈") == true)
    #expect(query["body"]?.contains("产品：SubForge") == true)
    #expect(query["body"]?.contains("当前页面/模块：检查更新") == true)
    #expect(query["body"]?.contains("点击意见反馈后没有看到输入框") == true)
    #expect(query["body"]?.contains("不会自动附加日志") == true)
}
