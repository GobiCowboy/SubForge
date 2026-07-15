# 308 本地 FunASR（SenseVoice）转写

## 1. 功能目标

在 SubForge 中提供与本地 Whisper 同构的 **SenseVoice GGUF 本地转写引擎**，覆盖中文 / 日语 / 韩语 / 英语，且不引入 Python 运行时。

状态：**已实现（待本机 CLI + 模型验收）**

## 2. 产品边界

包含：

- 转写引擎选项：`本地 FunASR`
- 内嵌 / 外置 `llama-funasr-sensevoice` 运行时检测
- SenseVoice Small q8 + FSMN-VAD GGUF 下载与状态展示
- 识别结果进入公共分段器 `TimedSubtitleSegmenter`
- 设置页验证链路

不包含（一期）：

- Fun-ASR-Nano / Paraformer 多模型切换
- Python FunASR / 远程 funasr-server
- 字级时间戳（上游 CLI roadmap 中，尚未提供）
- 日韩专用切句规则（后续可扩展 `SubtitleSegmentationConfiguration.language`）

## 3. CLI 契约（已对照上游源码锁定）

上游：`modelscope/FunASR` → `runtime/llama.cpp/sensevoice/funasr-sensevoice/funasr-sensevoice.cpp`  
Release：`runtime-llamacpp-v0.1.6`（macOS arm64 包名 `funasr-llamacpp-macos-arm64.tar.gz`）

```text
usage: llama-funasr-sensevoice -m sensevoice.gguf (-a audio.wav | -f fbank.bin)
       [--vad fsmn-vad.gguf [--vad-maxseg ms]] [--ids] [--keep-tags]
```

| 参数 | 用途 |
|------|------|
| `-m` | SenseVoice GGUF |
| `-a` | 任意常见音频（内部 miniaudio → 16k mono） |
| `--vad` | FSMN-VAD GGUF，长音频分段后再识别（**推荐始终开启**） |
| `--vad-maxseg` | VAD 最大段长（ms），默认 30000 |
| `--keep-tags` | 保留 `<|zh|>` 等标签（SubForge **不**使用） |
| `--ids` | 输出 CTC id（SubForge **不**使用） |

### 3.1 语言

CLI **没有** `--language` 参数。语言由模型 query token 默认 `auto` 决定，支持中 / 英 / 粤 / 日 / 韩自动识别。

UI 中的语言选项对 FunASR 引擎仅作展示与后续分段预留；不会映射到 CLI 参数。

### 3.2 输出

- stdout：整段转写文本（默认已 strip `<|...|>` meta tags）
- 使用 `--vad` 时：各 VAD 段文本直接拼接，**不输出时间戳、不换行分隔**
- stderr：进度与诊断（如 `[sensevoice] N vad segments`）

因此一期时间策略：

1. 取音频时长 `duration`
2. 将清洗后的全文作为一条粗 segment：`[0, duration]`
3. 调用 `TimedSubtitleSegmenter.segmentEstimated`

## 4. 模型与路径

| 资源 | 文件名 | 来源 |
|------|--------|------|
| ASR | `sensevoice-small-q8.gguf` | `FunAudioLLM/SenseVoiceSmall-GGUF` |
| VAD | `fsmn-vad.gguf` | `FunAudioLLM/fsmn-vad-GGUF` |

本地目录：`~/Library/Application Support/SubForge/models/funasr/`

CLI 候选路径：

1. `SubForge.app/Contents/Frameworks/llama-funasr-sensevoice`
2. `Application Support/SubForge/bin/llama-funasr-sensevoice`
3. 仓库 `vendor/funasr/llama-funasr-sensevoice`（开发）

下载镜像：`hf-mirror.com` → `huggingface.co`。

## 5. 架构衔接

```
音频
  → FunASRSenseVoiceProvider（听写 + 文本清洗）
  → 粗 SubtitleSegment（无可靠词时间）
  → TimedSubtitleSegmenter.segmentEstimated
  → 可编辑 SubtitleSegment
```

禁止在 Provider 内复制切句逻辑。

## 6. 失败态

| 情况 | 用户提示 |
|------|----------|
| CLI 不存在 | 提示安装 / 重新打包内置运行时 |
| 模型或 VAD 未下载 | 引导设置页下载 |
| CLI 非 0 退出 | 展示 stderr 摘要 |
| 空文本 | 没有识别出可用字幕 |

## 7. 验收

- 设置可选「本地 FunASR」
- 下载模型后可用内置测试音频验证中文
- 日 / 韩样例音频可出对应文字体系（auto）
- 最大字数设置仍作用于公共分段器
- 不破坏 Apple / Whisper / 云端三引擎

## 8. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-07-15 | 锁定 SenseVoice GGUF 本地集成方案与 CLI 契约 |
