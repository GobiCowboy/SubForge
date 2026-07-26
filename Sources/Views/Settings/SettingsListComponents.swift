import AppKit
import SwiftUI

enum SettingsListMetrics {
    static let titleWidth: CGFloat = 160
    static let controlWidth: CGFloat = 300
    static let pickerWidth: CGFloat = 176
    static let rowHorizontalPadding: CGFloat = 20
}

struct SettingsListRow<Control: View>: View {
    let title: String
    var titleDetail: String? = nil
    var description: String? = nil
    var alignment: VerticalAlignment = .center
    var titleWidth: CGFloat = SettingsListMetrics.titleWidth
    var controlWidth: CGFloat? = SettingsListMetrics.controlWidth
    @ViewBuilder let control: Control

    init(
        title: String,
        titleDetail: String? = nil,
        description: String? = nil,
        alignment: VerticalAlignment = .center,
        titleWidth: CGFloat = SettingsListMetrics.titleWidth,
        controlWidth: CGFloat? = SettingsListMetrics.controlWidth,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.titleDetail = titleDetail
        self.description = description
        self.alignment = alignment
        self.titleWidth = titleWidth
        self.controlWidth = controlWidth
        self.control = control()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            VStack(alignment: .leading, spacing: description == nil ? 0 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)

                    if let titleDetail {
                        Text(titleDetail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .help([title, titleDetail].compactMap { $0 }.joined(separator: " "))

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
                .strokeBorder(SettingsVisualTokens.standardBorder, lineWidth: SettingsVisualTokens.borderWidth)
        )
    }
}
