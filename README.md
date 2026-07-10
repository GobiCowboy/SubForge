# SubForge

**从 Git Release 下载：** https://github.com/GobiCowboy/SubForge/releases

SubForge 是一个面向 macOS 的本地优先字幕工作台，服务于「拿到一段音频后，尽快生成、校对、微调并导出字幕」的场景。重点是把 **导入 → 转写 → 编辑 → 导出** 这条主路径做短、做稳、做清楚。

## 功能

- **素材导入**：打开文件、拖放文件、最近项目。
- **本地字幕生成**：基于本地 Whisper（whisper.cpp）转写，音频不出本机。
- **AI 校对**：对转写结果做可选的文本修正（增强项，不阻塞主流程）。
- **字幕编辑工作台**：逐条编辑文本、入点、出点，支持插入与合并。
- **导出与交付**：输出 SRT、FCPXML，并衔接 Final Cut Pro 工作流。
- **目录监听**：监听 FCP 导出目录并自动处理（偏自动化工作流）。
- **菜单栏常驻**：支持菜单栏常驻模式。

## 下载与安装

前往 [Git Release](https://github.com/GobiCowboy/SubForge/releases) 下载最新 `SubForge-x.y.z.zip`，解压后将 `SubForge.app` 拖入 `应用程序` 文件夹即可。

发布包已使用 **Developer ID Application** 证书签名并经 Apple **公证（Notarization）**，首次打开不会被 Gatekeeper 拦截。

> 注：应用首次使用麦克风 / 语音识别 / 控制 Final Cut Pro（Apple Events）时，macOS 仍会弹出系统权限请求，这是系统隐私保护（TCC），与签名公证无关，按提示允许即可。

## 使用流程

1. **导出到 Final Cut Pro**：打开应用后进入「设置」页面，在「导出」页勾选「导出到 FCP」。之后导出字幕时可直接唤起 Final Cut Pro 并导入，无需手动搬运文件。
2. **目录监听自动转写**：进入「目录监听」页面，选择你制作视频的根目录。应用会自动识别 Final Cut Pro 导出的音频，并自动进行转写。

## 从源码构建

### 环境要求

- macOS 14.0+
- Swift 5.9+（Xcode 命令行工具）
- [Homebrew](https://brew.sh)
- 依赖：`whisper-cpp`、`ggml`、`libomp`

```bash
brew install whisper-cpp ggml libomp
```

### 基础模型

应用需要 Whisper 基础模型（如 `ggml-base.bin`）。把模型放到以下任一位置即可被打包脚本自动发现：

- `Resources/ggml-base.bin`
- `BAK/models/ggml-base.bin`
- `~/Library/Application Support/SubForge/models/ggml-base.bin`

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
