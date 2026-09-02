import AppKit
import SwiftUI

struct SubtitleTextEditor: NSViewRepresentable {
  @Binding var text: String

  let isEditable: Bool
  let isFocused: Bool
  let onFocusChange: (Bool) -> Void
  let onSelectionChange: (NSRange) -> Void
  let onRequestSplit: () -> Void
  var initialCaretOffset: Int? = nil
  var fontSize: CGFloat = 13

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder

    let textView = SubtitleNSTextView()
    textView.splitAction = onRequestSplit
    textView.shouldRequestFocus = isFocused
    textView.delegate = context.coordinator
    textView.string = text
    textView.isEditable = isEditable
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font = .systemFont(ofSize: fontSize)
    textView.textColor = .labelColor
    textView.insertionPointColor = .controlAccentColor
    textView.textContainerInset = NSSize(width: 6, height: 7)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.lineFragmentPadding = 0
    textView.initialCaretOffsetForFocus = initialCaretOffset
    textView.pendingInitialCaretOffset = initialCaretOffset

    scrollView.documentView = textView
    textView.requestFocusIfNeeded()
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? SubtitleNSTextView else { return }
    context.coordinator.parent = self
    textView.splitAction = onRequestSplit
    textView.shouldRequestFocus = isFocused

    if textView.string != text {
      let selectedRange = textView.selectedRange()
      textView.string = text
      textView.setSelectedRange(
        NSRange(
          location: min(selectedRange.location, text.utf16.count),
          length: 0
        )
      )
    }
    textView.isEditable = isEditable
    textView.font = .systemFont(ofSize: fontSize)

    let isFirstResponder = textView.window?.firstResponder === textView
    if !isFirstResponder, !textView.hasAppliedInitialCaret,
      textView.pendingInitialCaretOffset == nil
    {
      textView.pendingInitialCaretOffset = textView.initialCaretOffsetForFocus ?? initialCaretOffset
    }

    textView.requestFocusIfNeeded()
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: SubtitleTextEditor

    init(_ parent: SubtitleTextEditor) {
      self.parent = parent
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onFocusChange(true)
      sendSelection()
    }

    func textDidEndEditing(_ notification: Notification) {
      parent.onFocusChange(false)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      sendSelection(textView)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      sendSelection(notification.object as? NSTextView)
    }

    private func sendSelection(_ textView: NSTextView? = nil) {
      let view = textView ?? (NSApp.keyWindow?.firstResponder as? NSTextView)
      guard let view else { return }
      parent.onSelectionChange(view.selectedRange())
    }
  }
}

private final class SubtitleNSTextView: NSTextView {
  var splitAction: (() -> Void)?
  var shouldRequestFocus = false
  var initialCaretOffsetForFocus: Int?
  var pendingInitialCaretOffset: Int?
  private(set) var hasAppliedInitialCaret = false

  override func layout() {
    super.layout()
    centerTextVertically()
  }

  private func centerTextVertically() {
    guard let textContainer, let layoutManager else { return }

    let contentHeight = layoutManager.usedRect(for: textContainer).height
    let centeredInset = max(7, (bounds.height - contentHeight) / 2)
    guard abs(textContainerInset.height - centeredInset) > 0.5 else { return }

    textContainerInset = NSSize(width: textContainerInset.width, height: centeredInset)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    requestFocusIfNeeded()
  }

  func requestFocusIfNeeded() {
    guard shouldRequestFocus else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.shouldRequestFocus, let window = self.window else { return }

      if window.firstResponder !== self {
        guard window.makeFirstResponder(self) else { return }
      }

      self.applyPendingInitialCaret()

      guard let initialCaretOffset = self.initialCaretOffsetForFocus else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self,
          self.shouldRequestFocus,
          self.window?.firstResponder === self
        else { return }
        self.applyInitialCaret(initialCaretOffset)
      }
    }
  }

  private func applyPendingInitialCaret() {
    guard let pendingInitialCaretOffset else { return }

    applyInitialCaret(pendingInitialCaretOffset)
    self.pendingInitialCaretOffset = nil
  }

  private func applyInitialCaret(_ offset: Int) {
    let location = min(max(offset, 0), string.utf16.count)
    setSelectedRange(NSRange(location: location, length: 0))
    scrollRangeToVisible(selectedRange())
    setNeedsDisplay(bounds)
    hasAppliedInitialCaret = true
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event) ?? NSMenu()
    if !menu.items.contains(where: { $0.title == "分割当前字幕" }) {
      menu.addItem(.separator())
      let item = NSMenuItem(
        title: "分割当前字幕",
        action: #selector(splitCurrentSubtitle),
        keyEquivalent: ""
      )
      item.target = self
      menu.addItem(item)
    }
    return menu
  }

  @objc private func splitCurrentSubtitle() {
    splitAction?()
  }
}
