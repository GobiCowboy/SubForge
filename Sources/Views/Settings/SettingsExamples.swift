import SwiftUI

struct SettingsActionRow<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    init(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        HStack(spacing: 14) {
            primary
                .frame(maxWidth: .infinity)

            secondary
                .frame(maxWidth: .infinity)
        }
    }
}

struct AudioWaveformDropZone: View {
    @State private var bars: [CGFloat] = [0.18, 0.36, 0.54, 0.28, 0.72, 0.42, 0.31, 0.63, 0.22, 0.57, 0.34, 0.48, 0.27, 0.69, 0.38, 0.24, 0.61, 0.33, 0.52, 0.26, 0.58, 0.41, 0.3, 0.64]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("音频示例")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 5) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 999)
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 6, height: 96 * value + 14)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .center)

                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.plus")
                        .foregroundStyle(Color.accentColor)
                    Text("在这里放置一段用于测试转写的音频")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28))
            )
        }
    }
}

struct SettingsValidationResultBox: View {
    let title: String
    let hasValidated: Bool
    let isSuccess: Bool
    let originalText: String
    let resultText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(statusTitle, systemImage: statusIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(originalText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Divider()

                Text("当前结果")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(resultText)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.24))
        )
    }

    private var statusTitle: String {
        if !hasValidated { return "尚未验证" }
        return isSuccess ? "验证通过" : "验证失败"
    }

    private var statusIcon: String {
        if !hasValidated { return "clock.badge.questionmark" }
        return isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        if !hasValidated { return .secondary }
        return isSuccess ? .green : .red
    }
}

struct SettingsStatusRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SettingsExampleBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14))
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.24))
                )
        }
    }
}

struct SettingsComparisonBox: View {
    let title: String
    let subtitle: String
    let bodyText: String
    let badge: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let badge {
                    SettingsPill(text: badge, tint: tint)
                }
            }

            Text(bodyText)
                .font(.system(size: 14))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}
