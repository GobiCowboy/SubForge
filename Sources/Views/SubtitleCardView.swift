import SwiftUI
import AppKit

/// 支持 Enter 提交 / Escape 取消 / 全选的 NSTextField 包装器
/// 关键：这个视图始终存在于视图树中，只是通过 opacity 切换可见性
struct SelectableTextField: NSViewRepresentable {
    @Binding var text: String
    var isEditing: Bool
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 14.5)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.delegate = context.coordinator
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.isHidden = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if isEditing {
            nsView.isHidden = false
            if context.coordinator.needsSelectAll {
                context.coordinator.needsSelectAll = false
                DispatchQueue.main.async {
                    nsView.window?.makeFirstResponder(nsView)
                    nsView.selectText(nil)
                }
            }
        } else {
            nsView.isHidden = true
            context.coordinator.needsSelectAll = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectableTextField
        var needsSelectAll = true

        init(_ parent: SelectableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let _ = obj.object as? NSTextField else { return }
            guard let editor = obj.userInfo?["NSFieldEditor"] as? NSTextView else { return }
            let movement = obj.userInfo?["NSTextMovement"] as? Int

            parent.text = editor.string

            if movement == NSReturnTextMovement {
                parent.onCommit()
            }
        }

        // 拦截 Escape 键
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

/// 单条字幕卡片
struct SubtitleCardView: View {
    let segment: SubtitleSegment
    let index: Int
    let isActive: Bool
    let onTap: () -> Void
    @EnvironmentObject var appState: AppState

    @State private var editText = ""
    @State private var editStartTime = ""
    @State private var editEndTime = ""
    @State private var editingField: EditableField? = nil

    private var isEditing: Bool {
        appState.editingIndex == index
    }

    enum EditableField {
        case start, end
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 序号
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 28, alignment: .center)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                // 时间码行
                HStack(spacing: 6) {
                    timeField(time: segment.start, field: .start)
                    Text("→")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    timeField(time: segment.end, field: .end)
                }

                // 文本层：编辑器始终存在，用 opacity 切换
                ZStack(alignment: .topLeading) {
                    // 编辑器（始终在视图树中）
                    SelectableTextField(
                        text: $editText,
                        isEditing: isEditing,
                        onCommit: { commitEdit() },
                        onCancel: { cancelEdit() }
                    )
                    .frame(minHeight: 24)
                    .padding(4)
                    .opacity(isEditing ? 1 : 0)

                    // 显示文本
                    Text(segment.text)
                        .font(.system(size: isActive ? 17 : 14.5, weight: isActive ? .medium : .regular))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(2)
                        .opacity(isEditing ? 0 : 1)
                        .onTapGesture(count: 2) {
                            startEdit()
                        }
                }
                .background(
                    isEditing ?
                    Color(nsColor: .textBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.blue, lineWidth: 2))
                    : nil
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.blue.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue)
                    .frame(width: 3)
                    .padding(.leading, -1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enterEditMode)) { notification in
            if let targetIndex = notification.userInfo?["index"] as? Int, targetIndex == index {
                startEdit()
            }
        }
    }

    // MARK: - 时间码字段

    @ViewBuilder
    private func timeField(time: TimeInterval, field: EditableField) -> some View {
        if editingField == field {
            TextField("", text: field == .start ? $editStartTime : $editEndTime)
                .font(.system(size: 11.5, design: .monospaced))
                .textFieldStyle(.plain)
                .frame(width: 100)
                .padding(1)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.blue, lineWidth: 1.5))
                .onSubmit {
                    commitTimeEdit(field: field)
                }
                .onExitCommand {
                    editingField = nil
                }
        } else {
            Text(formatTime(time))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture {
                    editingField = field
                    if field == .start {
                        editStartTime = formatTime(time)
                    } else {
                        editEndTime = formatTime(time)
                    }
                }
        }
    }

    // MARK: - 编辑逻辑

    private func startEdit() {
        editText = segment.text
        appState.editingIndex = index
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != segment.text {
            appState.segments[index].text = trimmed
        }
        appState.editingIndex = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func cancelEdit() {
        editText = segment.text
        appState.editingIndex = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func commitTimeEdit(field: EditableField) {
        let value = field == .start ? editStartTime : editEndTime
        if let newTime = parseTime(value) {
            if field == .start {
                appState.segments[index].start = newTime
            } else {
                appState.segments[index].end = newTime
            }
        }
        editingField = nil
    }
}
