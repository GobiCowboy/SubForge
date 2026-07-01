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
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
    }

    private var cardBackground: Color {
        Color(nsColor: tone == .emphasis ? .windowBackgroundColor : .controlBackgroundColor)
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

struct SettingsListSection<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.16), lineWidth: 1)
        )
    }
}

enum SettingsListMetrics {
    static let titleWidth: CGFloat = 160
    static let controlWidth: CGFloat = 300
    static let pickerWidth: CGFloat = 176
    static let rowHorizontalPadding: CGFloat = 20
}

struct SettingsListRow<Control: View>: View {
    let title: String
    var description: String? = nil
    var alignment: VerticalAlignment = .center
    var titleWidth: CGFloat = SettingsListMetrics.titleWidth
    var controlWidth: CGFloat? = SettingsListMetrics.controlWidth
    @ViewBuilder let control: Control

    init(
        title: String,
        description: String? = nil,
        alignment: VerticalAlignment = .center,
        titleWidth: CGFloat = SettingsListMetrics.titleWidth,
        controlWidth: CGFloat? = SettingsListMetrics.controlWidth,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.alignment = alignment
        self.titleWidth = titleWidth
        self.controlWidth = controlWidth
        self.control = control()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            VStack(alignment: .leading, spacing: description == nil ? 0 : 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .help(title)

                if let description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: titleWidth, alignment: .leading)

            Spacer(minLength: 16)

            if let controlWidth {
                control
                    .frame(width: controlWidth, alignment: .trailing)
            } else {
                control
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, SettingsListMetrics.rowHorizontalPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsTrailingControl<Content: View>: View {
    var width: CGFloat = SettingsListMetrics.pickerWidth
    @ViewBuilder let content: Content

    init(width: CGFloat = SettingsListMetrics.pickerWidth, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: width, alignment: .trailing)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 20)
    }
}

struct SettingsSubsectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct SettingsCompactPicker<Control: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)

            control
                .controlSize(.regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        )
    }
}

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
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.14), lineWidth: 1)
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
