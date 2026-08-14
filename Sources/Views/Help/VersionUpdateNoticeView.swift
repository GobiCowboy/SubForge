import SwiftUI

struct VersionUpdateNoticeView: View {
    let notice: VersionUpdateNotice
    let onLater: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("发现新版本")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tint)
                    Text("SubForge 有新版本")
                        .font(.system(size: 23, weight: .bold))
                    Text("v\(notice.latestVersion) · \(notice.title)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.68))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(notice.highlights, id: \.self) { highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tint)
                        Text(highlight)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 4)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("稍后") {
                    onLater()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                Button("查看更新") {
                    DispatchQueue.main.async {
                        onOpen()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 500)
        .background(.regularMaterial)
    }
}
