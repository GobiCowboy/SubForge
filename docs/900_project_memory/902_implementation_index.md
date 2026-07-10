# 902 实现索引

当前仓库已经形成一批可继续复用的实现骨架，后续重做时优先沿这些边界继续整理，而不是重新堆回单文件。

| 编号 | 模块/能力 | 状态 | 备注 |
|------|-----------|------|------|
| I-001 | `AppModel` 全局状态骨架 | 已存在 | 统一管理模式切换、导入路由、最近项目、播放、按设置导出与 FCP 导入 |
| I-002 | `RootView` 主窗口组装层 | 已存在 | 首页 / 流水线 / 编辑页的根切换入口 |
| I-003 | 首页工作区骨架 | 已存在 | `HomeView` + `ProjectSidebar` 组成首页导入与最近文件入口 |
| I-004 | 设置中心分文件结构 | 已存在 | 设置页按通用 / 转写 / 校对 / 样式 / 导出 / 监听拆分 |
| I-005 | 本地配置持久化 | 已存在 | `SettingsStore`、`RecentProjectsStore` 已独立；云端 API Key 通过 `KeychainStore` 保存，目录授权通过 security-scoped bookmark 保存 |
| I-006 | 字幕基础工具 | 已存在 | `SRTCodec`、`TimeFormatting` 已独立 |
| I-007 | 真实转写服务层 | 已存在 | `TranscriptionService` 已接入 Apple 语音 / 本地 Whisper / 云端 ASR |
| I-008 | 模型纠正服务层 | 已存在 | `ProofreadingService` 已接入 OpenAI 兼容模型纠正链路 |
| I-009 | Whisper 模型管理 | 已存在 | `WhisperModelStore`、`WhisperModelDownloader` 负责本地模型下载与检测 |
| I-010 | 设置验证资源 | 已存在 | `SettingsTestAsset` + 设置页验证结果组件已接入内置测试音频 / 文本 |
| I-011 | 编辑键盘监视链路 | 已存在 | `EditorKeyboardMonitor` + `AppModel` 统一处理 `Space` / `Tab` / `J K L` / `Esc`，IME marked text 下放行 Space |
| I-012 | 媒体预览与波形层 | 已存在 | `MediaPlaybackService`、`WaveformAnalysisService` 已接入真实播放与波形分析 |
| I-013 | 快捷键说明组件 | 已存在 | `ShortcutGuideView` 同时服务右侧 Inspector 与全局说明弹层，快捷键以 keycap 方式渲染 |
| I-014 | 统一运行脚本 | 已存在 | `script/build_and_run.sh` 已覆盖 debug / release / verify / logs / telemetry |
| I-015 | 应用日志入口 | 已存在 | `AppLog` 已收口 editor / proofreading 等分类日志 |
| I-016 | FCP 目录监听服务 | 已存在 | `WatchFolderService` 负责轮询监听目录、稳定检测、FCP 元数据识别，并通过 `AppModel.importDocument(at:)` 接入现有处理链路 |
| I-017 | 菜单栏入口 | 已存在 | `MenuBarController` 持有 `NSStatusItem`，由通用设置控制显隐；`SubForgeAppDelegate` 同步 Dock/菜单栏模式，`MainWindowCloseBehavior` 将主窗口关闭改为隐藏 |
| I-018 | 带时间词元公共分段器 | 已存在 | `TimedSubtitleSegmenter` 统一处理 Apple segment、Whisper DTW token、DashScope word 的标点、字数、时长、英文边界与时间重叠 |
