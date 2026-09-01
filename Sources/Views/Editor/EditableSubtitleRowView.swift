import SwiftUI

struct EditableSubtitleRowView: View {
  @EnvironmentObject private var model: AppModel

  let segment: SubtitleSegment
  let index: Int

  @FocusState private var focusedField: Field?
  @State private var startText = ""
  @State private var endText = ""
  @State private var contentText = ""
  @State private var isContentFocused = false

  private enum Field: Hashable {
    case start
    case end
  }

  private var isSelected: Bool {
    segment.id == model.selectedSegmentID
  }

  private var playbackCaretOffset: Int {
    SubtitleSplitService.caretOffset(at: model.currentTime, in: segment)
  }

  var body: some View {
    HStack(spacing: 0) {
      indexCell
      timeCell(text: $startText, field: .start, width: 126)
      timeCell(text: $endText, field: .end, width: 126)
      contentCell
      actionsCell
    }
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    .contentShape(Rectangle())
    .onTapGesture {
      model.selectSegment(segment.id)
    }
    .onAppear(perform: syncDisplayValues)
    .onChange(of: segment.start) { _, _ in syncDisplayValues() }
    .onChange(of: segment.end) { _, _ in syncDisplayValues() }
    .onChange(of: segment.text) { _, newValue in
      if !isContentFocused {
        contentText = newValue
      }
    }
    .onChange(of: focusedField) { previous, current in
      if isSelected {
        AppLog.editor.info(
          "rowFocusedFieldChanged segment=\(self.segment.id.uuidString, privacy: .public) previous=\(String(describing: previous), privacy: .public) current=\(String(describing: current), privacy: .public)"
        )
      }
      if previous == .start, current != .start {
        commitStart()
      }
      if previous == .end, current != .end {
        commitEnd()
      }
      if let current {
        model.setEditorFocusContext(context(for: current))
      } else if !isContentFocused, model.editorFocusContext != .text {
        model.setEditorFocusContext(.none)
      }
      if current == .start || current == .end {
        selectAllCurrentText()
      }
    }
    .onChange(of: model.isEditingSubtitle) { _, isEditing in
      guard isSelected else { return }
      AppLog.editor.info(
        "rowEditingStateChanged segment=\(self.segment.id.uuidString, privacy: .public) editing=\(isEditing, privacy: .public) surface=\(String(describing: model.activeEditorSurface), privacy: .public) modelFocus=\(String(describing: model.editorFocusContext), privacy: .public)"
      )
      if isEditing, model.activeEditorSurface == .table {
        applyModelFocus(model.editorFocusContext)
      } else {
        focusedField = nil
        isContentFocused = false
      }
    }
    .onChange(of: model.selectedSegmentID) { _, selectedID in
      guard model.isEditingSubtitle, model.activeEditorSurface == .table else { return }
      if selectedID == segment.id || isSelected {
        AppLog.editor.info(
          "rowSelectionChanged segment=\(self.segment.id.uuidString, privacy: .public) selected=\(String(describing: selectedID), privacy: .public) modelFocus=\(String(describing: model.editorFocusContext), privacy: .public)"
        )
      }
      if selectedID == segment.id {
        applyModelFocus(model.editorFocusContext)
      } else {
        focusedField = nil
        isContentFocused = false
      }
    }
    .onChange(of: model.editorFocusContext) { _, context in
      guard model.isEditingSubtitle, model.activeEditorSurface == .table, isSelected else { return }
      AppLog.editor.info(
        "rowApplyModelFocus segment=\(self.segment.id.uuidString, privacy: .public) target=\(String(describing: context), privacy: .public)"
      )
      applyModelFocus(context)
    }
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  private var indexCell: some View {
    Text("\(index + 1)")
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.secondary)
      .frame(width: 54)
      .frame(maxHeight: .infinity)
  }

  private func timeCell(text: Binding<String>, field: Field, width: CGFloat) -> some View {
    TextField("", text: text)
      .textFieldStyle(.plain)
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .frame(width: width, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .center)
      .disabled(model.isPlaying)
      .focused($focusedField, equals: field)
      .onTapGesture {
        model.selectSegment(segment.id)
        if !model.isPlaying {
          AppLog.editor.info(
            "rowTimeFieldTapped segment=\(self.segment.id.uuidString, privacy: .public) field=\(String(describing: field), privacy: .public)"
          )
          model.beginEditingSelectedSubtitle(surface: .table)
          focusedField = field
        }
      }
      .onSubmit {
        switch field {
        case .start:
          commitStart()
        case .end:
          commitEnd()
        }
      }
      .onPasteCommand(of: [.plainText]) { _ in
        guard let pasted = NSPasteboard.general.string(forType: .string),
          let normalized = normalizeTimestampString(from: pasted)
        else {
          return
        }

        text.wrappedValue = normalized
        switch field {
        case .start:
          commitStart()
        case .end:
          commitEnd()
        }
        selectAllCurrentText()
      }
  }

