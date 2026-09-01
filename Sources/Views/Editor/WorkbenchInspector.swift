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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("编辑操作")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Button("在前方插入") { model.insertSegment(before: true) }
                            .buttonStyle(.bordered)

                        Button("在后方插入") { model.insertSegment(before: false) }
                            .buttonStyle(.bordered)

                        Button("合并下一条") { model.mergeWithNext() }
                            .buttonStyle(.bordered)
                            .disabled(model.selectedIndex == model.segments.indices.last)

                        Button("分割当前字幕") { model.splitSelectedSubtitle() }
                            .buttonStyle(.bordered)

                        Button("删除字幕", role: .destructive) { model.deleteSelected() }
                            .buttonStyle(.bordered)
                    }

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
