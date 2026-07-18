# SubForge

**从 Git Release 下载：** https://github.com/GobiCowboy/SubForge/releases

SubForge 是一个面向 Final Cut Pro（FCP）的字幕工作流应用：可监听 FCP 上导出的音频，也能将生成的字幕 XML 文件自动传回 FCP 中（需要打开设置的相关配置）。重点是把 **监听 → 转写 → 编辑 → 导出** 这条路径做短、做稳、做清楚。

## 使用流程

打开应用后先进入「设置」页面（本应用的主要操作都在设置内完成）。

1. **目录监听**：在「设置」中进入「目录监听」页面，选择你制作视频的根目录。应用会自动监听 FCP 上导出的音频并自动进行转写。
2. **配置传回 FCP**：在「设置」中打开相关配置，将生成的字幕 XML 文件自动传回 FCP 中。
3. **配置校对与转写**：按需配置校对（AI 文本修正）与转写（模型、语言等）参数，并滑到页面底部进行验证，确认配置生效。
4. **导出并回灌样式**：导出字幕到 FCP；在 Final Cut Pro 中确认后，将对应参数配置回「设置 → 基本样式」，使后续导出保持一致。

## 功能

- **素材导入**：打开文件、拖放文件、最近项目。
- **本地字幕生成**：基于本地 Whisper（whisper.cpp）或本地 FunASR / SenseVoice 转写，音频不出本机；支持中日韩英（SenseVoice auto）。
- **AI 校对**：对转写结果做可选的文本修正（增强项，不阻塞主流程）。
- **字幕编辑工作台**：逐条编辑文本、入点、出点，支持插入与合并。
- **导出与交付**：输出 SRT、FCPXML，并可将字幕 XML 自动传回 FCP（需在设置中开启相关配置）。
- **目录监听**：监听 FCP 上导出的音频，自动识别并转写。
- **菜单栏常驻**：支持菜单栏常驻模式。

## 下载与安装

前往 [Git Release](https://github.com/GobiCowboy/SubForge/releases) 下载最新 `SubForge-x.y.z.zip`，解压后将 `SubForge.app` 拖入 `应用程序` 文件夹即可。

发布包已使用 **Developer ID Application** 证书签名并经 Apple **公证（Notarization）**，首次打开不会被 Gatekeeper 拦截。

> 注：应用首次使用麦克风 / 语音识别 / 控制 Final Cut Pro（Apple Events）时，macOS 仍会弹出系统权限请求，这是系统隐私保护（TCC），与签名公证无关，按提示允许即可。

## 从源码构建

### 环境要求

- macOS 14.0+
- Swift 5.9+（Xcode 命令行工具）
- [Homebrew](https://brew.sh)
- 依赖：`whisper-cpp`、`ggml`、`libomp`

```bash
brew install whisper-cpp ggml libomp
```

### 本地模型（不打进安装包）

**Whisper** 与 **FunASR** 的权重均不默认打进 `.app`（可显著减小分发包体积）：

- 在应用 **设置 → 转写** 中按需下载
- Whisper：Tiny / Base / Small（约 74～466MB）
- FunASR：SenseVoice q8 + VAD（约 256MB）

开发若需临时把 Whisper base 打进包：

```bash
BUNDLE_WHISPER_BASE=1 ./script/build_and_run.sh
# 或 BASE_MODEL_SOURCE=/path/to/ggml-base.bin ./script/build_and_run.sh
```

### 本地 FunASR 运行时（SenseVoice CLI）

```bash
# 下载 macOS arm64 CLI 到 vendor/funasr/
bash script/download_funasr_runtime.sh
```

打包脚本会嵌入 `llama-funasr-sensevoice` / `llama-funasr-vad`（若存在）。模型仍在设置页下载。详见 `docs/300_features/308_funasr_local_engine.md`。

### 构建（未签名 / 本地调试）

```bash
./script/release_appstore.sh --unsigned
```

产物位于 `dist/appstore/SubForge.app`。

### 打包并公证分发（macOS 站外分发）

```bash
./script/release_developer_id.sh
```

该脚本会：用 `Developer ID Application` 证书 + Hardened Runtime 签名、嵌入第三方依赖与许可声明、压缩上传至 Apple Notary 服务公证、贴票（staple）并校验 `codesign` / `spctl` / `stapler`，最终产物为 `dist/developer-id/SubForge-x.y.z.zip`。

上架用的 App Store 打包流程见 `script/release_appstore.sh`（需对应的 Mac App Store 证书与 provisioning profile）。

## 许可证

[MIT](./LICENSE)
