import SwiftUI

struct ShortcutGuideItem: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
}

private let editorShortcutItems: [ShortcutGuideItem] = [
    .init(keys: "Space", description: "播放 / 暂停。播放时按下会暂停并进入编辑，编辑时按下会退出编辑并继续播放。"),
    .init(keys: "Shift + Space", description: "在编辑状态下输入空格。"),
    .init(keys: "Tab / Shift + Tab", description: "在开始时间、结束时间、字幕文本之间切换焦点。"),
    .init(keys: "Esc", description: "退出当前编辑状态。"),
    .init(keys: "J", description: "后退 1 秒。"),
    .init(keys: "K", description: "暂停并复制当前时间戳。"),
    .init(keys: "L", description: "按当前速度播放，并在 0.5x 到 2.0x 之间循环调速。"),
]

struct ShortcutGuidePanel: View {
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            Text("快捷键")
                .font(.system(size: compact ? 11 : 15, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                ForEach(compact ? Array(editorShortcutItems.prefix(5)) : editorShortcutItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.keys)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: compact ? 112 : 118, alignment: .leading)

                        Text(item.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct ShortcutGuideSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("快捷键")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("完成") {
                    model.isShortcutGuidePresented = false
                }
                .keyboardShortcut(.defaultAction)
            }

            ShortcutGuidePanel(compact: false)

            Spacer()
        }
        .padding(20)
        .frame(width: 560, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
