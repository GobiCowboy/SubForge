# 字幕流水线后续详细修改方案

日期：2026-07-26

关联测试总结：`docs/test-summary-and-modification-plan-2026-07-26.md`

## 实施状态（2026-07-26）

本方案已在客户端和官方 Model API 落地：

- 公共最大字数完成一次性32字迁移，之后始终使用用户设置。
- 通用设置已集中最大字数、保留标点、逐视频热词、固定热词和AI校对提示词；方案页重复项已删除。
- 公共分段器已实现source segment硬边界、一级标点切分、二级标点超长回退、有效字数和短句向后合并。
- 热词首次启用、逐视频输入、固定热词独立开关、两类热词合并、任务快照和目录监听等待流程已接入。
- 本地与官方AI校对均使用严格编号验证；官方请求已透传`proofreadingPrompt`。
- 最终标点策略只在最后一个自动文本阶段后执行一次。
- 客户端58项测试、官方Model API 22项测试与TypeScript类型检查通过；macOS调试包已构建并验证启动。

仍需真实线上环境验收官方热词校对和完整音频任务。

## 1. 本次修改目标

本轮修改要统一解决四类问题：

1. 所有转写方案使用同一套字幕切分规则和公共设置。
2. `qwen3-asr-flash-filetrans` 只提供 ASR segment、文字和时间戳，本地负责最终字幕切分。
3. 热词通过本地 AI 提示词传给云端校对模型，由模型结合上下文判断错误变体。
4. 标点只参与切分，不一定出现在最终字幕中；最终保留哪些标点由用户多选。

最终流水线固定为：

```text
音频
  → ASR 返回 source segment + word 时间戳
  → 按 source segment 分组
  → 本地公共分段器
  → 可选 AI 校对
  → 最终标点保留处理
  → 字幕编辑器
  → SRT / FCPXML 导出
```

其中：

- ASR 不负责按产品规则生成最终字幕行。
- AI 不负责重新切分字幕。
- 标点处理不能在分段前执行。
- 用户在编辑器里的手工修改不能在导出时再次被自动清理。

## 2. 已确认的产品规则

### 2.1 ASR 与 segment

- 云端 ASR 模型继续使用 `qwen3-asr-flash-filetrans`。
- 必须请求并保留 word 级时间戳。
- ASR 返回的每个 source segment 是硬边界。
- 任何切分、短句合并和超长回退都不能跨 source segment。
- 不使用 ASR 模型的原生热词功能。

### 2.2 单条字幕最大字数

- 使用一个全局公共设置，不再按官方、自定义云端、本地三种方案分别保存。
- 新安装默认值为 32。
- 现有用户第一次升级到本次新规则时，无论旧版本保存的是多少，都强制重置为 32。
- 这次强制重置只能执行一次。
- 用户在新版本中修改后，必须始终以用户当前保存的值为准，后续启动不能再次重置。
- 合理范围继续限制在 10～50。
- 这里计算的是“有效字数”，不是 Swift `String.count`。
- 标点、空格和指定语气词不计入有效字数。
- 分段算法不得硬编码 32，必须始终读取 `configuration.maxCharacters`。

### 2.3 最小字幕长度

- 默认最小有效字数为 3。
- 小于 3 的片段优先向后合并。
- 当前 source segment 已结束时，只能在当前 source segment 内向前合并或保留。
- 绝不能为了补足最小字数跨 source segment 合并。

### 2.4 标点切分优先级

一级边界在正常情况下直接切分：

```text
。 ！ ？ ! ? ； ; ， ,
```

英文句点 `.` 只有在明确作为句末标点时才作为一级边界；数字、小数、版本号和英文缩写内部的句点不能直接切分。

二级边界平时不主动切分，只在一级片段超过最大有效字数时使用：

```text
、 ： :
```

超长片段处理顺序：

1. 在最大有效字数之前向前寻找最近的二级标点。
2. 没有二级标点时，寻找最近的中文自然词边界或英文短语边界。
3. 如果单个不可拆词或英文专名本身超过上限，允许该字幕小幅超过上限，不从专名中间切断。

