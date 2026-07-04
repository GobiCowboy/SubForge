import AppKit
import SwiftUI

struct ProjectSidebar: View {
    @EnvironmentObject private var model: AppModel

    let onImport: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    primaryAction
                    navigationSection
                    recentSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }

            Divider()

            settingsRow
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .frame(width: 280)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)

            Text("SubForge")
                .font(.system(size: 28, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var primaryAction: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .frame(width: 18)
            Text("导入文件")
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .onTapGesture(perform: onImport)
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("工作区")

            navigationRow(
                title: "开始页",
                detail: "导入音频或 srt",
                systemImage: "house",
                isSelected: model.mode == .home
            )
            .onTapGesture {
                model.showHome()
            }

            if model.hasWorkspace {
                navigationRow(
                    title: model.mode == .progress ? "处理中" : "当前字幕",
                    detail: model.currentDocumentName,
                    systemImage: model.mode == .progress ? "waveform.path.ecg" : "captions.bubble",
                    isSelected: model.mode != .home
                )
                .opacity(model.mode == .progress ? 0.5 : 1)
                .onTapGesture {
                    guard model.mode != .progress else { return }
                    model.showEditor()
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("最近文件")

            if model.recentProjects.isEmpty {
                Text("还没有最近文件")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.recentProjects.prefix(6)) { project in
                        recentRow(project)
                            .onTapGesture {
                                model.openRecentProject(project)
                            }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func navigationRow(
        title: String,
        detail: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.07) : Color.clear)
        )
    }

    private func recentRow(_ project: RecentProject) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: project.kind))
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(project.modifiedLabel) · \(project.durationLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.20))
                }
        )
    }

    private var settingsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .frame(width: 18)
            Text("设置")
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenSettings)
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "audio":
            return "waveform"
        default:
            return "doc.text"
        }
    }
}
