import Foundation

enum VersionContentBuiltIn {
    static let help = VersionHelpDocument(
        version: VersionContentRuntime.appVersion.description,
        title: "SubForge 使用帮助",
        sections: [
            VersionHelpSection(
                title: "快速开始",
                body: "配置字幕方案后，从开始页导入音频或 SRT。音频会进入转写流程，SRT 会直接进入字幕编辑工作台。",
                bullets: [
                    "先在设置中选择官方、自定义或本地字幕方案。",
                    "转写完成后检查字幕文本和时间。",
                    "使用 ⌘E 导出 SRT 或 FCPXML。"
                ]
            ),
            VersionHelpSection(
                title: "Final Cut Pro 工作流",
                body: "可以在设置中选择视频创作总目录并开启目录监听，让 SubForge 自动接手 Final Cut Pro 导出的新音频。",
                bullets: [
                    "监听默认关闭，需要用户主动开启。",
                    "可以开启人工复核，避免自动导出未经检查的字幕。",
                    "菜单栏可以快速显示 SubForge、开始或停止监听。"
                ]
            ),
            VersionHelpSection(
                title: "常见问题",
                body: "首次使用麦克风、语音识别或控制 Final Cut Pro 时，macOS 可能会请求系统权限，请按实际工作流允许对应权限。",
                bullets: []
            )
        ]
    )

    static let release = VersionReleaseNote(
        version: VersionContentRuntime.appVersion.description,
        title: "当前 SubForge 版本",
        publishedAt: "",
        highlights: [
            "支持音频转写与 SRT 导入",
            "支持字幕编辑、SRT 和 FCPXML 导出",
            "支持本地识别与 Final Cut Pro 工作流"
        ],
        videoURL: nil
    )
}