### 2.5 语气词计数

首版不计入有效字数的语气词：

```text
嗯 呃 额 哦 噢 哎 唉 呢 啊 呀 吧 嘛
```

“好”只有在单独成词并带有停顿或标点时，才按语气词处理，避免影响“好用”“好吃”等正常词语。

语气词只是不计数，不从字幕文本中删除。

### 2.6 中文和英文词边界

- 使用 Apple NaturalLanguage 的词边界作为中文自然词边界基础。
- 相邻英文单词如果属于同一连续短语，应作为一个不可拆 atom。
- `Final Cut Pro`、`GitHub`、`subForge` 等名称不能从单词内部切开。
- NaturalLanguage 结果只是切分候选，不替代 ASR 时间戳。
- 最终字幕开始和结束时间仍取自首尾 word 的真实时间。

## 3. 公共设置数据模型

### 3.1 统一最大字数

继续复用 `AppSettings.maxSubtitleLength` 作为新的公共持久化字段，避免再增加一套同义字段。

建议语义调整：

```swift
var maxSubtitleLength: Int? = 32
```

现有字段：

```swift
officialMaxSubtitleLength
customMaxSubtitleLength
localMaxSubtitleLength
```

改为旧版本兼容字段，不再参与迁移取值、运行时读取和设置界面。升级到新规则时，不管这些字段原来保存了什么，新的公共值都统一设为 32。

统一提供：

```swift
var effectiveMaxSubtitleLength: Int
mutating func setMaxSubtitleLength(_ value: Int)
```

移除运行时对 `SubtitleLengthProfile` 的依赖。

### 3.2 标点保留选项

原来的单一“标点消除”开关改为“保留标点”多选。

建议新增类型：

```swift
enum SubtitlePunctuationGroup: String, CaseIterable, Codable, Hashable, Identifiable {
    case period
    case comma
    case questionMark
    case exclamationMark
    case ellipsis
    case semicolon
    case colon
    case enumerationComma
    case quotationMarks
    case brackets
    case dash
    case bookTitleMarks
}
```

每组选项对应：

| 选项 | 字符 |
|---|---|
| 句号 | `。．.` |
| 逗号 | `，,` |
| 问号 | `？?` |
| 感叹号 | `！!` |
| 省略号 | `……`、`…`、`...` |
| 分号 | `；;` |
| 冒号 | `：:` |
| 顿号 | `、` |
| 引号 | `“”‘’「」『』"'` |
| 括号 | `（）()【】[]` |
| 破折号/连接号 | `—–-` |
| 书名号 | `《》〈〉` |

设置字段：

```swift
var retainedSubtitlePunctuation: Set<SubtitlePunctuationGroup>
```

新安装和旧设置缺少该字段时，默认使用“字幕推荐”，保留问号、感叹号和省略号。界面提供显眼的预设按钮，用户可以快速选择：

- 全部不保留
- 字幕推荐：问号、感叹号、省略号（默认）
- 保留结构标点：在字幕推荐基础上增加冒号、顿号
- 保留全部

### 3.3 逐视频热词与固定热词

用户界面统一使用“热词”，不使用“术语表”“术语提示”等需要解释的名称。

逐视频热词保存是否启用转写前弹窗：

```swift
enum HotwordPromptPreference: String, Codable {
    case undecided
    case enabled
    case disabled
}
```

含义：

- `undecided`：用户还没有选择，第一次视频转写时询问。
- `enabled`：每次转写前显示热词输入框。
- `disabled`：不显示热词输入框，直接开始转写。

第一次视频转写时显示：

```text
启用热词？

启用后，每次转写前都可以填写视频中经常出现的人名、
品牌名、产品名或专业术语，由 AI 校对识别错误。

[暂不启用]  [启用]
```

交互：

- 点击“启用”：保存 `enabled`，并立即显示当前视频的热词输入框。
- 点击“暂不启用”：保存 `disabled`，当前任务不填写热词并继续转写。
- 用户以后可以在通用设置中随时打开或关闭。

