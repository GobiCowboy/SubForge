import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func selectSegment(_ segmentID: UUID) {
        if selectedSegmentID != segmentID {
            subtitleTextCaret = nil
        }
        selectedSegmentID = segmentID
        if let segment = selectedSegment, !isEditingSubtitle {
            seek(to: segment.start)
        }
    }

    func updateSelectedText(_ text: String) {
        guard let selectedIndex else { return }
        segments[selectedIndex].text = text
    }

    func updateSegmentText(_ text: String, for segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }) else { return }
        segments[index].text = text
    }

    func setEditorFocusContext(_ context: EditorFocusContext) {
        AppLog.editor.info(
            "setEditorFocusContext from=\(String(describing: self.editorFocusContext), privacy: .public) to=\(String(describing: context), privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public)"
        )
        editorFocusContext = context
    }

    func beginEditingSelectedSubtitle(surface: EditorSurface = .table) {
        guard mode == .editor, !isPlaying, selectedSegmentID != nil else { return }
        AppLog.editor.info(
            "beginEditingSelectedSubtitle surface=\(String(describing: surface), privacy: .public) selected=\(String(describing: self.selectedSegmentID), privacy: .public) currentFocus=\(String(describing: self.editorFocusContext), privacy: .public)"
        )
        activeEditorSurface = surface
        isEditingSubtitle = true
        if editorFocusContext == .none {
            editorFocusContext = .text
        }
    }

    func endEditingSubtitle() {
        guard isEditingSubtitle else { return }
        AppLog.editor.info(
            "endEditingSubtitle surface=\(String(describing: self.activeEditorSurface), privacy: .public) selected=\(String(describing: self.selectedSegmentID), privacy: .public) currentFocus=\(String(describing: self.editorFocusContext), privacy: .public)"
        )
        isEditingSubtitle = false
        editorFocusContext = .none
    }

    func setActiveEditorSurface(_ surface: EditorSurface) {
        activeEditorSurface = surface
    }

    func setSubtitleTextCaret(segmentID: UUID, range: NSRange) {
        guard range.location != NSNotFound else { return }
        subtitleTextCaret = SubtitleTextCaret(
            segmentID: segmentID,
            utf16Offset: range.location,
            selectionLength: range.length
        )
    }

    func splitSelectedSubtitle() {
        guard !isPlaying else {
            showToast("请先暂停播放，再分割字幕", level: .info)
            return
        }
        guard let selectedIndex, segments.indices.contains(selectedIndex) else {
            showToast("请先选择一条字幕", level: .info)
            return
        }

        let segment = segments[selectedIndex]
        do {
            let result: SubtitleSplitResult
            if let caret = subtitleTextCaret, caret.segmentID == segment.id {
                guard caret.selectionLength == 0 else {
                    showToast("请先收起文本选区，只保留一个分割光标", level: .info)
                    return
                }
                result = try SubtitleSplitService.splitAtCaret(
                    segment,
                    utf16Offset: caret.utf16Offset
                )
            } else {
                result = try SubtitleSplitService.splitAtPlayhead(segment, time: currentTime)
            }

            endEditingSubtitle()
            segments[selectedIndex] = result.left
            segments.insert(result.right, at: selectedIndex + 1)
            selectedSegmentID = result.right.id
            subtitleTextCaret = nil

            let suffix = result.usesEstimatedTime ? "（时间按比例估算）" : ""
            showToast("已分割当前字幕\(suffix)", level: .success)
        } catch let error as SubtitleSplitError {
            showToast(error.localizedDescription, level: .info)
        } catch {
            showToast("当前字幕无法分割", level: .error)
        }
    }

    func selectPreviousSegment() {
        guard let selectedIndex, selectedIndex > 0 else { return }
        selectSegment(segments[selectedIndex - 1].id)
    }

    func selectNextSegment() {
        guard let selectedIndex, selectedIndex < segments.count - 1 else { return }
        selectSegment(segments[selectedIndex + 1].id)
    }

    func moveEditingFocus(reverse: Bool) {
        guard isEditingSubtitle else { return }

        let order: [EditorFocusContext] = [.start, .end, .text]
        let current = order.firstIndex(of: editorFocusContext) ?? 0
        let nextIndex: Int

        if reverse {
            nextIndex = current == 0 ? order.count - 1 : current - 1
        } else {
            nextIndex = current == order.count - 1 ? 0 : current + 1
        }

        let target = order[nextIndex]
        AppLog.editor.info(
            "moveEditingFocus reverse=\(reverse, privacy: .public) from=\(String(describing: self.editorFocusContext), privacy: .public) to=\(String(describing: target), privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public)"
        )

        if activeEditorSurface == .table {
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.async {
                AppLog.editor.info(
                    "applyDeferredFocus target=\(String(describing: target), privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public)"
                )
                self.editorFocusContext = target
            }
        } else {
            editorFocusContext = target
        }
    }

    func updateSelectedStart(from text: String) {
        guard let selectedIndex, let value = parseTimestamp(text) else { return }
        segments[selectedIndex].start = max(0, min(value, segments[selectedIndex].end - 0.1))
    }

    func updateSegmentStart(from text: String, for segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }),
              let value = parseTimestamp(text) else { return }
        segments[index].start = max(0, min(value, segments[index].end - 0.1))
    }

    func updateSelectedEnd(from text: String) {
        guard let selectedIndex, let value = parseTimestamp(text) else { return }
        segments[selectedIndex].end = max(segments[selectedIndex].start + 0.1, value)
        playbackDuration = max(playbackDuration, segments[selectedIndex].end + 0.5)
    }

    func updateSegmentEnd(from text: String, for segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }),
              let value = parseTimestamp(text) else { return }
        segments[index].end = max(segments[index].start + 0.1, value)
        playbackDuration = max(playbackDuration, segments[index].end + 0.5, playbackService.mediaDuration)
    }

    func insertSegment(before: Bool) {
        guard let selectedIndex else { return }
        endEditingSubtitle()
        let newSegment = blankSegment(around: selectedIndex, before: before)
        let insertIndex = before ? selectedIndex : selectedIndex + 1
        segments.insert(newSegment, at: insertIndex)
        selectedSegmentID = newSegment.id
    }

    func mergeWithNext() {
        guard let selectedIndex, selectedIndex < segments.count - 1 else { return }
        endEditingSubtitle()
        let current = segments[selectedIndex]
        let next = segments[selectedIndex + 1]
        segments[selectedIndex].end = max(current.end, next.end)
        segments[selectedIndex].text = [current.text, next.text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        segments.remove(at: selectedIndex + 1)
    }

    func deleteSelected() {
        guard let selectedIndex else { return }
        endEditingSubtitle()
        segments.remove(at: selectedIndex)
        selectedSegmentID = segments.indices.contains(selectedIndex) ? segments[selectedIndex].id : segments.last?.id
    }
}
