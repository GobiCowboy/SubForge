import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    static func makePipelineStages(
        proofreadingEnabled: Bool,
        officialSmart: Bool
    ) -> [PipelineStageState] {
        let stages: [PipelineStage]
        if officialSmart {
            stages = [.prepare, .transcribe, .proofread, .complete]
        } else {
            stages = proofreadingEnabled
                ? [.prepare, .transcribe, .proofread, .complete]
                : [.prepare, .transcribe, .complete]
        }
        return stages.map { stage in
            let title: String
            if officialSmart {
                switch stage {
                case .prepare: title = "准备上传"
                case .transcribe: title = "语音转写"
                case .proofread: title = "智能校对"
                case .complete: title = "完成字幕"
                }
            } else {
                title = stage.rawValue
            }
            return PipelineStageState(stage: stage, title: title, status: .pending)
        }
    }

    func handleOfficialSmartProgress(_ update: OfficialSmartProgressUpdate) {
        guard mode == .progress else { return }
        switch update.phase {
        case .securingUpload:
            markStageActive(.prepare, progress: update.progress, message: "")
            setPipelinePhase("准备安全上传", progress: update.progress)
        case .uploading:
            markStageActive(.prepare, progress: update.progress, message: "")
            setPipelinePhase("上传音频", progress: update.progress)
        case .transcribing:
            markStageDone(.prepare, progress: update.progress)
            markStageActive(.transcribe, progress: update.progress, message: "")
            setPipelinePhase("语音转写", progress: update.progress)
        case .proofreading:
            markStageDone(.prepare, progress: update.progress)
            markStageDone(.transcribe, progress: update.progress)
            markStageActive(.proofread, progress: update.progress, message: "")
            setPipelinePhase("智能校对", progress: update.progress)
        case .finishing:
            markStageDone(.prepare, progress: update.progress)
            markStageDone(.transcribe, progress: update.progress)
            markStageDone(.proofread, progress: update.progress)
            markStageActive(.complete, progress: update.progress, message: "")
            setPipelinePhase("完成字幕", progress: update.progress)
        }
    }

    func presentTrialActivation(_ activation: SmartTrialActivation) {
        switch activation {
        case .granted(let seconds):
            showToast("首次安装已赠送 \(seconds / 60) 分钟智能字幕体验", level: .success, duration: 5)
        case .restored(let seconds):
            showToast("已恢复 \(seconds / 60) 分钟智能字幕体验凭证", level: .info, duration: 4)
        case .unavailable(let message):
            showToast("暂时无法领取体验额度：\(message)", level: .error, duration: 5)
        case .notNeeded:
            break
        }
    }

    func pipelineErrorMessage(for error: Error) -> String {
        switch error {
        case OfficialSmartServiceError.insufficientCredits:
            return "智能字幕时长不足，请前往“设置 > 字幕”购买"
        case OfficialSmartServiceError.additionalCreditsRequired(let seconds):
            return "智能字幕时长不足，还需要 \(seconds) 秒；当前方案保持不变"
        case OfficialSmartServiceError.keyMissing:
            return "暂时无法领取体验额度，请稍后重试或前往“设置 > 字幕”"
        default:
            return "转写失败：\(error.localizedDescription)"
        }
    }

    func advancePipeline(_ stage: PipelineStage, progress: Double, message: String) async {
        guard !Task.isCancelled else { return }
        for index in pipelineStages.indices {
            switch pipelineStages[index].stage {
            case stage:
                pipelineStages[index].status = .active
            default:
                break
            }
        }
        pipelineMessage = message
        pipelineProgress = progress
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        for index in pipelineStages.indices where pipelineStages[index].stage == stage {
            pipelineStages[index].status = .done
        }
    }

    func markStageActive(_ stage: PipelineStage, progress: Double, message: String) {
        for index in pipelineStages.indices {
            switch pipelineStages[index].stage {
            case stage:
                pipelineStages[index].status = .active
            case .prepare where stage != .prepare:
                if pipelineStages[index].status == .active {
                    pipelineStages[index].status = .done
                }
            default:
                break
            }
        }
        pipelineProgress = progress
        pipelineMessage = message
    }

    func markStageDone(_ stage: PipelineStage, progress: Double) {
        for index in pipelineStages.indices where pipelineStages[index].stage == stage {
            pipelineStages[index].status = .done
        }
        pipelineProgress = progress
    }

    func markStageFailed(_ stage: PipelineStage, progress: Double) {
        for index in pipelineStages.indices where pipelineStages[index].stage == stage {
            pipelineStages[index].status = .failed
        }
        pipelineProgress = progress
    }

    func normalizeSegments(
        _ segments: [SubtitleSegment],
        stripTrailingPunctuation: Bool
    ) -> [SubtitleSegment] {
        segments
            .map { segment in
                var normalized = segment
                var text = normalized.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if stripTrailingPunctuation {
                    text = SubtitleTextFormatting.stripTrailingLineEndPunctuation(text)
                }
                normalized.text = text
                return normalized
            }
            .filter { !$0.text.isEmpty }
    }

    func mediaKind(for url: URL) -> String {
        Self.supportedSubtitleExtensions.contains(url.pathExtension.lowercased()) ? "srt" : "audio"
    }

    func importSRT(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let parsed = SRTCodec.parse(content)
            guard !parsed.isEmpty else {
                showToast("SRT 文件为空或格式无法识别", level: .error)
                return
            }
            stopPlayback()
            currentDocumentAccess = nil
            currentDocumentURL = url
            segments = parsed
            selectedSegmentID = parsed.first?.id
            subtitleTextCaret = nil
            playbackDuration = (parsed.last?.end ?? 0) + 1.5
            currentTime = 0
            waveformSamples = []
            isEditingSubtitle = false
            editorFocusContext = .none
            activeEditorSurface = .table
            clearPlaybackMedia()
            mode = .editor
            addRecentProject(for: url, kind: "srt", subtitleCount: parsed.count)
            showToast("已导入 \(parsed.count) 条字幕", level: .success)
        } catch {
            showToast("读取 SRT 失败：\(error.localizedDescription)", level: .error)
        }
    }
}
