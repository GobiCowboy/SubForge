import AppKit
import SwiftUI

enum SettingsCardTone {
    case regular
    case emphasis
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            content
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let tone: SettingsCardTone
    @ViewBuilder let content: Content

    init(
        tone: SettingsCardTone = .regular,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
    }

    private var cardBackground: Color {
        Color(nsColor: tone == .emphasis ? .textBackgroundColor : .controlBackgroundColor)
    }

    private var cardStroke: Color {
        switch tone {
        case .regular:
            Color(nsColor: .separatorColor).opacity(0.18)
        case .emphasis:
            Color(nsColor: .separatorColor).opacity(0.24)
        }
    }
}

struct SettingsSubsectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
    }
}

struct SettingsPill: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
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
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.system(size: 14))
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
                .font(.system(size: 12, weight: .semibold))
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

func chooseDirectory(for path: Binding<String>) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"

    if panel.runModal() == .OK, let url = panel.url {
        path.wrappedValue = url.path
    }
}
