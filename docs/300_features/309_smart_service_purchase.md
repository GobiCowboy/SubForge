# 309 智能字幕与购买

状态：基础实现已验收，待App Store Sandbox和阿里真实云联调

## 目标

在不破坏本地优先工作流的前提下，提供中国区托管云端ASR + AI校对、智能分钟购买、余额和任务状态。音频直接上传阿里临时OSS。

## 用户界面

设置新增“智能服务”：

- 当前处理区域：中国大陆（首版不可切换）。
- 剩余智能分钟与刷新状态。
- `60分钟`与`300分钟`两个商品卡片；Mac App Store价格从StoreKit读取，默认选中300分钟。
- 购买、到账等待和手动刷新入口；消耗型商品不提供“恢复购买”。
- 数据路径、临时存储与按秒计费说明。
- 官方智能模式开关与高级自定义Provider入口分离。

## 客户端流程

1. 从Keychain读取官方钱包Key并查询余额。
2. 选择智能模式处理音频时申请上传会话。
3. 使用返回的Policy、Signature和对象Key直传`upload_host`。
4. 提交`oss://`地址并轮询Model API任务。
5. 完成后把统一字幕片段交给现有编辑器和导出链路。
6. 用户中途取消时调用任务取消接口；已预留但未结算的秒数由服务端返还，客户端不继续轮询或回填结果。

## Apple购买

- Product ID：`com.jago.subforge.smart.60min`（发放3,600智能秒）与`com.jago.subforge.smart.300min`（发放18,000智能秒）。
- 商品类型：消耗型内购，余额不在客户端过期。
- 价格、货币和名称只使用StoreKit本地化Product。
- StoreKit本地验证只用于客户端状态；真正入账只信任Apple Server Notifications V2的服务端签名通知。
- Billing履约成功后客户端才刷新钱包，客户端purchase success不自行增加额度。
- 客户端在App Store包中保留已完成消耗型交易历史；购买后、App启动或手动刷新时，把未确认的transaction ID交给Billing，由Billing向Apple主动核验并补偿漏通知订单。
- Billing每5分钟拉取Apple失败通知历史并走同一验签履约路径，客户端不打开也能恢复漏单。
- 本地、Sandbox Development和App Store使用独立钥匙串service，构建包显式声明签名渠道，避免开发包读取TestFlight凭证而反复弹窗。
- StoreKit交易只在Billing确认额度已发放后调用`finish()`；未到账交易保持unfinished，应用重启后继续恢复。
- 到账等待最长约40秒，超时后恢复按钮并提示稍后刷新，不再持续转圈三分钟。
- 用户取消不报错；pending、失败和未验证交易给出明确状态。

## 区域扩展

- 客户端稳定枚举包含`china`和未来`international`，但首版界面和请求只允许`china`。
- 不保存阿里Base URL、Workspace、模型或云Key。
- 后续国际化只增加服务端Profile和界面选项，不改变购买资源与主流程。

## 开发前检查

- 复用KeychainStore、AppLog、Settings系统原生UI、现有流水线进度和TimedSubtitleSegmenter。
- 新增独立SmartService客户端、StoreKit购买服务和设置Pane，不继续堆入TranscriptionService。
- 官方服务与现有BYOK设置隔离，避免覆盖用户自定义Key。

## 实现与验证

- `SmartServiceStore`：StoreKit商品、pending Key入Keychain、`appAccountToken`购买、Billing轮询和钱包刷新。
- TestFlight首装读取`AppTransaction.shared`失败时按StoreKit恢复路径调用`AppTransaction.refresh()`；打开智能服务设置页会再次尝试领取，失败时显示可见提示。
- `OfficialSmartServiceClient`：中国区钱包、上传会话、任务提交与轮询；官方Key与BYOK Key分开。
- `OSSMultipartUploader`：将音频写入沙箱临时multipart文件后流式直传阿里HTTPS Host，请求完成后删除临时副本。
- 智能服务设置Pane已接入剩余时长、官方区域、购买、刷新和设为当前引擎。
- `swift build`通过；`swift test`共18项通过，其中3项固定中国区、语言映射和三端商品ID契约。
- 待联调：StoreKit Sandbox真实商品与Server Notification、阿里上传Policy、长音频直传、ASR、校对和实际秒数。