每次热词输入框：

```text
填写热词

subForge
Final cut pro
GitHub

填写视频中经常出现的专有名词，可由 AI 校对。
每行一个，只需填写正确写法。

[取消]  [开始生成字幕]
```

本次填写的热词只属于当前任务：

```swift
struct TranscriptionRunOptions {
    var maxSubtitleLength: Int
    var retainedPunctuation: Set<SubtitlePunctuationGroup>
    var proofreadingPrompt: String
    var hotwords: [String]
}
```

规则：

- 不把本次热词写入全局设置。
- 不自动带到下一个视频。
- 支持换行、中英文逗号分隔。
- 清理首尾空格和空项。
- 完全相同的热词去重。
- 保留用户填写的大小写。
- 用户只填写正确写法，不填写错误变体。
- 任务开始后使用不可变快照，后续设置变化不影响正在运行的任务。

通用设置同时提供独立的“固定热词”开关和输入框：

- 标题显示“固定热词 — 视频中常用的专有名词、生僻词”，说明部分使用较小字号。
- 固定热词会持久保存，关闭开关时只停用，不删除已经填写的内容。
- 开启后，每次转写都把固定热词加入当前任务。
- 固定热词与逐视频热词可以同时开启，并合并后交给 AI 校对。
- 合并顺序为固定热词在前、逐视频热词在后；完全相同的条目去重，保留用户填写的大小写。
- 固定热词也只提供正确写法，不要求用户枚举可能的识别错误。

目录监听：

- 热词开关关闭时，检测到音频后继续自动转写。
- 热词开关开启时，检测到音频后进入“等待填写热词”状态，用户确认后才开始上传和转写。
- 不能在后台静默跳过已开启的热词输入。

### 3.4 AI 校对提示词

继续复用：

```swift
var proofreadingPrompt: String
```

它是全局公共设置，不属于某一个 ASR 方案。

AI 校对提示词用于填写长期通用的校对要求；固定热词和逐视频热词由客户端在任务开始时编入实际校对提示词。

应用固定系统约束和用户提示词必须分开：

- 固定系统约束由应用维护，用户不可删除。
- 用户提示词作为附加规则传给模型。
- 用户提示词不能覆盖“保持行数、不得改时间戳、不得合并拆分”等固定约束。

### 3.5 设置迁移

这次迁移不是“沿用旧值”，而是一次性启用新的统一默认值。

建议增加独立规则版本：

```swift
var subtitleRulesRevision: Int?
```

应用定义当前版本：

```swift
static let currentSubtitleRulesRevision = 1
```

加载设置时：

1. 如果 `subtitleRulesRevision` 小于当前版本，说明用户第一次进入新规则。
2. 无论旧的公共值、官方值、自定义值或本地值是什么，都设置 `maxSubtitleLength = 32`。
3. 写入当前 `subtitleRulesRevision`。
4. 立即持久化迁移结果，保证下次启动不会再次执行。
5. 用户之后通过设置页修改最大字数时，只保存新值，不改变规则版本。
6. 后续每次启动直接读取用户保存的 `maxSubtitleLength`。

例如：

```text
旧版本保存 24 → 第一次升级后变成 32
旧版本保存 40 → 第一次升级后也变成 32
用户在新版本改成 24 → 后续始终使用 24
用户在新版本改成 40 → 后续始终使用 40
```

不能只在 `normalize` 中每次看到旧字段就重置，否则会覆盖用户在新版本中的修改。

新增标点集合时要兼容旧 JSON：

- 旧设置没有该字段时，按“字幕推荐”处理。
- 不要因为新增非可选 Codable 字段导致整份设置解码失败。
- 可以先使用可选持久化字段 + 计算属性，或为 `AppSettings` 增加显式解码迁移。

新增逐视频热词状态时：

- 旧设置没有该字段时按 `undecided` 处理。
- 这样现有用户第一次使用新版本转写视频时也会看到“启用热词？”。
- 用户在通用设置中主动切换开关后，直接保存为 `enabled` 或 `disabled`，不再显示首次询问。
- 逐视频热词不持久化具体内容。

