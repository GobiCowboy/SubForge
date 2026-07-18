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
| ISSUE-008 | P0 | 已解决 | App Store `--upload` 误用 ad-hoc 签名 | `release_appstore.sh` 原先只对 `--signed` / `--package` 调 `sign_app`，`--upload` 落到 ad-hoc；App Store Connect 拒绝。现已让三种正式发布模式统一走分发签名 |
| ISSUE-009 | P0 | 已解决 | Developer ID 包启用 App Sandbox 无法启动 | 站外公证包若套用 App Store sandbox entitlements，launchd 会以 RBSRequestError / POSIX 163 拒绝启动。现已使用独立的 `Config/SubForge.developer-id.entitlements`（无 Sandbox） |
| ISSUE-010 | P0 | 已解决 | Developer ID 嵌套 `whisper-cli` 被信号 5 杀掉 | 主程序无 Sandbox 时，对 `Frameworks/whisper-cli` 使用 sandbox+inherit 会 SIGTRAP。现与主程序同用 developer-id entitlements 签名 |
| ISSUE-011 | P0 | 已解决 | DashScope filetrans 长音频 413 RequestTooLarge | 原实现把整文件 Base64 塞进 `file_url` 导致请求体超限。现改为百炼临时上传拿 `oss://` URL，提交时带 `X-DashScope-OssResourceResolve: enable` |
| ISSUE-012 | P0 | 发布前联调 | 智能字幕尚未经StoreKit Sandbox与阿里真实云端到端验收 | 需验证商品、Server Notification、pending Key激活、Policy直传、ASR、AI校对和按秒结算 |
| ISSUE-013 | P1 | 预期限制 | Developer ID站外包不能完成Mac App Store消耗型内购 | 购买入口以StoreKit商品可用性为准；正式付费能力在Mac App Store包验收 |

## 使用规则

- 这里只记录值得持续跟踪的问题
- 文档期发现的问题可以先登记，不要求当场修复
