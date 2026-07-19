import SwiftUI

struct PipelineProgressView: View {
    @EnvironmentObject private var model: AppModel
    let onCancel: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    Text(model.currentDocumentName)
                        .font(.system(size: 15, weight: .semibold))
                    Text("SubForge 正在生成字幕")
                        .font(.system(size: 28, weight: .semibold))
                    Text(model.pipelineMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    ForEach(model.pipelineStages) { stage in
                        HStack(spacing: 12) {
                            stageIcon(stage)
                            Text(stage.title)
                                .font(.system(size: 14, weight: stage.status == .active ? .semibold : .regular))
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: 320)

                VStack(spacing: 8) {
                    ProgressView(value: model.pipelineProgress)
                        .frame(width: 320)
                    Text("\(Int(model.pipelineProgress * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func stageIcon(_ state: PipelineStageState) -> some View {
        switch state.status {
        case .pending:
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1.5)
                .frame(width: 20, height: 20)
        case .active:
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 20, height: 20)
        }
    }
}
