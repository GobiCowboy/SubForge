import AppKit
import SwiftUI

struct SettingsInsetPanel<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SettingsVisualTokens.standardBorder, lineWidth: SettingsVisualTokens.borderWidth)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

struct SettingsPill: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct SettingsTipBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettingsVisualTokens.standardBorder, lineWidth: SettingsVisualTokens.borderWidth)
        )
    }
}

struct SettingsKeyValueRow: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsPathField: View {
    let title: String
    @Binding var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("请选择目录", text: $path)
                Button("选择…") {
                    chooseDirectory(for: $path)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

func chooseDirectory(for path: Binding<String>, bookmarkData: Binding<Data?>? = nil) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"

    if panel.runModal() == .OK, let url = panel.url {
        path.wrappedValue = url.path
        bookmarkData?.wrappedValue = SecurityScopedResourceAccess.bookmarkData(for: url)
    }
}
