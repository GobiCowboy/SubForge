# 904 问题索引

| 编号 | 严重度 | 状态 | 问题 | 说明 |
|------|--------|------|------|------|
| ISSUE-001 | P1 | 已解决 | `swift build` 失败 | 已移除错误的测试目标声明，当前 `swift build` 与 `swift build -c release` 可通过 |
| ISSUE-002 | P1 | 已规避 | 直接运行裸可执行文件导致 GUI 行为不稳定 | SwiftUI GUI 统一通过 `script/build_and_run.sh` 或 `dist/SubForge.app` 启动，不再直接运行 `.build/.../SubForge` |
| ISSUE-003 | P0 | 待外部处理 | 缺少 Mac App Store 分发证书 | 当前本机只有 Apple Development 和 Developer ID Application，`script/release_appstore.sh --signed` 会停止，需安装 Mac App Store app / installer signing identity |

## 使用规则

- 这里只记录值得持续跟踪的问题
- 文档期发现的问题可以先登记，不要求当场修复
