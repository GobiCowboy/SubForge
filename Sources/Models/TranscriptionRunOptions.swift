import Foundation

struct TranscriptionRunOptions: Equatable {
    let maxSubtitleLength: Int
    let retainedPunctuation: Set<SubtitlePunctuationGroup>
    let proofreadingPrompt: String
    let hotwords: [String]

    init(settings: AppSettings, hotwords: [String]) {
        maxSubtitleLength = settings.effectiveMaxSubtitleLength
        retainedPunctuation = settings.effectiveRetainedSubtitlePunctuation
        proofreadingPrompt = settings.proofreadingPrompt
        let fixedHotwords = settings.effectiveFixedHotwordsEnabled
            ? HotwordInputParser.parse(settings.effectiveFixedHotwordsText)
            : []
        self.hotwords = HotwordInputParser.merging(fixedHotwords, hotwords)
    }

    var composedProofreadingPrompt: String {
        ProofreadingPromptComposer.userPrompt(
            basePrompt: proofreadingPrompt,
            hotwords: hotwords
        )
    }
}

struct HotwordPromptRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        case onboarding
        case entry
    }

    let id = UUID()
    let url: URL
    let kind: Kind
}
