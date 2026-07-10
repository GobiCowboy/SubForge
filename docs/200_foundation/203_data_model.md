# 203 数据模型文档

## 1. 说明

这里记录的是产品级数据对象，用于约束后续重做时的领域模型，不直接等同于当前代码结构。

## 2. 核心实体

### 2.1 SubtitleProject

表示一次字幕任务。

关键字段：

- `id`
- `sourceAsset`
- `segments`
- `status`
- `settingsSnapshot`
- `createdAt`
- `updatedAt`

生命周期：

- 导入素材后创建
- 转写后产生初始字幕
- 编辑过程中持续更新
- 导出后保留当前状态

### 2.2 SourceAsset

表示用户导入的原始素材。

关键字段：

- `path`
- `type`：audio / srt
- `name`
- `duration`
- `origin`

### 2.3 SubtitleWord（转写中间结果）

表示带时间的最小听写单元，是「转写 → 公共分段」之间的契约。

关键字段：

- `start`
- `end`
- `text`

来源示例：

- Apple Speech 的 segment（先做异常 duration 收敛，再当作词元）
- Whisper JSON 的 token / DTW 词边界
- DashScope 等云端返回的 `words`
- 无可靠词时间时，由粗段落文本按字/词权重估算出来的伪词元

关键规则：

- `start < end`
- 空文本词元不参与分段
- 引擎只负责产出词元；**不在此层做产品级切句**

### 2.4 SubtitleSegment

表示一条可编辑字幕（公共分段器输出，也是编辑 / 导出单元）。

关键字段：

- `id`
- `start`
- `end`
- `text`
- `words`：可选，生成该条时用到的词元；旧项目或估算路径允许缺失
- `order`
- `isEmpty`

关键规则：

- `start < end`
- 空文本字幕允许存在，但不应成为最终输出重点
- 顺序可调整，但必须保持可导出
- 相邻字幕不应时间重叠（由公共分段器保证）

### 2.5 AppSettings

表示应用级配置。

关键字段：

- `transcriptionEngine`
- `language`
- `proofreadingEnabled`
- `proofreadingEngine`
- `subtitleStyle`
- `maxSubtitleLength`：单条字幕最大字数，**统一注入公共分段器**，不按引擎分叉
- `exportSettings`
- `watchSettings`

默认初始化：

- `interfaceLanguage`: 简体中文
- `showMenuBarIcon`: 开启
- `transcriptionEngine`: Apple 语音
- `language`: 中文
- `maxSubtitleLength`: 24
- `proofreadingEnabled`: 关闭
- `subtitleStyle`: 横屏、内白外黑
- `exportSettings.format`: SRT + FCPXML
- `exportSettings.exportToFinalCutPro`: 关闭
- `exportSettings.overwriteExisting`: 关闭
- `exportSettings.saveLocation`: 与源文件同目录
- `watchSettings.autoStart`: 关闭

### 2.6 ExportSettings

表示导出阶段所需参数。

关键字段：

- `fps`
- `width`
- `height`
- `saveLocation`
- `customOutputPath`
- `targetFormat`

### 2.7 WatchTask

表示目录监听中的单次处理任务。

关键字段：

- `watchDirectory`
- `detectedFile`
- `mode`：auto / manual-proofread
- `status`
- `resultFiles`

## 3. 派生对象

- `RecentProject`
- `PipelineProgress`
- `ExportArtifact`
- `LogEntry`
- `SubtitleSegmentationConfiguration`：分段参数（最大字数、优选/最大时长等），由设置派生后注入公共分段器

## 4. 数据边界

- 不要求引入数据库
- 默认以本地内存状态和本地配置持久化为主
- 只要数据模型稳定，后续存储实现可替换
- 转写中间结果（词元）与可编辑字幕片段分层；不要把引擎原始 JSON 直接当编辑模型
