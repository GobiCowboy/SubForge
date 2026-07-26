import SwiftUI

struct HotwordPromptSheet: View {
    let request: HotwordPromptRequest
    let onEnable: () -> Void
    let onDisable: () -> Void
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: request.kind == .onboarding ? "text.badge.plus" : "text.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)

            Text(request.kind == .onboarding ? "启用热词？" : "填写热词")
                .font(.system(size: 22, weight: .semibold))

            if request.kind == .onboarding {
                Text("启用后，每次转写前都可以填写视频中经常出现的人名、品牌名、产品名或专业术语，由 AI 校对识别错误。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextEditor(text: $input)
                    .font(.system(size: 14))
                    .frame(height: 150)
                    .padding(8)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    }

                Text("填写视频中经常出现的专有名词，可由 AI 校对。每行一个，只需填写正确写法。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Spacer()
                if request.kind == .onboarding {
                    Button("暂不启用", action: onDisable)
                    Button("启用", action: onEnable)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("取消", action: onCancel)
                    Button("开始生成字幕") {
                        onSubmit(input)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(26)
        .frame(width: 480)
    }
}
