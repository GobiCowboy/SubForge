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
| ISSUE-014 | P0 | 待TestFlight验收 | TestFlight首装无法领取10分钟体验 | 根因是`AppTransaction.shared`返回`SKInternalErrorDomain Code=13`；已增加`AppTransaction.refresh()`恢复路径、设置页重试与可见错误提示 |
| ISSUE-015 | P0 | 待TestFlight验收 | 智能字幕轮询遇到临时服务错误后丢失任务 | 客户端现对轮询阶段的 5xx 和可恢复网络错误继续重试，不再因单次临时故障直接退出并触发后续 `ACTIVE_TASK_EXISTS` |
| ISSUE-016 | P1 | 已解决 | 本地构建切换官方服务时频繁弹出钥匙串密码框 | 已按本地、开发和 App Store 签名通道隔离官方凭据，所有钥匙串读写均禁止交互，页面切换时使用内存缓存避免重复读取 |
| ISSUE-017 | P0 | 待TestFlight验收 | TestFlight 点击购买按钮没有可见反馈 | 购买前主动查询 StoreKit 商品，并在购买区显示连接中、商品不可用、购买窗口、取消、失败和到账状态；商品加载错误不再静默吞掉 |
| ISSUE-018 | P0 | 已解决 | 官方服务返回的长字幕未严格遵守最大字数 | 官方结果在进入编辑器前再次执行客户端强制分段，分段器增加硬字数上限，单个超长英文词也不能越界 |
| ISSUE-019 | P2 | 已解决 | 字幕设置页信息层级和控件布局不符合验收稿 | 已精简官方功能说明、改用字数滑杆、把配置状态放入转写与 AI 校对标签，并将本地实验提示移到标签下方 |
| ISSUE-020 | P1 | 已解决 | 设置页卡片边界过浅且页面标题不统一 | 已按选定的方案一重做字幕页层级：统一所有设置页标题规格；以官方页为基准抽出公共边框 token，所有设置容器统一引用；字幕字数限制移入各方案配置并分别保存，顶部不再显示公共滑杆 |
| ISSUE-021 | P0 | 待在线验收 | 创建 Apple 内购订单返回 `APPLICATION_REQUIRED` | 创建订单请求现显式携带 `applicationId=subforge`，并增加请求体回归测试 |
| ISSUE-022 | P1 | 待修复 | 客户端最大字数分段在语义中间硬切 | 官方长字幕虽已受最大字数约束，但公共分段器会把 `Final Cut Pro`、`Apple Speech` 及中文短语从中间拆开；应将字数作为目标值，按标点、停顿和词组边界回退分段 |
| ISSUE-023 | P1 | 待修复 | 官方智能字幕进度未区分 ASR 转写与 AI 校对 | 当前服务端只回传笼统 `processing`，客户端把它显示成“云端转写与 AI 校对”；应映射为可验证的独立阶段，不能在服务端完成前提前标记校对完成 |
| ISSUE-024 | P0 | 待修复 | StoreKit Sandbox 成交后钱包额度未到账 | Apple 沙盒交易已验证并完成，但订单轮询未进入 `paid`，需核对 App Store Server Notifications V2 的 Sandbox 回调、应用路由、环境和 `appAccountToken` 订单匹配 |
| ISSUE-025 | P1 | 待修复 | 流水线取消语义不完整 | 当前客户端退出并取消本地任务，但官方云任务提交后只停止轮询，服务端可能继续处理；需要明确本地停止、上传终止及云任务取消/不可取消反馈 |

## 使用规则

- 这里只记录值得持续跟踪的问题
- 文档期发现的问题可以先登记，不要求当场修复
