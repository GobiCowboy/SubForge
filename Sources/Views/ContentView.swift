import SwiftUI

/// 主视图路由
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            if appState.audioFileURL != nil && !appState.segments.isEmpty && !appState.isTranscribing {
                EditorView()
            } else if appState.audioFileURL != nil {
                // 转写中 / 校对中
                pipelineProgressView
            } else {
                DropZoneView()
            }

            // Toast 覆盖层
            VStack {
                if let msg = appState.toastMessage {
                    ToastView(message: msg, type: appState.toastType)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: appState.toastMessage)
        }
    }

    private var pipelineProgressView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // 步骤指示器
                VStack(spacing: 20) {
                    pipelineStep(
                        icon: "waveform",
                        label: "语音转写",
                        status: appState.transcriptionStep
                    )

                    if appState.settings.proofreadingEnabled {
                        pipelineStep(
                            icon: "text.checker",
                            label: "AI 校对（\(appState.settings.proofreadingEngine.rawValue)）",
                            status: appState.proofreadingStep
                        )
                    }
                }
                .frame(width: 360)

                // 进度条
                VStack(spacing: 8) {
                    ProgressView(value: appState.pipelineProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 300)

                    Text(appState.transcriptionProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button("取消") {
                    appState.reset()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pipelineStep(icon: String, label: String, status: PipelineStepStatus) -> some View {
        HStack(spacing: 12) {
            // 状态图标
            Group {
                switch status {
                case .pending:
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                case .running:
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 24, height: 24)
                }
            }

            // 图标 + 标签
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(status == .pending ? .tertiary : .primary)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14, weight: status == .running ? .medium : .regular))
                .foregroundStyle(status == .pending ? .tertiary : .primary)

            Spacer()
        }
    }
}
