import SwiftUI

struct ShortcutGuideItem: Identifiable {
    let id = UUID()
    let keys: [String]
    var compactKeys: [String]? = nil
    let description: String

    func displayKeys(compact: Bool) -> [String] {
        compact ? (compactKeys ?? keys) : keys
    }
}

private let editorShortcutItems: [ShortcutGuideItem] = [
    .init(keys: ["Space"], description: "播放 / 暂停。播放时按下会暂停并进入编辑，编辑时按下会退出编辑并继续播放。"),
    .init(keys: ["⇧ Space"], description: "编辑状态下输入空格。中文输入法组词时，Space 会保留给输入法选词。"),
    .init(keys: ["Tab", "⇧ Tab"], description: "在开始时间、结束时间、字幕文本之间切换焦点。"),
    .init(keys: ["Esc"], description: "退出当前编辑状态。"),
    .init(keys: ["⌘B"], description: "分割当前字幕。文本光标优先；没有有效光标时使用当前播放头。"),
    .init(keys: ["⇧⌘↑", "⇧⌘↓"], description: "在当前字幕前方 / 后方插入空字幕。"),
    .init(keys: ["⇧⌘M"], description: "合并当前字幕与下一条。"),
    .init(keys: ["⌘⌫"], description: "删除当前字幕。"),
    .init(keys: ["J"], description: "后退 1 秒。"),
    .init(keys: ["K"], description: "暂停并复制当前时间戳。"),
    .init(keys: ["L"], description: "按当前速度播放，并在 0.5x 到 2.0x 之间循环调速。"),
    .init(keys: ["⌘E"], description: "按当前导出设置导出字幕。"),
]

private let compactShortcutItems: [ShortcutGuideItem] = {
    let primaryItems = Array(editorShortcutItems.prefix(6))
    guard let exportItem = editorShortcutItems.last else { return primaryItems }
    return primaryItems + [exportItem]
}()

struct ShortcutGuidePanel: View {
    let compact: Bool
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            if showsTitle {
                Text("快捷键")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: compact ? 11 : 14) {
                ForEach(compact ? compactShortcutItems : editorShortcutItems) { item in
                    ShortcutGuideRow(item: item, compact: compact)
                }
            }
        }
    }
}

private struct ShortcutGuideRow: View {
    let item: ShortcutGuideItem
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 12 : 18) {
            ShortcutKeyGroup(keys: item.displayKeys(compact: compact))
                .frame(width: compact ? 120 : 184, alignment: .leading)

            Text(item.description)
                .font(.system(size: compact ? 12 : 13))
                .foregroundStyle(.secondary)
                .lineSpacing(compact ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ShortcutKeyGroup: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text("/")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                ShortcutKeycap(text: key)
            }
        }
    }
}

private typealias ShortcutKeycap = KeyboardShortcutBadge

struct ShortcutGuideSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷键")
                        .font(.system(size: 22, weight: .semibold))
                    Text("字幕编辑工作台")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成") {
                    model.isShortcutGuidePresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                ShortcutGuidePanel(compact: false, showsTitle: false)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 660, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
