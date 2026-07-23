import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func handleEditorKeyDown(_ event: NSEvent) -> Bool {
        guard mode == .editor else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasUnsupportedModifier = modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
        guard !hasUnsupportedModifier else { return false }

        AppLog.editor.info(
            "keyDown keyCode=\(event.keyCode, privacy: .public) chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public) playing=\(self.isPlaying, privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public) focus=\(String(describing: self.editorFocusContext), privacy: .public) repeat=\(event.isARepeat, privacy: .public)"
        )

        if isEditingSubtitle {
            switch event.keyCode {
            case 49:
                if modifiers.contains(.shift) {
                    AppLog.editor.info("shiftSpacePassThrough editing=true")
                    return false
                }
                if activeTextInputHasMarkedText() {
                    AppLog.editor.info("imeSpacePassThrough editing=true")
                    return false
                }
                handleSpacePlaybackShortcut()
                return true
            case 48:
                moveEditingFocus(reverse: modifiers.contains(.shift))
                return true
            case 53:
                endEditingSubtitle()
                return true
            default:
                return false
            }
        }

        guard !event.isARepeat else { return false }

        switch event.keyCode {
        case 38:
            handleBackwardPlaybackShortcut()
            return true
        case 40:
            handlePausePlaybackShortcut()
            return true
        case 37:
            handleForwardPlaybackShortcut()
            return true
        case 49:
            handleSpacePlaybackShortcut()
            return true
        case 126:
            selectPreviousSegment()
            return true
        case 125:
            selectNextSegment()
            return true
        case 123:
            skip(by: -1)
            return true
        case 124:
            skip(by: 1)
            return true
        default:
            return false
        }
    }

    func activeTextInputHasMarkedText() -> Bool {
        if let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient,
           inputClient.hasMarkedText() {
            return true
        }

        if let inputClient = NSApp.keyWindow?.fieldEditor(false, for: nil) as? NSTextInputClient,
           inputClient.hasMarkedText() {
            return true
        }

        return false
    }

    func captureCurrentTimestamp() {
        let formatted = formatClock(currentTime)
        capturedTimestamp = formatted
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formatted, forType: .string)
        showToast("已复制时间戳 \(formatted)", level: .info)
    }

    func syncSelectionToCurrentTime() {
        guard let match = segments.first(where: { currentTime >= $0.start && currentTime < $0.end }) else { return }
        if match.id != selectedSegmentID {
            selectedSegmentID = match.id
        }
    }
}