新增固定热词字段时：

- 旧设置没有字段时默认关闭、内容为空。
- 用户关闭固定热词时保留文本，重新开启后可继续使用。

## 4. 设置界面调整

### 4.1 通用设置新增“字幕处理”

在 `GeneralSettingsPane` 增加独立区块：

```text
字幕处理
├─ 单条字幕最大字数       32 字
├─ 保留标点              多选
├─ 热词                  逐视频弹窗开关
├─ 固定热词              开关 + 多行文本
└─ AI 校对提示词         多行文本
```

“单条字幕最大字数”：

- 使用现有 SwiftUI Slider。
- 范围 10～50，步进 2。
- 新版本第一次运行显示 32，用户修改后显示并使用用户值。
- 右侧显示当前实际值。
- 设置行不再显示解释段落。

“保留标点”：

- 使用系统 Toggle、Grid 或项目现有设置行组件。
- 每组选项显示名称和代表字符。
- 引号、括号作为成组选项，不能只选择左半边。
- 提供“不保留标点 / 字幕推荐 / 保留结构 / 保留全部”四个高辨识度预设按钮。
- 当前预设使用强调色背景、描边和选中标记，默认选中“字幕推荐”。

“热词”：

- 使用简单开关。
- 标题显示“热词 — 视频中的专有名词、生僻词”，说明部分使用较小字号。
- 用户第一次转写尚未选择时，仍显示首次询问弹窗。
- 设置中打开对应 `enabled`，关闭对应 `disabled`。
- 设置页不展示内部的 `undecided` 状态名称。

“固定热词”：

- 开关和输入框位于通用设置。
- 标题显示“固定热词 — 视频中常用的专有名词、生僻词”，说明部分使用较小字号。
- 开启时每次任务自动加入，关闭时不加入，保存的文本不清空。
- 与逐视频热词独立控制，并可在同一次任务中合并。

“AI 校对提示词”：

- 使用多行 TextEditor。
- 不再显示解释段落。
- 设置变更后重置 AI 校对验证状态。

### 4.2 从各方案页面删除重复项

需要删除：

- `TranscriptionSettingsPane` 中的“单条字幕最大字数”。
- `SmartServiceSettingsPane` 中重复展示或编辑最大字数的内容。
- `ProofreadingSettingsPane` 中的“提示词”编辑器。

继续保留：

- 自定义 ASR 的 URL、Key、模型配置。
- 自定义 AI 校对的服务预设、URL、Key、模型配置和启用开关。
- 各服务自己的连接验证。

### 4.3 设置页显示原则

- 公共字幕规则只在通用设置出现一次。
- 服务设置只负责服务连接和模型选择。
- 本地、云端和官方方案不能各自再维护一套切分规则。

## 5. 公共分段器修改

### 5.1 严格保留 source segment

不建议仅把所有 word 合并后再依靠时间间隔猜 source segment。

建议增加明确入口：

```swift
static func segmentSources(
    _ sources: [SubtitleSegment],
    configuration: SubtitleSegmentationConfiguration
) -> [SubtitleSegment]
```

实现方式：

1. 遍历每个 ASR source segment。
2. 只把当前 source 的 `words` 交给单段分段函数。
3. 当前 source 内完成一级切分、超长回退和短句合并。
4. 当前 source 完成后直接追加结果。
5. 永远不把上一个 source 的 pending 短句带到下一个 source。

这样不需要依赖时间间隔推断，也不必强行给 `SubtitleWord` 增加 segment ID。

对于没有 word 时间戳的引擎：

- 仍以 provider 返回的粗 segment 作为 source 边界。
- 在每个 source 内估算词元。
- 估算词元也不能跨 source。

### 5.2 有效字数工具

建议单独增加纯函数工具，避免继续扩大现有 Segmenter 文件：

```swift
enum SubtitleEffectiveLength {
    static func count(text: String) -> Int
    static func count(words: [SubtitleWord]) -> Int
    static func isFiller(_ text: String, punctuation: String?) -> Bool
}
```

