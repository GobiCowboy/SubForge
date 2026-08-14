import AppKit
import SwiftUI

enum HelpSectionVisualStyle: String {
    case standard
    case feature
    case steps
    case note
    case faq

    init(rawValue: String?) {
        self = HelpSectionVisualStyle(rawValue: rawValue ?? "") ?? .standard
    }

    var iconColor: Color {
        switch self {
        case .note: .orange
        case .faq: .secondary
        case .standard, .feature, .steps: .accentColor
        }
    }

    var background: Color {
        switch self {
        case .feature: Color.accentColor.opacity(0.075)
        case .steps: Color.accentColor.opacity(0.045)
        case .note: Color.orange.opacity(0.07)
        case .standard, .faq: .clear
        }
    }
}

struct HelpRichBlocks: View {
    let blocks: [VersionHelpBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case let .block(block):
                    HelpRichBlock(block: block)
                case let .stepWithScreenshot(step, screenshot):
                    HelpStepWithScreenshot(step: step, screenshot: screenshot)
                }
            }
        }
    }

    private var rows: [HelpRichRow] {
        var rows: [HelpRichRow] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            if block.type.lowercased() == "steps",
               block.items?.count == 1,
               index + 1 < blocks.count,
               blocks[index + 1].type.lowercased() == "image" {
                rows.append(.stepWithScreenshot(step: block, screenshot: blocks[index + 1]))
                index += 2
            } else {
                rows.append(.block(block))
                index += 1
            }
        }

        return rows
    }
}

private enum HelpRichRow {
    case block(VersionHelpBlock)
    case stepWithScreenshot(step: VersionHelpBlock, screenshot: VersionHelpBlock)
}

private struct HelpRichBlock: View {
    let block: VersionHelpBlock

    var body: some View {
        switch block.type.lowercased() {
        case "text":
            if let text = block.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "steps":
            HelpStepList(items: block.items ?? [], start: block.start ?? 1)
        case "callout":
            HelpCallout(block: block)
        case "image":
            HelpImageBlock(block: block)
        default:
            EmptyView()
        }
    }
}

private struct HelpStepList: View {
    let items: [String]
    let start: Int

    var body: some View {
        let isSingleStep = items.count == 1

        VStack(alignment: .leading, spacing: isSingleStep ? 0 : 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HelpStepRow(
                    number: index + start,
                    text: item,
                    emphasized: isSingleStep
                )
            }
        }
    }
}

private struct HelpStepWithScreenshot: View {
    let step: VersionHelpBlock
    let screenshot: VersionHelpBlock
    @State private var image: NSImage?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                HelpStepList(items: step.items ?? [], start: step.start ?? 1)

                Button {
                    isExpanded.toggle()
                } label: {
                    VStack(spacing: 4) {
                        Text("截图")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.tint)
                    .frame(width: 46, height: 45)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起第 \(step.start ?? 1) 步截图" : "展开第 \(step.start ?? 1) 步截图")
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(screenshot.alt ?? "操作截图")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Group {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            HelpImagePlaceholder()
                        }
                    }
                    .frame(maxWidth: 520, maxHeight: 340)
                    .padding(8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if let caption = screenshot.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.leading, 42)
            }
        }
        .task(id: "\(screenshot.url ?? "")-\(isExpanded)") {
            guard isExpanded,
                  let url = screenshot.url,
                  let sha256 = screenshot.sha256,
                  let data = await VersionContentImageStore.shared.load(urlString: url, sha256: sha256),
                  let loadedImage = NSImage(data: data) else {
                return
            }
            image = loadedImage
        }
    }
}

private struct HelpImagePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("图片暂时无法加载")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color.primary.opacity(0.045))
    }
}

private struct HelpStepRow: View {
    let number: Int
    let text: String
    let emphasized: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(emphasized ? 0.16 : 0.13), in: Circle())

            VStack(alignment: .leading, spacing: emphasized ? 4 : 0) {
                if emphasized {
                    Text("第 \(number) 步")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tint)
                }

                Text(text)
                    .font(.system(size: emphasized ? 14 : 13, weight: emphasized ? .semibold : .medium))
                    .foregroundStyle(.primary.opacity(0.86))
                    .lineSpacing(emphasized ? 2 : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, emphasized ? 13 : 0)
        .padding(.vertical, emphasized ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            emphasized ? Color.accentColor.opacity(0.055) : .clear,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            if emphasized {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
            }
        }
    }
}

private struct HelpCallout: View {
    let block: VersionHelpBlock

    private var tone: String {
        block.tone?.lowercased() ?? "info"
    }

    private var tint: Color {
        switch tone {
        case "warning": .orange
        case "success": .green
        default: .accentColor
        }
    }

    private var symbolName: String {
        switch tone {
        case "warning": "exclamationmark.triangle.fill"
        case "success": "checkmark.circle.fill"
        default: "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                if let title = block.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                if let text = block.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct HelpImageBlock: View {
    let block: VersionHelpBlock
    @State private var image: NSImage?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 2) {
                    Text(isExpanded ? "操作截图" : "展开截图")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                        Text(isExpanded ? "点击收起" : "点击查看操作参考")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("辅助参考")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.055), in: Capsule())

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(isExpanded ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025))
            .accessibilityLabel(isExpanded ? "收起操作截图" : "展开操作截图")
            .accessibilityHint(isExpanded ? "隐藏这张操作参考图" : "显示这张操作参考图")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")

            if isExpanded {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        imagePlaceholder
                    }
                }
                .frame(maxWidth: 520, maxHeight: 340)
                .padding(9)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let caption = block.caption, !caption.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 1)

                        Text(caption)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 13)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .frame(maxWidth: 520, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: 700, alignment: .leading)
        .padding(.leading, 38)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel(block.alt ?? "帮助插图")
        .task(id: "\(block.url ?? "")-\(isExpanded)") {
            guard isExpanded else { return }
            guard let url = block.url,
                  let sha256 = block.sha256,
                  let data = await VersionContentImageStore.shared.load(urlString: url, sha256: sha256),
                  let loadedImage = NSImage(data: data) else {
                return
            }
            image = loadedImage
        }
    }

    private var imagePlaceholder: some View {
        HelpImagePlaceholder()
    }
}
