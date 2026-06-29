# 902 实现索引

当前仓库已经形成一批可继续复用的实现骨架，后续重做时优先沿这些边界继续整理，而不是重新堆回单文件。

| 编号 | 模块/能力 | 状态 | 备注 |
|------|-----------|------|------|
| I-001 | `AppModel` 全局状态骨架 | 已存在 | 统一管理模式切换、导入路由、最近项目、播放与导出 |
| I-002 | `RootView` 主窗口组装层 | 已存在 | 首页 / 流水线 / 编辑页的根切换入口 |
| I-003 | 首页工作区骨架 | 已存在 | `HomeView` + `ProjectSidebar` 组成首页导入与最近文件入口 |
| I-004 | 设置中心分文件结构 | 已存在 | 设置页按通用 / 转写 / 校对 / 样式 / 导出 / 监听拆分 |
| I-005 | 本地配置持久化 | 已存在 | `SettingsStore`、`RecentProjectsStore` 已独立 |
| I-006 | 字幕基础工具 | 已存在 | `SRTCodec`、`TimeFormatting` 已独立 |
| I-007 | 真实转写服务层 | 已存在 | `TranscriptionService` 已接入 Apple 语音 / 本地 Whisper / 云端 ASR |
| I-008 | 模型纠正服务层 | 已存在 | `ProofreadingService` 已接入 OpenAI 兼容模型纠正链路 |
| I-009 | Whisper 模型管理 | 已存在 | `WhisperModelStore`、`WhisperModelDownloader` 负责本地模型下载与检测 |
| I-010 | 设置验证资源 | 已存在 | `SettingsTestAsset` + 设置页验证结果组件已接入内置测试音频 / 文本 |
