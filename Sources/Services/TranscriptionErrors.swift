import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case notAuthorized(SFSpeechRecognizerAuthorizationStatus)
    case recognizerUnavailable(String)
    case cliUnavailable
    case modelUnavailable
    case funASRCLIUnavailable
    case funASRModelUnavailable
    case funASRVADUnavailable
    case funASRExecutionFailed(String)
    case audioConversionFailed
    /// 无法读取用户选择的音频（常见于沙箱未拿到安全作用域，或拖入路径无效）。
    case audioSourceUnreadable
    case whisperExecutionFailed(String)
    case cloudNotConfigured
    case cloudRequestFailedWithDetail(String)
    case cloudResponseInvalid
    case timeout
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let status):
            "语音识别未授权（状态: \(status.rawValue)）"
        case .recognizerUnavailable(let language):
            "语言 \(language) 的识别器不可用"
        case .cliUnavailable:
            "whisper-cli 未安装，请先在本机安装 whisper-cpp"
        case .modelUnavailable:
            "Whisper 模型未下载，请先在设置中下载模型"
        case .funASRCLIUnavailable:
            "未检测到 llama-funasr-sensevoice。请通过 script/download_funasr_runtime.sh 安装，或重新打包应用。"
        case .funASRModelUnavailable:
            "FunASR SenseVoice 模型未下载，请先在设置中下载模型"
        case .funASRVADUnavailable:
            "FunASR VAD 模型未下载，请先在设置中下载 SenseVoice（会同时下载 VAD）"
        case .funASRExecutionFailed(let message):
            "FunASR 执行失败：\(message)"
        case .audioConversionFailed:
            "音频转换失败（afconvert）"
        case .audioSourceUnreadable:
            "无法读取所选音频。请用「打开」按钮重新选择文件，不要只依赖失效的最近项目路径；若从访达拖入失败，请改用打开面板。"
        case .whisperExecutionFailed(let message):
            "whisper-cli 执行失败：\(message)"
        case .cloudNotConfigured:
            "云端 ASR 未配置，请填写 Base URL、Key 和模型名"
        case .cloudRequestFailedWithDetail(let detail):
            "云端 ASR 错误：\(detail)"
        case .cloudResponseInvalid:
            "云端 ASR 响应格式异常"
        case .timeout:
            "转写超时（5分钟）"
        case .emptyResult:
            "没有识别出可用字幕"
        }
    }
}

enum TranscriptionService {
    static func createProvider(settings: AppSettings) -> TranscriptionProvider {
        var resolvedSettings = settings
        let segmentationConfiguration = SubtitleSegmentationConfiguration(
            maxCharacters: resolvedSettings.effectiveMaxSubtitleLength
        )

        switch resolvedSettings.transcriptionEngine {
        case .whisperLocal:
            return WhisperCppProvider(
                model: resolvedSettings.whisperModel,
                segmentationConfiguration: segmentationConfiguration
            )
        case .funASRLocal:
            return FunASRSenseVoiceProvider(
                model: .sensevoiceSmallQ8,
                segmentationConfiguration: segmentationConfiguration
            )
        case .appleSpeech:
            return AppleSpeechProvider(segmentationConfiguration: segmentationConfiguration)
        case .officialSmart:
            return OfficialSmartSubtitleProvider(segmentationConfiguration: segmentationConfiguration)
        case .cloudASR:
            SettingsStore.hydrateSecrets(into: &resolvedSettings, includeASR: true, includeLLM: false)
            return CloudASRProvider(
                apiURL: resolvedSettings.effectiveASRURL,
                apiKey: resolvedSettings.cloudASRKey,
                model: resolvedSettings.effectiveASRModel,
                segmentationConfiguration: segmentationConfiguration
            )
        }
    }
}
