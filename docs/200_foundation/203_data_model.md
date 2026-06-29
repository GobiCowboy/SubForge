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
- `type`：audio / video / srt
- `name`
- `duration`
- `origin`

### 2.3 SubtitleSegment

表示一条字幕。

关键字段：

- `id`
- `start`
- `end`
- `text`
- `order`
- `isEmpty`

关键规则：

- `start < end`
- 空文本字幕允许存在，但不应成为最终输出重点
- 顺序可调整，但必须保持可导出

### 2.4 AppSettings

表示应用级配置。

关键字段：

- `transcriptionEngine`
- `language`
- `proofreadingEnabled`
- `proofreadingEngine`
- `subtitleStyle`
- `maxSubtitleLength`
- `exportSettings`
- `watchSettings`

### 2.5 ExportSettings

表示导出阶段所需参数。

关键字段：

- `fps`
- `width`
- `height`
- `saveLocation`
- `customOutputPath`
- `targetFormat`

### 2.6 WatchTask

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

## 4. 数据边界

- 不要求引入数据库
- 默认以本地内存状态和本地配置持久化为主
- 只要数据模型稳定，后续存储实现可替换
