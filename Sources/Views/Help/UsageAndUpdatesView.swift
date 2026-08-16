import AppKit
import SwiftUI

struct UsageAndUpdatesView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var contentService: VersionContentService
    @Environment(\.openURL) private var openURL
    @State private var selection: UsageAndUpdatesSection = .help

    var body: some View {
        HStack(spacing: 0) {
            navigationRail

            Divider()

            ScrollView {
                content
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 30)
            }
            .scrollIndicators(.automatic)
            .background(.regularMaterial)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 600, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            UsageAndUpdatesWindowBehavior()
                .frame(width: 0, height: 0)
        }
        .onAppear {
            selection = appModel.requestedUsageAndUpdatesSection
            contentService.start()
        }
        .onChange(of: appModel.requestedUsageAndUpdatesSection) { _, section in
            selection = section
        }
    }

    private var navigationRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("帮助与更新")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("SubForge")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 26)

            ForEach(UsageAndUpdatesSection.allCases) { section in
                navigationButton(for: section)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 7) {
                Text("当前版本")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(verbatim: "v\(VersionContentRuntime.appVersion)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(20)
        .frame(minWidth: 214, idealWidth: 214, maxWidth: 214, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
    }

    private func navigationButton(for section: UsageAndUpdatesSection) -> some View {
        Button {
            selection = section
            if section == .updates {
                contentService.checkForUpdates()
            }
        } label: {
            Label(section.rawValue, systemImage: section.systemImage)
                .font(.system(size: 13, weight: selection == section ? .semibold : .regular))
                .foregroundStyle(selection == section ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(
                    selection == section ? Color.accentColor.opacity(0.13) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(alignment: .leading) {
                    if selection == section {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 3)
                            .padding(.vertical, 8)
                    }
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(section.rawValue)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .help:
            UsageHelpContent(document: contentService.currentHelp)
        case .news:
            LatestNewsContent(
                notes: contentService.releaseNotes,
                onOpenVideo: { url in
                    openURL(url)
                    return .handled
                }
            )
        case .updates:
            UpdatesContent(
                state: contentService.state,
                currentVersion: VersionContentRuntime.appVersion,
                latestVersion: contentService.latestVersion,
                latestRelease: contentService.latestRelease,
                updateNotes: contentService.releaseNotes.filter {
                    (AppVersion($0.version) ?? VersionContentRuntime.appVersion) > VersionContentRuntime.appVersion
                },
                downloadURL: contentService.downloadURL,
                onCheck: { contentService.checkForUpdates() },
                onOpenDownload: { url in
                    openUpdateURL(url)
                }
            )
        case .feedback:
            FeedbackContentView(currentSection: selection)
        }
    }

    private func openUpdateURL(_ url: URL) -> OpenURLAction.Result {
        if let appStoreURL = VersionContentRuntime.appStoreURL(for: url),
           NSWorkspace.shared.open(appStoreURL) {
            return .handled
        }

        openURL(url)
        return .handled
    }

}

struct UsageHelpContent: View {
    let document: VersionHelpDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(
                eyebrow: "HELP CENTER",
                title: "使用帮助",
                subtitle: "从导入音频到导出字幕，快速了解 SubForge 的工作流。"
            )

            HelpIntroCard(
                title: "从音频到字幕",
                bodyText: "SubForge 把导入、转写、编辑和导出集中在一条工作流里，适合配合 Final Cut Pro 使用。"
            )

            ForEach(document.sections) { section in
                HelpSectionCard(section: section)
            }
        }
    }
}

struct LatestNewsContent: View {
    let notes: [VersionReleaseNote]
    let onOpenVideo: (URL) -> OpenURLAction.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(
                eyebrow: "WHAT'S NEW",
                title: "最新动态",
                subtitle: "了解 SubForge 最近发生的变化。"
            )

            if let latest = notes.last {
                ReleaseHighlight(
                    note: latest,
                    eyebrow: "最新动态",
                    actionTitle: latest.videoURL == nil ? nil : "观看演示",
                    onAction: {
                        guard let videoURL = latest.videoURL.flatMap(URL.init(string:)) else { return }
                        _ = onOpenVideo(videoURL)
                    }
                )
            }

            if notes.count > 1 {
                ReleaseTimeline(title: "历史动态", notes: Array(notes.dropLast().reversed()))
            }
        }
    }
}

struct UpdatesContent: View {
    let state: VersionContentState
    let currentVersion: AppVersion
    let latestVersion: AppVersion
    let latestRelease: VersionReleaseNote
    let updateNotes: [VersionReleaseNote]
    let downloadURL: URL?
    let onCheck: () -> Void
    let onOpenDownload: (URL) -> OpenURLAction.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if latestVersion > currentVersion {
                VersionUpdateHero(
                    currentVersion: currentVersion,
                    latestVersion: latestVersion,
                    note: latestRelease,
                    downloadURL: downloadURL,
                    onCheck: onCheck,
                    onOpenDownload: onOpenDownload
                )

                if updateNotes.count > 1 {
                    ReleaseTimeline(
                        title: "历史更新",
                        notes: Array(updateNotes.dropLast().reversed())
                    )
                }
            } else {
                PageHeading(
                    eyebrow: "VERSION UPDATE",
                    title: "检查更新",
                    subtitle: "查看当前版本是否需要更新。"
                )
                UpdateCheckResult(
                    state: state,
                    currentVersion: currentVersion,
                    onCheck: onCheck
                )
            }
        }
    }
}

private struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.tint)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.68))
        }
    }
}
