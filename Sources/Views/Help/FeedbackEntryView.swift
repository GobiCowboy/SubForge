import SwiftUI

struct FeedbackContentView: View {
    let currentSection: UsageAndUpdatesSection

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FEEDBACK")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.tint)
                Text("意见反馈")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("告诉我们哪里可以变得更好。具体内容由你填写，邮件只会带上必要的产品上下文。")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            FeedbackEntryView(currentSection: currentSection)
        }
    }
}

struct FeedbackEntryView: View {
    let currentSection: UsageAndUpdatesSection
    @Environment(\.openURL) private var openURL
    @State private var selectedType: FeedbackType = .experienceOpinion
    @State private var feedbackText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("告诉我们哪里可以变得更好")
                        .font(.system(size: 15, weight: .semibold))
                    Text("填写具体内容后，会打开邮件客户端并自动带上必要的产品信息。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("反馈类型")
                    .font(.system(size: 12, weight: .semibold))
                Picker("反馈类型", selection: $selectedType) {
                    ForEach(FeedbackType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("具体内容")
                    .font(.system(size: 12, weight: .semibold))
                ZStack(alignment: .topLeading) {
                    if feedbackText.isEmpty {
                        Text("请描述你的建议、遇到的问题或使用感受…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $feedbackText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(3)
                }
                .frame(height: 150)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("当前页面：\(currentSection.rawValue)", systemImage: "location")
                Label("收件地址：\(FeedbackComposer.recipient)", systemImage: "envelope")
                Label("不会自动附加日志、截图或媒体", systemImage: "lock.shield")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("发送反馈邮件") {
                    guard let url = FeedbackComposer.mailURL(
                        type: selectedType,
                        section: currentSection,
                        details: feedbackText
                    ) else { return }
                    openURL(url)
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
    }
}
