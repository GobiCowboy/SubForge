import SwiftUI

struct ReleaseHighlight: View {
    let note: VersionReleaseNote
    let eyebrow: String
    let actionTitle: String?
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.tint)
                    Text(note.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }

                Spacer(minLength: 12)
                if !note.publishedAt.isEmpty {
                    Text(note.publishedAt)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(note.highlights, id: \.self) { highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tint)
                        Text(highlight)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

struct VersionUpdateHero: View {
    let currentVersion: AppVersion
    let latestVersion: AppVersion
    let note: VersionReleaseNote
    let downloadURL: URL?
    let onCheck: () -> Void
    let onOpenDownload: (URL) -> OpenURLAction.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("发现新版本")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(verbatim: "v\(currentVersion)  →  v\(latestVersion)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tint)
                }

                Spacer(minLength: 10)

                Text("可更新")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("本次更新")
                        .font(.system(size: 13, weight: .semibold))
                    Text(note.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                ForEach(note.highlights, id: \.self) { highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tint)
                        Text(highlight)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                if let downloadURL {
                    Button("去更新") {
                        _ = onOpenDownload(downloadURL)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("重新检查", action: onCheck)
                    .buttonStyle(.bordered)

                Spacer()

                if !note.publishedAt.isEmpty {
                    Text(note.publishedAt)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ReleaseTimeline: View {
    let title: String
    let notes: [VersionReleaseNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(index == 0 ? Color.accentColor : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)

                            if index < notes.count - 1 {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.18))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                                    .padding(.top, 5)
                            }
                        }
                        .frame(width: 12)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("v\(note.version)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.tint)
                                Text(note.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer(minLength: 8)
                                if !note.publishedAt.isEmpty {
                                    Text(note.publishedAt)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Text(note.highlights.joined(separator: "；"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UpdateCheckResult: View {
    let state: VersionContentState
    let currentVersion: AppVersion
    let onCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("重新检查", action: onCheck)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }

    private var title: String {
        switch state {
        case .current: "已经是最新版本"
        case .checking: "正在检查版本"
        case .failed: "暂时无法检查"
        default: "版本状态"
        }
    }

    private var message: String {
        switch state {
        case .current: "你正在使用 v\(currentVersion)，暂时不需要更新。"
        case .checking: "正在从线上内容服务读取最新版本信息。"
        case .failed(let message): message
        default: "版本信息将在下一次检查后显示。"
        }
    }

    private var icon: String {
        switch state {
        case .current: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        default: "questionmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .current: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
