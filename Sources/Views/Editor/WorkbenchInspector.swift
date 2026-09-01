import SwiftUI

extension WorkbenchView {
    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前字幕")
                            .font(.system(size: 16, weight: .semibold))
                        Text(model.selectedIndex.map { "第 \($0 + 1) 条" } ?? "未选择字幕")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let segment = model.selectedSegment {
                    VStack(alignment: .leading, spacing: 12) {
                        inspectorField("开始时间", value: formatClock(segment.start)) {
                            model.updateSelectedStart(from: $0)
                        }
                        .focused($inspectorFocus, equals: .start)
                        .disabled(model.isPlaying)

                        inspectorField("结束时间", value: formatClock(segment.end)) {
                            model.updateSelectedEnd(from: $0)
                        }
                        .focused($inspectorFocus, equals: .end)
                        .disabled(model.isPlaying)

                        metricRow("时长", value: formatDuration(segment.end - segment.start))

                        Divider()

                        Text("文本预览")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        SubtitleTextEditor(
                            text: Binding(
                                get: { model.selectedSegment?.text ?? "" },
                                set: { model.updateSelectedText($0) }
                            ),
                            isEditable: !model.isPlaying,
                            isFocused: inspectorFocus == .text,
                            onFocusChange: { focused in
                                if focused {
                                    model.beginEditingSelectedSubtitle(surface: .inspector)
                                }
                                inspectorFocus = focused ? .text : nil
                            },
                            onSelectionChange: { range in
                                if let segmentID = model.selectedSegmentID {
                                    model.setSubtitleTextCaret(segmentID: segmentID, range: range)
                                }
                            },
                            onRequestSplit: {
                                model.splitSelectedSubtitle()
                            }
                        )
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .focused($inspectorFocus, equals: .text)
                        .disabled(model.isPlaying)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("编辑操作")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("分割：文本光标优先，播放头兜底")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("快捷键")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        VStack(spacing: 6) {
                            EditorActionRow(title: "在前方插入", icon: "arrow.up", shortcut: "⇧⌘↑") {
                                model.insertSegment(before: true)
                            }
                            .disabled(model.selectedSegment == nil)

                            EditorActionRow(title: "在后方插入", icon: "arrow.down", shortcut: "⇧⌘↓") {
                                model.insertSegment(before: false)
                            }
                            .disabled(model.selectedSegment == nil)

                            EditorActionRow(title: "合并下一条", icon: "arrow.triangle.merge", shortcut: "⇧⌘M") {
                                model.mergeWithNext()
                            }
                            .disabled(model.selectedIndex == model.segments.indices.last)

                            EditorActionRow(title: "分割当前字幕", icon: "scissors", shortcut: "⌘B", tint: .accentColor) {
                                model.splitSelectedSubtitle()
                            }
                            .disabled(model.selectedSegment == nil)

                            EditorActionRow(title: "删除字幕", icon: "trash", shortcut: "⌘⌫", tint: .red, isDestructive: true) {
                                model.deleteSelected()
                            }
                            .disabled(model.selectedSegment == nil)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("项目信息")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        metricRow("文件", value: model.currentDocumentName)
                        metricRow("字幕条数", value: "\(model.segments.count)")
                        metricRow("语言", value: model.summaryLanguage)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        ShortcutGuidePanel(compact: true)

                        Button("打开完整快捷键说明") {
                            model.presentShortcutGuide()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.link)
                    }
                } else {
                    Text("导入文件后，这里会显示当前字幕的精确编辑信息。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .onChange(of: inspectorFocus) { _, focus in
            AppLog.editor.info(
                "inspectorFocusChanged previousSelected=\(String(describing: model.selectedSegmentID), privacy: .public) focus=\(String(describing: focus), privacy: .public) editing=\(model.isEditingSubtitle, privacy: .public)"
            )
            switch focus {
            case .start:
                model.beginEditingSelectedSubtitle(surface: .inspector)
                model.setEditorFocusContext(.start)
            case .end:
                model.beginEditingSelectedSubtitle(surface: .inspector)
                model.setEditorFocusContext(.end)
            case .text:
                model.beginEditingSelectedSubtitle(surface: .inspector)
                model.setEditorFocusContext(.text)
            case nil:
                if model.isEditingSubtitle, model.activeEditorSurface == .inspector {
                    model.endEditingSubtitle()
                } else {
                    model.setEditorFocusContext(.none)
                }
            }
        }
        .onChange(of: model.isEditingSubtitle) { _, isEditing in
            AppLog.editor.info(
                "inspectorObservedEditing editing=\(isEditing, privacy: .public) surface=\(String(describing: model.activeEditorSurface), privacy: .public) modelFocus=\(String(describing: model.editorFocusContext), privacy: .public)"
            )
            if !isEditing || model.activeEditorSurface != .inspector {
                inspectorFocus = nil
            }
        }
        .onChange(of: model.editorFocusContext) { _, context in
            guard model.isEditingSubtitle, model.activeEditorSurface == .inspector else { return }
            AppLog.editor.info(
                "inspectorApplyModelFocus target=\(String(describing: context), privacy: .public)"
            )
            inspectorFocus = inspectorField(for: context)
        }
    }

    var ratePill: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button("\(rate, specifier: "%.2g")x") {
                    model.setPlaybackRate(rate)
                }
            }
        } label: {
            pillLabel("速度 \(String(format: "%.2g", model.playbackRate))x")
        }
        .menuStyle(.borderlessButton)
    }

    var volumePill: some View {
        pillLabel("预览")
    }

    func button(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
        }
        .buttonStyle(.borderless)
        .frame(width: 20)
    }

    func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    func headerCell(_ text: String, width: CGFloat? = nil) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    func inspectorField(_ title: String, value: String, onCommit: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: Binding(
                get: { value },
                set: { onCommit($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
        }
    }

    func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12))
    }

    func inspectorField(for context: EditorFocusContext) -> InspectorFocus? {
        switch context {
        case .start:
            return .start
        case .end:
            return .end
        case .text:
            return .text
        case .none:
            return nil
        }
    }
}

private struct EditorActionRow: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let icon: String
    let shortcut: String
    var tint: Color = .secondary
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isEnabled ? tint : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        (isEnabled ? tint : Color.secondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? (isDestructive ? .red : .primary) : .secondary)

                Spacer(minLength: 8)

                KeyboardShortcutBadge(text: shortcut, compact: true)
                    .opacity(isEnabled ? 1 : 0.55)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(
                Color.primary.opacity(isEnabled ? 0.045 : 0.018),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help("\(title)（\(shortcut)）")
    }
}
