# 904 问题索引

| 编号 | 严重度 | 状态 | 问题 | 说明 |
|------|--------|------|------|------|
| ISSUE-001 | P1 | 已解决 | `swift build` 失败 | 已移除错误的测试目标声明，当前 `swift build` 与 `swift build -c release` 可通过 |
| ISSUE-002 | P1 | 已规避 | 直接运行裸可执行文件导致 GUI 行为不稳定 | SwiftUI GUI 统一通过 `script/build_and_run.sh` 或 `dist/SubForge.app` 启动，不再直接运行 `.build/.../SubForge` |
| ISSUE-003 | P1 | 已解决 | App Store 脚本未自动找到 installer 证书和 provisioning profile | Installer 证书不能用 `security find-identity -p codesigning` 查找；脚本已改用 `security find-certificate`，并自动查找 `SubForge_Mac_App_Store.provisionprofile` |
| ISSUE-004 | P1 | 已解决 | 字幕被硬切到词语中间 | 本地 Whisper 移除 `--max-len 20` 预切分，公共分段器先合并相邻续句再按标点重切，避免 `Synima / mode`、`让整 / 个` 这类断句 |
| ISSUE-005 | P0 | 待验收 | 无效云端 ASR URL 导致应用崩溃 | 移除 `URL(...)!` 强制解包，所有云端入口先验证 HTTP(S) endpoint，无效配置返回可读错误 |
| ISSUE-006 | P1 | 待验收 | Whisper 公共分段后丢失第一句 | 旧前导静音检测误判并清空首段词元；DTW 链路已移除该旧修正，完整保留首段 tokens |
| ISSUE-007 | P1 | 待验收 | Apple 短字幕跨越长停顿 | 对超过 5.2 秒的异常单 segment duration 按文本长度收敛，不让短词覆盖十几秒静音 |

## 使用规则

- 这里只记录值得持续跟踪的问题
- 文档期发现的问题可以先登记，不要求当场修复
