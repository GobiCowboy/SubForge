import AppKit
import SwiftUI

enum SettingsCardTone {
    case regular
    case emphasis
}

enum SettingsVisualTokens {
    static let standardBorder = Color(nsColor: .separatorColor).opacity(0.50)
    static let choiceBorder = Color(nsColor: .separatorColor).opacity(0.50)
    static let selectedBorder = Color.accentColor.opacity(0.90)
    static let borderWidth: CGFloat = 1
}

struct SettingsPageHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))

            if let detail {
                Text(" - \(detail)")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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

struct SettingsValidationSection<Content: View, Action: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let state: SettingsValidationState
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action

    init(
        title: String,
        isExpanded: Binding<Bool>,
        state: SettingsValidationState,
        @ViewBuilder action: () -> Action,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.state = state
        self.action = action()
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 12)
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 0)

                Label(state.statusText, systemImage: state.statusIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state.hasValidated ? (state.passed ? .green : .red) : .secondary)

                action
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SettingsVisualTokens.standardBorder, lineWidth: SettingsVisualTokens.borderWidth)
        )
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
                .strokeBorder(cardStroke, lineWidth: SettingsVisualTokens.borderWidth)
        )
    }

    private var cardBackground: Color {
        Color(nsColor: tone == .emphasis ? .windowBackgroundColor : .controlBackgroundColor)
    }

    private var cardStroke: Color {
        SettingsVisualTokens.standardBorder
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
                .strokeBorder(SettingsVisualTokens.standardBorder, lineWidth: SettingsVisualTokens.borderWidth)
        )
    }
}