规则：

- Unicode punctuation 不计数。
- 空格和换行不计数。
- 已确认的语气词不计数。
- 中文字符、英文字母和数字正常计数。
- 英文短语是否可拆与计数是两个独立问题。

### 5.3 一级标点处理

当前实现把逗号放在软边界，并要求达到长度或时长才切。需要调整为：

- 一级标点出现时先形成候选片段。
- 候选片段有效字数不足 3 时，暂存并向后合并。
- 候选片段达到最小字数后立即输出。
- 不再让 `preferredDuration` 覆盖一级标点规则。

### 5.4 超长回退

一级片段有效字数超过最大值时：

1. 找到即将超过用户当前最大字数的 atom。
2. 从该位置向前寻找最近的二级标点。
3. 找到顿号或冒号时，在其后切分。
4. 找不到时，在最近的 NaturalLanguage 词边界切分。
5. 下一片段继续执行相同逻辑。

时长和停顿可以作为多个候选边界分数相同时的辅助信息，但不能越过 source segment，也不能优先于明确标点。

### 5.5 短片段合并

在每个 source segment 内单独执行：

```text
一级片段
  → 有效字数 >= 3：输出
  → 有效字数 < 3：暂存
      → 后面还有片段：与下一片段合并
      → source 已结束：与前一片段合并
      → 当前 source 只有这一片：保留
```

例如：

```text
一般来说呢，｜呃，｜添加字幕是整个视频的收尾阶段。
```

结果：

```text
一般来说呢，
呃，添加字幕是整个视频的收尾阶段。
```

### 5.6 时间戳

- 每条字幕开始时间取第一个 word 的开始时间。
- 结束时间取最后一个 word 的结束时间。
- 合并片段时同步合并 words。
- 相邻字幕不能重叠。
- 不使用字符数重新均匀估算已有真实 word 时间戳。

## 6. AI 校对与热词

### 6.1 提示词组成

每批 AI 请求由四部分组成：

1. 应用固定系统规则。
2. 通用设置中的 AI 校对提示词。
3. 当前启用的固定热词，以及本次任务填写的逐视频热词。
4. 带稳定序号的字幕文本。

应用根据本次任务的 `hotwords` 自动生成：

```text
本次视频中经常出现以下专有名词：

- subForge
- Final cut pro
- GitHub

请结合上下文判断识别错误，并统一使用上面的正确写法。
用户不会提供错误变体，请自行判断。
```

固定系统规则至少包括：

```text
只修正错别字、漏字、明显 ASR 错误和专有名词，不润色、不改写原意。
请根据上下文判断标准术语的同音、近音、拆分、连写、大小写、附加字母或数字及组合形式。
如果明确指向标准术语，统一为标准写法；用户不需要提供错误变体。
输出行数、序号和顺序必须与输入完全一致。
不得合并、拆分、删除字幕行，不得输出空行。
只输出序号和修正后的文本，不得解释。
```

`Sub4Sub`、`Sub4word` 在当前口播上下文中明确指向产品 `subForge`，因此统一修正是正确行为。

### 6.2 返回结果验证

当前解析器允许无序号行按顺序回填，约束不够严格。建议修改为：

- 只接受明确带有输入序号的行。
- 返回序号数量必须与输入完全一致。
- 不允许重复序号、缺失序号、越界序号或空文本。
- 任何一项失败时，整批结果无效。
- 可以用更严格提示重试一次。
- 重试仍失败时保留该批原文，并记录校对失败日志。

不得把部分成功、部分缺失的结果静默写回字幕。

### 6.3 时间戳保护

AI 只返回文本。客户端始终：

1. 从原 `SubtitleSegment` 复制 id、start、end 和 words。
2. 只替换 `text`。
3. 不根据 AI 输出重新计算时间。

官方服务如果先在 source segment 层校对，也必须保持 source segment 数量和 word 时间数据不变，客户端随后仍按本地公共规则切分。

## 7. 官方智能字幕接口

### 7.1 已解决的接口缺口

当前官方任务提交体只有：

