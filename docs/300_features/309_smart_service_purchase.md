# 309 智能字幕与购买

状态：开发前检查完成

## 目标

在不破坏本地优先工作流的前提下，提供中国区托管云端ASR + AI校对、智能分钟购买、余额和任务状态。音频直接上传阿里临时OSS。

## 用户界面

设置新增“智能服务”：

- 当前处理区域：中国大陆（首版不可切换）。
- 剩余智能分钟与刷新状态。
- `300分钟`商品卡片；Mac App Store价格从StoreKit读取。
- 购买、恢复购买、管理购买问题入口。
- 数据路径和48小时临时存储说明。
- 官方智能模式开关与高级自定义Provider入口分离。

## 客户端流程

1. 从Keychain读取官方钱包Key并查询余额。
2. 选择智能模式处理音频时申请上传会话。
3. 使用返回的Policy、Signature和对象Key直传`upload_host`。
4. 提交`oss://`地址并轮询Model API任务。
5. 完成后把统一字幕片段交给现有编辑器和导出链路。

## Apple购买

- Product ID：`com.jago.subforge.smart.300min`。
- 商品类型：消耗型内购，发放18,000智能秒且余额不在客户端过期。
- 价格、货币和名称只使用StoreKit本地化Product。
- 签名交易提交Billing验证；Billing履约成功后才刷新钱包。
- 用户取消不报错；pending、失败和未验证交易给出明确状态。

## 区域扩展

- 客户端稳定枚举包含`china`和未来`international`，但首版界面和请求只允许`china`。
- 不保存阿里Base URL、Workspace、模型或云Key。
- 后续国际化只增加服务端Profile和界面选项，不改变购买资源与主流程。

## 开发前检查

- 复用KeychainStore、AppLog、Settings系统原生UI、现有流水线进度和TimedSubtitleSegmenter。
- 新增独立SmartService客户端、StoreKit购买服务和设置Pane，不继续堆入TranscriptionService。
- 官方服务与现有BYOK设置隔离，避免覆盖用户自定义Key。
