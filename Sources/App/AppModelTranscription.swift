import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func startTranscription(for url: URL) {
        guard settings.allowsTranscriptionAfterValidation else {
            notifyUser(
                "当前转写方案验证失败，请修改配置或重新验证后再试。",
                level: .error,
                duration: 5
            )
            return
        }

        if settings.proofreadingEnabled,
           settings.transcriptionEngine != .officialSmart,
           !settings.shouldRunProofreading {
            notifyUser(
                "AI 校对尚未通过验证，本次只进行转写。",
                level: .info,
                duration: 4
            )
        }

        requestHotwordsOrStart(for: url)
    }

    func beginTranscriptionPipeline(for url: URL, runOptions: TranscriptionRunOptions) {
        var pipelineSettings = settings
        pipelineSettings.maxSubtitleLength = runOptions.maxSubtitleLength
        pipelineSettings.proofreadingPrompt = runOptions.proofreadingPrompt
        pipelineSettings.retainedSubtitlePunctuation = runOptions.retainedPunctuation
        if pipelineSettings.transcriptionEngine != .officialSmart,
           !pipelineSettings.shouldRunProofreading {
            pipelineSettings.proofreadingEnabled = false
        }

        stopPlayback(captureTimestamp: false)
        pipelineTask?.cancel()
        stopPipelineClock()
        mode = .progress
        currentDocumentURL = url
        segments = []
        selectedSegmentID = nil
        currentTime = 0
        playbackDuration = 0
        pipelineStages = Self.makePipelineStages(
            proofreadingEnabled: pipelineSettings.shouldRunProofreading,
            officialSmart: pipelineSettings.transcriptionEngine == .officialSmart
        )
        pipelineProgress = 0
        let initialEngine = pipelineSettings.transcriptionEngine
        startPipelineClock(
            modelLabel: displayName(for: initialEngine, settings: pipelineSettings),
            usesLocalEngine: initialEngine.isLocal
        )

        pipelineTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 先解析引擎，再开秒表，文案从一开始就带模型名
                let resolution = self.resolveTranscriptionEngine(from: pipelineSettings)
                var transcriptionSettings = resolution.settings
                if resolution.didFallback {
                    self.settings.transcriptionEngine = transcriptionSettings.transcriptionEngine
                    self.showToast(resolution.fallbackMessage ?? "已回退到可用转写引擎", level: .error, duration: 4.5)
                }

                if transcriptionSettings.transcriptionEngine == .cloudASR {
                    var hydrated = transcriptionSettings
                    SettingsStore.hydrateSecrets(into: &hydrated, includeASR: true, includeLLM: false)
                    let key = hydrated.cloudASRKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if key.isEmpty || hydrated.effectiveASRURL.isEmpty || hydrated.effectiveASRModel.isEmpty {
                        throw TranscriptionError.cloudNotConfigured
                    }
                    transcriptionSettings = hydrated
                }
                if transcriptionSettings.transcriptionEngine == .officialSmart {
                    switch KeychainStore.readResult(.officialServiceKey) {
                    case .notFound:
                        let activation = await self.smartService.activateTrialIfNeeded()
                        self.presentTrialActivation(activation)
                    case .value:
                        await self.smartService.refreshWallet()
                    case .unavailable:
                        throw OfficialSmartServiceError.keychainUnavailable
                    }
                    guard case .value(let key) = KeychainStore.readResult(.officialServiceKey),
                          !key.isEmpty else {
                        throw OfficialSmartServiceError.keyMissing
                    }
                    if self.smartService.balanceSeconds > 0 {
                        self.showToast(
                            "智能字幕可用时长：\(self.smartService.balanceText)",
                            level: .info,
                            duration: 3.5
                        )
                    }
                }

                let engine = transcriptionSettings.transcriptionEngine
                let modelLabel = self.displayName(for: engine, settings: transcriptionSettings)
                self.updatePipelineClockContext(
                    modelLabel: modelLabel,
                    usesLocalEngine: engine.isLocal
                )

                self.markStageActive(.prepare, progress: 0.14, message: "")
                self.setPipelinePhase("准备音频", progress: 0.14)
                // 短停留，让 UI 阶段点亮；真正拷文件在 transcribe 内
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else {
                    self.stopPipelineClock()
                    return
                }
                self.markStageDone(.prepare, progress: 0.2)

                let provider: TranscriptionProvider
                if engine == .officialSmart {
                    provider = OfficialSmartSubtitleProvider(
                        segmentationConfiguration: SubtitleSegmentationConfiguration(
                            maxCharacters: runOptions.maxSubtitleLength
                        ),
                        proofreadingPrompt: runOptions.composedProofreadingPrompt
                    ) { [weak self] update in
                        Task { @MainActor in
                            self?.handleOfficialSmartProgress(update)
                        }
                    }
                } else {
                    provider = TranscriptionService.createProvider(settings: transcriptionSettings)
                }
                if engine == .officialSmart {
                    // 官方智能字幕的上传是独立可见阶段，后续状态由服务端回调推进。
                    self.markStageActive(.prepare, progress: 0.2, message: "")
                    self.setPipelinePhase("准备上传", progress: 0.2)
                } else {
                    self.markStageActive(.transcribe, progress: 0.36, message: "")
                    self.setPipelinePhase("转写中", progress: 0.36)
                }

                var transcribedSegments = try await provider.transcribe(audioURL: url, language: transcriptionSettings.language)
                if engine == .officialSmart {
                    await self.smartService.refreshWallet()
                }
                transcribedSegments = self.normalizeSegments(transcribedSegments, stripTrailingPunctuation: false)
                guard !Task.isCancelled else {
                    self.stopPipelineClock()
                    return
                }

                let usesOfficialProofreading = engine == .officialSmart
                let willAttemptProofread = usesOfficialProofreading || transcriptionSettings.shouldRunProofreading

                var finalSegments = transcribedSegments
                var proofreadingNote: String?
                if usesOfficialProofreading {
                    self.markStageDone(.prepare, progress: 0.94)
                    self.markStageDone(.transcribe, progress: 0.94)
                    self.markStageDone(.proofread, progress: 0.94)
                    self.markStageActive(.complete, progress: 0.96, message: "")
                    self.setPipelinePhase("完成字幕", progress: 0.96)
                    proofreadingNote = "官方 AI 校对已完成"
                } else {
                    self.markStageDone(.transcribe, progress: willAttemptProofread ? 0.72 : 0.92)
                }

                if !usesOfficialProofreading, willAttemptProofread {
                    var proofSettings = transcriptionSettings
                    SettingsStore.hydrateSecrets(into: &proofSettings, includeASR: false, includeLLM: true)
                    if let warning = proofSettings.proofreadingConfigWarning {
                        proofreadingNote = warning + "，已跳过校对"
                        self.markStageDone(.proofread, progress: 0.92)
                        self.showToast(proofreadingNote!, level: .error, duration: 4.5)
                    } else if let proofreadingProvider = ProofreadingService.createProvider(settings: proofSettings) {
                        self.markStageActive(.proofread, progress: 0.8, message: "")
                        self.setPipelinePhase("AI 校对", progress: 0.8)
                        do {
                            let corrected = try await proofreadingProvider.proofread(
                                segments: transcribedSegments,
                                batchSize: 60,
                                prompt: runOptions.composedProofreadingPrompt,
                                strictCorrections: proofSettings.proofreadingStrictCorrections
                            )
                            let normalizedCorrected = self.normalizeSegments(corrected, stripTrailingPunctuation: false)
                            if normalizedCorrected.isEmpty {
                                finalSegments = transcribedSegments
                                proofreadingNote = "模型纠正返回空结果，已保留原始转写"
                                self.showToast(proofreadingNote!, level: .error, duration: 4)
                            } else {
                                finalSegments = normalizedCorrected
                                proofreadingNote = "AI 校对已完成"
                            }
                            self.markStageDone(.proofread, progress: 0.92)
                        } catch {
                            self.markStageFailed(.proofread, progress: 0.92)
                            proofreadingNote = "模型纠正失败，已保留原始转写"
                            self.showToast(
                                "模型纠正失败，已保留原始转写结果：\(error.localizedDescription)",
                                level: .error,
                                duration: 4.5
                            )
                        }
                    } else {
                        proofreadingNote = "AI 校对无法启动，已跳过"
                        self.markStageDone(.proofread, progress: 0.92)
                        self.showToast(proofreadingNote!, level: .error, duration: 4)
                    }
                }

                guard !Task.isCancelled else {
                    self.stopPipelineClock()
                    self.pipelineTask = nil
                    return
                }

                finalSegments = finalSegments.compactMap { segment in
                    var formatted = segment
                    formatted.text = SubtitleTextFormatting.applyingPunctuationPolicy(
                        segment.text,
                        retained: runOptions.retainedPunctuation
                    )
                    return formatted.text.isEmpty ? nil : formatted
                }

                let totalSeconds = self.pipelineElapsedSeconds()
                self.pipelinePhaseLabel = "完成"
                self.pipelineMessage = "\(modelLabel) · 完成 · \(totalSeconds)s"
                self.pipelineProgress = 1.0
                self.stopPipelineClock()

                self.markStageActive(.complete, progress: 1.0, message: self.pipelineMessage)
                self.segments = finalSegments
                self.selectedSegmentID = finalSegments.first?.id
                self.playbackDuration = (finalSegments.last?.end ?? 0) + 1.5
                self.playbackDuration = max(self.playbackDuration, self.playbackService.mediaDuration)
                self.currentTime = 0
                self.mode = .editor
                self.addRecentProject(for: url, kind: mediaKind(for: url), subtitleCount: finalSegments.count)
                self.markStageDone(.complete, progress: 1.0)

                self.showToast("已生成 \(finalSegments.count) 条字幕", level: .success)
                self.pipelineTask = nil
            } catch {
                if Task.isCancelled {
                    self.stopPipelineClock()
                    self.pipelineTask = nil
                    return
                }
                if self.settings.transcriptionEngine == .officialSmart {
                    await self.smartService.refreshWallet()
                }
                let failedSeconds = self.pipelineElapsedSeconds()
                self.stopPipelineClock()
                self.pipelineTask = nil
                self.mode = .home
                self.pipelineMessage = failedSeconds > 0 ? "转写失败 · \(failedSeconds)s" : "转写失败"
                self.showToast(self.pipelineErrorMessage(for: error), level: .error, duration: 4.5)
            }
        }
    }

}