```json
{
  "ossUrl": "oss://..."
}
```

原协议没有传递本地 `proofreadingPrompt`，官方智能字幕无法使用用户配置的 AI 校对提示词和热词；现已增加可选字段并完成客户端与服务端透传。

### 7.2 客户端协议调整

建议提交体改为：

```json
{
  "ossUrl": "oss://...",
  "proofreadingPrompt": "AI 校对提示词、已启用固定热词与本次热词组合后的完整提示词"
}
```

只传组合后的 AI 校对提示词：

- 最大字数由客户端公共分段器处理，不需要发给服务端。
- 标点保留由客户端最终文本处理，不需要发给服务端。
- 已启用的固定热词和当前任务热词均由客户端编入 `proofreadingPrompt`。
- 服务端只负责 ASR 和 AI 文本校对。

### 7.3 服务端要求

官方 Model API 需要同步修改：

- 接受可选 `proofreadingPrompt`。
- 限制提示词长度，例如 4000 字符。
- 将应用固定系统规则放在更高优先级消息中。
- 用户提示词只能作为附加校对规则。
- 不在普通日志中记录完整用户提示词，只记录长度、请求 ID 和是否存在。
- 返回 `proofreadingApplied=true` 的语义保持不变。
- 返回原始 word 时间戳和校对后的 source segment 文本。

客户端修改不能单独完成官方链路验收；必须等待官方 Model API 同步支持该字段。

## 8. 最终标点保留处理

### 8.1 执行时间

统一在最后一个自动文本阶段结束后执行：

- 开启 AI 校对：AI 校对完成后执行。
- 未开启 AI 校对：ASR 分段完成后执行。
- 官方智能字幕：官方校对结果完成本地分段后执行。

处理完成后再进入字幕编辑器。

不能在以下阶段执行：

- ASR 解析时。
- 公共分段前。
- AI 校对前。
- 每次导出时。

不在导出时再次执行，是为了避免用户在编辑器中手工补回的标点被意外删除。

### 8.2 处理算法

建议增加：

```swift
static func applyingPunctuationPolicy(
    _ text: String,
    retained: Set<SubtitlePunctuationGroup>
) -> String
```

规则：

1. 先识别多字符标点，例如 `……` 和 `...`。
2. 属于已选分组的标点原样保留。
3. 未选标点替换为普通空格。
4. 连续多个替换空格折叠为一个空格。
5. 去除行首和行尾多余空格。
6. 不删除文字、数字和英文字母。

需要单独测试：

- 保留省略号但不保留句号时，`...` 仍然完整保留。
- 引号和括号按组保留。
- 中文标点和对应英文标点使用同一个选项。
- 标点移除后不会把前后两个词直接粘连。

### 8.3 标点与有效字数

无论用户最终选择保留还是删除，所有标点在分段阶段都不计入有效字数。

“保留标点”只决定最终显示，不改变切分结果。

## 9. 预计修改文件

### 设置与数据

- `Sources/Models/AppSettings.swift`
- `Sources/Models/AppSettingsValidation.swift`
- `Sources/Services/SettingsStore.swift`
- 新增 `Sources/Models/SubtitlePunctuationGroup.swift`

### 设置界面

- `Sources/Views/Settings/GeneralSettingsPane.swift`
- `Sources/Views/Settings/TranscriptionSettingsPane.swift`
- `Sources/Views/Settings/SmartServiceSettingsPane.swift`
- `Sources/Views/Settings/ProofreadingSettingsPane.swift`
- `Sources/Views/Settings/ProofreadingSettingsBindings.swift`
- `Sources/Views/Settings/SubtitleSettingsComponents.swift`
- 新增转写前“启用热词”和“填写热词”弹窗视图

### 公共分段

- `Sources/Services/TimedSubtitleSegmenter.swift`
- `Sources/Services/TimedSubtitleLexical.swift`
- `Sources/Services/TimedSubtitleCorrectedText.swift`
- 新增 `Sources/Services/SubtitleEffectiveLength.swift`

### AI 与后处理

