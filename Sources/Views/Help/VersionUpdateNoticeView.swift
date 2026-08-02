import SwiftUI

struct VersionUpdateNoticeView: View {
    let notice: VersionUpdateNotice
    let onLater: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("SubForge 有新版本")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("v\(notice.latestVersion) · \(notice.title)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(notice.highlights, id: \.self) { highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tint)
                        Text(highlight)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("稍后") { onLater() }
                    .keyboardShortcut(.cancelAction)
                Button("查看更新") { onOpen() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(.regularMaterial)
    }
}
