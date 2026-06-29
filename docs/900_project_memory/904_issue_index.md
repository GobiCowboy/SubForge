# 904 问题索引

| 编号 | 严重度 | 状态 | 问题 | 说明 |
|------|--------|------|------|------|
| ISSUE-001 | P1 | 已解决 | `swift build` 失败 | 已移除错误的测试目标声明，当前 `swift build` 与 `swift build -c release` 可通过 |
| ISSUE-002 | P1 | 已规避 | 直接运行裸可执行文件导致 GUI 行为不稳定 | SwiftUI GUI 统一通过 `script/build_and_run.sh` 或 `dist/SubForge.app` 启动，不再直接运行 `.build/.../SubForge` |

## 使用规则

- 这里只记录值得持续跟踪的问题
- 文档期发现的问题可以先登记，不要求当场修复
