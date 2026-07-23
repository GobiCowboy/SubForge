import Foundation

extension AppModel {
    /// 解析实际可用引擎；缺运行时/模型时回退 Apple 语音并给出说明。
    func resolveTranscriptionEngine(from settings: AppSettings) -> (
        settings: AppSettings,
        didFallback: Bool,
        fallbackMessage: String?
    ) {
        var resolved = settings
        switch settings.transcriptionEngine {
        case .whisperLocal:
            if !WhisperRuntime.isCLIAvailable {
                resolved.transcriptionEngine = .appleSpeech
                return (
                    resolved,
                    true,
                    "已回退：未检测到 Whisper 运行组件，改用 Apple 语音"
                )
            }
            if !WhisperModelStore.isAvailable(settings.whisperModel),
               WhisperModelStore.availableModels().isEmpty {
                resolved.transcriptionEngine = .appleSpeech
                return (
                    resolved,
                    true,
                    "已回退：Whisper 模型未下载，改用 Apple 语音"
                )
            }
        case .funASRLocal:
            if !FunASRRuntime.isCLIAvailable {
                resolved.transcriptionEngine = .appleSpeech
                return (
                    resolved,
                    true,
                    "已回退：未检测到 FunASR 运行组件，改用 Apple 语音"
                )
            }
            if !FunASRModelStore.isReady() {
                resolved.transcriptionEngine = .appleSpeech
                return (
                    resolved,
                    true,
                    "已回退：FunASR 模型或 VAD 未就绪，改用 Apple 语音"
                )
            }
        case .officialSmart, .cloudASR, .appleSpeech:
            break
        }
        return (resolved, false, nil)
    }
}