- `Sources/Services/ProofreadingService.swift`
- `Sources/Utilities/SubtitleTextFormatting.swift`
- `Sources/App/AppModelTranscription.swift`

### 官方智能服务

- `Sources/Services/OfficialSmartServiceClient.swift`
- `Sources/Services/OfficialSmartSubtitleProvider.swift`
- `Sources/Services/OfficialSmartServiceRequests.swift`
- 官方 Model API 对应任务提交和校对实现

### 测试

- `Tests/AppSettingsTests.swift`
- `Tests/OfficialSmartServiceTests.swift`
- `Tests/FunASROutputParserTests.swift`
- 新增或扩展 `TimedSubtitleSegmenterTests`
- 新增或扩展 `ProofreadingServiceTests`
- 新增或扩展 `SubtitleTextFormattingTests`

## 10. 测试矩阵

### 10.1 设置

- 新安装默认最大字数为 32。
- 旧版本无论保存 12、24、32 还是 40，第一次升级后都重置为 32。
- 一次性迁移标记会立即持久化，不会在下次启动重复重置。
- 用户在新版本改成 24 后，重新启动仍然是 24。
- 用户在新版本改成 40 后，重新启动仍然是 40。
- 三套 profile 值不再影响运行时。
- 旧设置没有标点字段时能正常解码。
- 旧设置没有标点字段时默认使用“字幕推荐”。
- 标点预设能得到预期集合。
- 首次转写且热词状态未选择时显示“启用热词？”。
- 点击“启用”后保存开启状态并立即显示热词输入框。
- 点击“暂不启用”后保存关闭状态，后续不再自动询问。
- 通用设置中的热词开关能够重新打开或关闭该功能。
- 固定热词能够独立启用；关闭后内容仍然保存。
- 固定热词与逐视频热词同时启用时按固定在前的顺序合并并去重。
- 修改 AI 校对提示词后验证状态重置。

### 10.2 分段

- 不跨 source segment。
- 逗号、句号、问号优先切分。
- 顿号、冒号在未超长时不切。
- 超过用户当前最大字数时在最近顿号或冒号回退。
- 用户设置为 24、32、40 时，分段器分别使用对应值。
- 标点不计数。
- 语气词不计数但保留文本。
- 小于 3 个有效字时向后合并。
- source 结束时不向下一 source 合并。
- 中文词组不从中间切。
- `Final Cut Pro`、`subForge` 等英文名称不从中间切。
- 单个不可拆专名超过用户当前最大字数时允许小幅超长。
- 字幕时间不重叠。

### 10.3 AI 校对

- 热词支持换行、中英文逗号输入，能够清理空项并去重。
- 本次热词不保存到下一次视频。
- 热词开关开启时，每次手动转写前都显示输入框。
- 热词开关关闭时直接开始转写。
- 固定热词关闭时不进入任务，重新开启后恢复使用已保存内容。
- 固定热词和逐视频热词相同的条目只进入校对提示词一次。
- 只给 `subForge`，能够结合上下文修正 `Sub4`、`Sub Forge`、`Sub4Sub`、`Sub4word`。
- 只给 `Final cut pro`，能够修正 `Final Cat Pro` 和大小写。
- 普通错字能修正。
- 行数和序号保持不变。
- 缺行、重复序号、空行时整批回退。
- AI 失败时原字幕和时间戳不丢失。

### 10.4 标点保留

- 空集合时所有标点变为空格。
- 只保留问号时，中英文问号保留，其他标点替换为空格。
- 保留冒号和顿号时，两者保留。
- 保留省略号时 `……`、`…`、`...` 均保留。
- 引号和括号成对保留。
- 替换后连续空格折叠。
- 手工编辑后的标点不会在导出时被再次清理。

### 10.5 官方服务

- submit 请求包含 AI 校对提示词、已启用固定热词和本次热词组合后的提示词。
- 未填写提示词时字段为空或省略，服务仍可工作。
- 服务端拒绝超长提示词时显示可理解错误。
- 返回必须包含 `proofreadingApplied=true`。
- word 时间戳保持不变。

