import SwiftUI

struct PlaybackSubtitleTextView: View {
  let text: String
  let caretOffset: Int

  private var textBeforeCaret: String {
    let safeOffset = min(max(caretOffset, 0), text.utf16.count)
    let index = String.Index(utf16Offset: safeOffset, in: text)
    return String(text[..<index])
  }

  var body: some View {
    ZStack(alignment: .leading) {
      Text(text)
        .font(.system(size: 13))
        .lineLimit(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

      Text(textBeforeCaret)
        .font(.system(size: 13))
        .foregroundStyle(.clear)
        .fixedSize()
        .overlay(alignment: .trailing) {
          Capsule()
            .fill(Color.accentColor)
            .frame(width: 2, height: 20)
        }
    }
    .clipped()
  }
}