  private var contentCell: some View {
    Group {
      if isSelected,
        model.isEditingSubtitle,
        model.activeEditorSurface == .table,
        model.editorFocusContext == .text
      {
        SubtitleTextEditor(
          text: $contentText,
          isEditable: !model.isPlaying,
          isFocused: true,
          onFocusChange: { focused in
            if focused {
              isContentFocused = true
              model.setEditorFocusContext(.text)
            } else {
              if isContentFocused {
                commitContent()
              }
              isContentFocused = false
              if model.editorFocusContext == .text {
                model.setEditorFocusContext(.none)
              }
            }
          },
          onSelectionChange: { range in
            model.setSubtitleTextCaret(segmentID: segment.id, range: range)
          },
          onRequestSplit: {
            model.selectSegment(segment.id)
            model.splitSelectedSubtitle()
          },
          initialCaretOffset: model.subtitleTextCaret?.segmentID == segment.id
            ? model.subtitleTextCaret?.utf16Offset
            : nil
        )
      } else if isSelected, model.isPlaying {
        PlaybackSubtitleTextView(text: segment.text, caretOffset: playbackCaretOffset)
      } else {
        Text(segment.text)
          .font(.system(size: 13))
          .lineLimit(3)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 90, alignment: .center)
    .disabled(model.isPlaying)
    .onTapGesture {
      model.selectSegment(segment.id)
      if !model.isPlaying {
        AppLog.editor.info(
          "rowContentTapped segment=\(self.segment.id.uuidString, privacy: .public)"
        )
        model.beginEditingSelectedSubtitle(surface: .table)
        model.setEditorFocusContext(.text)
        focusedField = nil
      }
    }
    .onChange(of: contentText) { _, newValue in
      model.updateSegmentText(newValue, for: segment.id)
    }
  }

  private var actionsCell: some View {
    Menu {
      Button("在前面插入") {
        model.selectSegment(segment.id)
        model.insertSegment(before: true)
      }
      Button("在后面插入") {
        model.selectSegment(segment.id)
        model.insertSegment(before: false)
      }
      Button("合并下一条") {
        model.selectSegment(segment.id)
        model.mergeWithNext()
      }
      Button("分割当前字幕") {
        model.selectSegment(segment.id)
        model.splitSelectedSubtitle()
      }
      Divider()
      Button("删除当前字幕", role: .destructive) {
        model.selectSegment(segment.id)
        model.deleteSelected()
      }
    } label: {
      HStack {
        Spacer()
        Image(systemName: "ellipsis")
          .foregroundStyle(.secondary)
        Spacer()
      }
      .frame(width: 42, height: 44)
    }
    .menuStyle(.borderlessButton)
  }

  private func syncDisplayValues() {
    if focusedField != .start {
      startText = formatClock(segment.start)
    }
    if focusedField != .end {
      endText = formatClock(segment.end)
    }
    if !isContentFocused {
      contentText = segment.text
    }
  }

  private func commitStart() {
    model.updateSegmentStart(from: startText, for: segment.id)
    startText = formatClock(
      model.segments.first(where: { $0.id == segment.id })?.start ?? segment.start)
  }

  private func commitEnd() {
    model.updateSegmentEnd(from: endText, for: segment.id)
    endText = formatClock(model.segments.first(where: { $0.id == segment.id })?.end ?? segment.end)
  }

  private func commitContent() {
    model.updateSegmentText(contentText, for: segment.id)
    contentText = model.segments.first(where: { $0.id == segment.id })?.text ?? segment.text
  }

  private func context(for field: Field?) -> EditorFocusContext {
    switch field {
    case .start:
      return .start
    case .end:
      return .end
    case nil:
      return .none
    }
  }

  private func applyModelFocus(_ context: EditorFocusContext) {
    switch context {
    case .start:
      focusedField = .start
    case .end:
      focusedField = .end
    case .text, .none:
      focusedField = nil
    }
  }

  private func selectAllCurrentText() {
    DispatchQueue.main.async {
      NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
    }
  }
}
