import Foundation

enum FeedbackComposer {
    static let recipient = "guojin.writer@outlook.com"

    static func mailURL(type: FeedbackType, section: UsageAndUpdatesSection, details: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[SubForge 意见] \(type.rawValue)"),
            URLQueryItem(name: "body", value: body(type: type, section: section, details: details))
        ]
        return components.url
    }

    private static func body(type: FeedbackType, section: UsageAndUpdatesSection, details: String) -> String {
        """
        产品：SubForge
        App 版本：v\(VersionContentRuntime.appVersion)
        系统平台：macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        反馈类型：\(type.rawValue)
        当前页面/模块：\(section.rawValue)

        具体内容：
        \(details.trimmingCharacters(in: .whitespacesAndNewlines))

        注：本邮件不会自动附加日志、截图或媒体文件。
        """
    }
}
