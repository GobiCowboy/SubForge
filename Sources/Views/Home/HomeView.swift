import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false
    @State private var animateWatchStatus = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    dropZone
                    recentProjectsCard
                }
                .frame(maxWidth: 920)
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }

            footerBar
        }
        .background(Color.white)
        .onAppear {
            animateWatchStatus = true
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("导入音频或视频")
                        .font(.system(size: 30, weight: .semibold))
                    Text("把文件拖到这里，或者直接选择本地素材开始生成字幕。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 68, height: 68)
                    .overlay {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
            }

            VStack(spacing: 18) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 6) {
                    Text("拖入媒体文件即可开始")
                        .font(.system(size: 22, weight: .semibold))
                    Text("支持 .mp4、.mov、.mkv、.mp3、.wav、.srt")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Button("选择文件") {
                    model.openImportPanel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 30)
        .background(panelBackground(cornerRadius: 24, fillOpacity: 0.05))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25))
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleProviders(providers)
        }
    }

    private var recentProjectsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近文件")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("\(model.recentProjects.count) 项")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            if model.recentProjects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("还没有最近文件")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        headerCell("文件名", alignment: .leading)
                        headerCell("时长", width: 120, alignment: .leading)
                        headerCell("字幕数", width: 110, alignment: .leading)
                        headerCell("最近修改", width: 100, alignment: .trailing)
                    }

                    ForEach(model.recentProjects) { project in
                        Button {
                            model.openRecentProject(project)
                        } label: {
                            HStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: iconName(for: project.kind))
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(project.path)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                tableCell(project.durationLabel, width: 120)
                                tableCell("\(project.subtitleCount)", width: 110)
                                tableCell(project.modifiedLabel, width: 100, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
            }
        }
        .background(panelBackground(cornerRadius: 20, fillOpacity: 0.05))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08))
        }
    }

    private var footerBar: some View {
        HStack(spacing: 18) {
            Spacer()

            badge(text: model.settings.transcriptionEngine.rawValue, systemImage: "waveform")
            badge(
                text: model.settings.proofreadingEnabled ? model.settings.proofreadingEngine.rawValue : "AI 校对关闭",
                systemImage: model.settings.proofreadingEnabled ? "checkmark.circle.fill" : "xmark.circle"
            )
            badge(text: model.summaryLanguage, systemImage: "globe")
            listenBadge
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func badge(text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .foregroundStyle(.secondary)
    }

    private var listenBadge: some View {
        HStack(spacing: 6) {
            Text("监听")
                .foregroundStyle(.secondary)
            WatchStatusDot(
                color: watchState.color,
                isAnimated: watchState.isAnimated && animateWatchStatus
            )
        }
    }

    private func panelBackground(cornerRadius: CGFloat, fillOpacity: Double = 0) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(fillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08))
            }
    }

    private func headerCell(_ title: String, width: CGFloat? = nil, alignment: Alignment) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, width == nil ? 16 : 12)
            .padding(.vertical, 10)
    }

    private func tableCell(_ title: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 12)
    }

    private func handleProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                return
            }

            Task { @MainActor in
                model.importDocument(at: url)
            }
        }
        return true
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "video":
            return "film"
        case "audio":
            return "waveform"
        default:
            return "doc.text"
        }
    }

    private var watchState: (color: Color, isAnimated: Bool) {
        let watch = model.settings.watchSettings

        guard !watch.directoryPath.isEmpty else {
            return (.gray, false)
        }

        if watch.autoStart {
            return (.green, true)
        }

        return (.blue, true)
    }
}

private struct WatchStatusDot: View {
    let color: Color
    let isAnimated: Bool

    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isAnimated ? 0.18 : 0.12))
                .frame(width: 16, height: 16)
                .scaleEffect(isAnimated && glow ? 1.35 : 1.0)
                .opacity(isAnimated && glow ? 0.35 : 0.8)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}