### 10.6 真实音频回归

使用：

- `/Users/jago/Documents/vedio/06_subforge/Subforge.mp3`
- `/Users/jago/Documents/vedio/06_subforge/Sub forge演示.mp3`

正式回归数据使用固定的 ASR JSON 或 SRT fixture，不再从包含说明和重复示例的 Markdown 文档提取统计。

## 11. 实施顺序

### 阶段 A：文档和测试基线

1. 更新 302 字幕流水线和 303 AI 校对功能文档。
2. 固化 ASR fixture。
3. 先补设置迁移、分段和标点策略测试。

### 阶段 B：公共设置

1. 统一最大字数为一个字段。
2. 新增标点保留数据模型。
3. 新增热词首次选择状态和通用设置开关。
4. 移动并重命名 AI 校对提示词。
5. 完成旧设置迁移。
6. 调整设置界面并删除重复控件。

### 阶段 C：公共分段器

1. 增加按 source segment 分段入口。
2. 增加有效字数工具。
3. 调整一级和二级标点规则。
4. 增加短片段向后合并。
5. 完善中文和英文词边界。

### 阶段 D：AI 校对

1. 增加首次转写热词询问和每次热词输入框。
2. 将本次热词保存到任务快照。
3. 重组固定提示词、通用提示词和本次热词。
4. 严格校验返回序号和行数。
5. 确保只替换 text。
6. 添加热词回归测试。

### 阶段 E：官方服务

1. 客户端 submit 请求增加 `proofreadingPrompt`。
2. 官方 Model API 接收并传给校对模型。
3. 验证 source segment、word 时间戳和 `proofreadingApplied`。

### 阶段 F：最终标点处理

1. 实现标点分组和替换算法。
2. 在自动流水线最后执行一次。
3. 接入官方、自定义云端和本地三种路径。
4. 确保导出阶段不重复执行。

### 阶段 G：完整验证

1. 运行 Swift 单元测试。
2. 运行真实音频测试。
3. 对比切分前后和 AI 校对前后。
4. 构建并运行 macOS 应用。
5. 检查设置迁移和三个转写入口。

## 12. 验收标准

- 新安装默认最大字数为 32。
- 旧版本第一次升级时最大字数无条件重置为 32，且只重置一次。
- 用户修改最大字数后，所有后续转写和应用重启都使用用户当前值。
- 代码中不存在把 32 当成固定切分上限的业务判断。
- 所有转写方案使用同一个最大字数、标点保留、热词开关、固定热词和 AI 校对提示词。
- 设置页不再重复显示公共设置。
- 第一次转写会用“暂不启用 / 启用”询问是否开启热词。
- 热词开启后，每次转写前都可以填写当前视频的热词。
- 热词只对当前视频生效，不会自动带入下一次视频。
- 通用设置能够随时打开或关闭热词。
- 固定热词能够独立开启或关闭；关闭不清空内容，开启后每次转写自动加入。
- 固定热词和逐视频热词同时启用时能够稳定合并并去重。
- 任何字幕都不跨 ASR source segment。
- 逗号等一级标点优先切分。
- 顿号和冒号只在超长时兜底。
- 标点和语气词不计入有效字数。
- 小于 3 个有效字的片段按规则合并。
- 中文词组和英文短语不被无意义拆开。
- AI 能只根据标准热词判断常见错误变体和组合形式。
- AI 不改变字幕数量和时间戳。
- 用户能够逐组选取最终保留的标点。
- 新安装和缺失标点字段的旧设置默认使用“字幕推荐”。
- 未保留标点被替换为空格，不会把两侧文字粘连。
- 官方智能服务能够收到本地 AI 提示词。
- AI、网络或格式验证失败时保留原始字幕。

## 13. 明确不做

- 不用大语言模型决定字幕切分。
- 不跨 ASR source segment 合并字幕。
- 不依赖 ASR 原生热词表。
- 不要求用户填写热词错误变体。
- 不做本地热词硬替换。
- 不在切分前删除标点。
- 不在每次导出时重新执行自动标点清理。
