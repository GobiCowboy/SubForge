import Foundation

enum FeedbackType: String, CaseIterable, Identifiable, Sendable {
    case featureSuggestion = "功能建议"
    case problemReport = "问题反馈"
    case experienceOpinion = "体验意见"

    var id: String { rawValue }
}
