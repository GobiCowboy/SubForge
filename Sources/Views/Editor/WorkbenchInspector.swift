import SwiftUI

extension WorkbenchView {
  var inspector: some View {
    VStack(spacing: 0) {
      ScrollView {
        if let segment = model.selectedSegment {
          VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
              InspectorSectionHeader(
                title: "当前字幕",
                trailing: model.selectedIndex.map { "第 \($0 + 1) 条" } ?? "未选择字幕"
              )

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

              InspectorDashedDivider()

              Text("文本预览")
                .font(InspectorStyle.secondaryFont(weight: .medium))
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
                },
                fontSize: 13
              )
              .frame(height: 84)
              .background(
                Color(nsColor: .textBackgroundColor).opacity(0.72),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .strokeBorder(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 1)
              )
              .focused($inspectorFocus, equals: .text)
              .disabled(model.isPlaying)
            }
            .padding(.horizontal, 14)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
              InspectorSectionHeader(title: "编辑操作", trailing: "快捷键")

              VStack(spacing: 4) {
                InspectorActionRow(title: "在前方插入", icon: "arrow.up", shortcut: "⇧ ⌘ ↑") {
                  model.insertSegment(before: true)
                }
                .disabled(model.selectedSegment == nil)

                InspectorActionRow(title: "在后方插入", icon: "arrow.down", shortcut: "⇧ ⌘ ↓") {
                  model.insertSegment(before: false)
                }
                .disabled(model.selectedSegment == nil)

                InspectorActionRow(title: "合并下一条", icon: "arrow.triangle.merge", shortcut: "⇧ ⌘ M")
                {
                  model.mergeWithNext()
                }
                .disabled(model.selectedIndex == model.segments.indices.last)

                InspectorActionRow(title: "分割当前字幕", icon: "scissors", shortcut: "⌘ B") {
                  model.splitSelectedSubtitle()
                }
                .disabled(model.selectedSegment == nil)

                InspectorActionRow(title: "删除字幕", icon: "trash", shortcut: "⌘ ⌫") {
                  model.deleteSelected()
                }
                .disabled(model.selectedSegment == nil)
              }
            }
            .padding(14)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
              InspectorSectionHeader(title: "项目信息")
              metricRow("文件", value: model.currentDocumentName)
              metricRow("字幕条数", value: "\(model.segments.count)")
              metricRow("语言", value: model.summaryLanguage)
            }
            .padding(14)
          }
        } else {
          VStack(alignment: .leading, spacing: 12) {
            InspectorSectionHeader(title: "当前字幕", trailing: "未选择字幕")
            Text("导入文件后，这里会显示当前字幕的精确编辑信息。")
              .font(InspectorStyle.secondaryFont())
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 14)
          .padding(.top, 22)
          .padding(.bottom, 14)
        }
      }

      Divider()

      Button {
        model.presentShortcutGuide()
      } label: {
        Label("键盘快捷键", systemImage: "keyboard")
          .font(InspectorStyle.secondaryFont(weight: .medium))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 9)
          .background(
            Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(16)
      .help("打开完整快捷键说明")
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

  func inspectorField(_ title: String, value: String, onCommit: @escaping (String) -> Void)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(InspectorStyle.secondaryFont(weight: .medium))
        .foregroundStyle(.secondary)
      TextField(
        "",
        text: Binding(
          get: { value },
          set: { onCommit($0) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 11, weight: .regular, design: .monospaced))
      .frame(height: 30)
    }
  }

  func metricRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
    }
    .font(InspectorStyle.secondaryFont())
    .frame(minHeight: 20)
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
