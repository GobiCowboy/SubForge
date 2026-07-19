# 207 App Store 提交准备

## 1. 当前结论

SubForge 已具备 App Store 打包与上传链路；历史上已有成功上传构建 `1.0 (2026070403)`。

- `script/release_appstore.sh --unsigned`：生成 release app bundle，仅做结构检查，使用 ad-hoc 调试签名。
- `script/release_appstore.sh --signed` / `--package` / `--upload`：都会调用 `sign_app`，使用 Mac App Store 分发证书正式签名。
- 若缺少 app signing identity，上述正式签名模式会主动停止，这是预期保护。
- 注意：`--upload` 必须走正式签名；漏掉该分支时会落到 ad-hoc 签名，App Store Connect 会拒绝上传。

## 2. 构建入口

开发运行继续使用：

```bash
./script/build_and_run.sh --verify
```

App Store 发布准备使用：

```bash
./script/release_appstore.sh --unsigned
./script/release_appstore.sh --signed
./script/release_appstore.sh --package
./script/release_appstore.sh --upload
```

模式说明：

| 模式 | 签名 | 产物 / 行为 |
|------|------|-------------|
| `--unsigned` | ad-hoc（调试） | `dist/appstore/SubForge.app` 结构检查 |
| `--signed` | Mac App Store 分发 | 已签名 `.app` |
| `--package` | Mac App Store 分发 + Installer | 已签名 `.app` + `.pkg` |
| `--upload` | 与 `--package` 相同 | 生成 `.pkg` 后上传 App Store Connect |

可配置环境变量：

```bash
APP_VERSION=1.0
APP_BUILD=1
TEAM_ID=4UNNXY925R
APP_SIGN_IDENTITY="3rd Party Mac Developer Application: ..."
INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: ..."
APP_STORE_USER="apple-id@example.com"
APP_STORE_PASSWORD="app-specific-password"
```

## 3. 签名要求

需要安装或配置：

- Mac App Store app signing identity（脚本自动查找 `Apple Distribution` / `3rd Party Mac Developer Application`）
- Mac App Store installer signing identity（脚本用 `security find-certificate` 查找，不会出现在 `security find-identity -p codesigning`）
- Bundle ID: `com.jago.subforge`
- Team ID: `4UNNXY925R`
- 上传时还需 `APP_STORE_USER` + `APP_STORE_PASSWORD`（app-specific password）

注意区分证书用途：

| 证书类型 | 用途 |
|----------|------|
| `Apple Development` | 本地开发调试 |
| `Developer ID Application` | 站外分发 + 公证（`release_developer_id.sh`） |
| `Apple Distribution` / `3rd Party Mac Developer Application` | Mac App Store `.app` 签名 |
| `3rd Party Mac Developer Installer` | Mac App Store `.pkg` 签名 |

站外 Developer ID 包与 App Store 包的 entitlements 也不同：前者用 `Config/SubForge.developer-id.entitlements`（无 Sandbox），后者用 `Config/SubForge.entitlements`（有 Sandbox），不可混用。

## 4. Entitlements（仅 App Store 渠道）

本文件只描述 **App Store** 包。站外 Developer ID 包见 `205` 与 `Config/SubForge.developer-id.entitlements`（无 Sandbox；嵌套二进制也不用 inherit）。

主 app（`Config/SubForge.entitlements`）使用：

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.automation.apple-events`
- 以及 application-identifier / team-identifier / keychain-access-groups

语音识别只保留 `NSSpeechRecognitionUsageDescription` 权限说明。Apple 远端校验不接受 macOS app bundle 签名中包含 `com.apple.security.personal-information.speech-recognition` entitlement。

嵌入命令行工具（`Config/SubForge.inherit.entitlements`，**仅 App Store 沙盒包**）使用继承 entitlement：

- `com.apple.security.app-sandbox`
- `com.apple.security.inherit`

不要把这套 inherit 签名套到 Developer ID 的 `whisper-cli` 上：站外主程序无 Sandbox，子进程再签 sandbox+inherit 会被系统以信号 5 杀掉。

## 5. 隐私清单

已提供并随 app bundle 打包：

- `Resources/PrivacyInfo.xcprivacy`

当前声明：

- 不追踪用户
- 官方智能字幕开启时收集`Audio Data`和`Other User Content`，并为首装体验与内购处理`User ID`和`Purchase History`；用途仅为App Functionality，不用于追踪
- Required Reason API:
  - UserDefaults
  - File Timestamp

## 6. 第三方二进制

App bundle 会嵌入：

- `whisper-cli`
- `libwhisper`
- `libggml`
- `libggml-base`
- `libomp`

发布脚本会执行：

- 拷贝 `libomp.dylib`
- 重写 Homebrew 绝对依赖路径为 bundle 内路径
- 清除 `libggml` 中写死的 Homebrew backend 扫描路径，避免 App Sandbox 访问 `/opt/homebrew/.../libexec`
- 不打包 Metal backend，Local Whisper 在 App Store 沙盒包中走 CPU 路径
- 检查 `otool -L` 不再包含 `/opt/homebrew` 或 `/usr/local`
- 打包第三方 license 到 `Contents/Resources/ThirdPartyNotices`

## 7. App Review Notes 草稿

SubForge is a macOS utility for turning user-selected audio files into editable subtitles, importing existing SRT files, then exporting SRT and Final Cut Pro XML files. The app can optionally watch a user-selected folder for new audio exported from Final Cut Pro. Folder watching is off by default and only starts after the user selects a folder.

The app defaults to Smart Subtitle, a managed cloud transcription and AI proofreading service. A first App Store installation receives a one-time 10-minute trial after our server verifies the Apple-signed App Transaction. Local FunASR, Local Whisper, Apple Speech, and user-configured cloud providers remain available as alternative subtitle plans.

Smart Subtitle consumables provide either 60 or 300 minutes of managed cloud transcription and AI proofreading. Audio is uploaded directly from the Mac to temporary Alibaba Cloud OSS storage using a short-lived upload policy issued by our server. The app never contains our permanent cloud API key. Credits are granted only after our server verifies an App Store Server Notification V2; a client-side successful purchase does not grant credits.

The app requests Apple Events permission only for the user-triggered “Export to Final Cut Pro” action, which opens Final Cut Pro with the generated FCPXML file.

No account is required. No sample login credentials are needed.

## 8. 隐私政策要点

隐私政策必须覆盖：

- 用户选择的音频和字幕文件只在本机处理，除非用户显式选择自备Key云服务或官方智能字幕。
- Apple 语音识别由系统能力处理。
- 本地 Whisper 不上传音频。
- 云端校对默认关闭；启用后，字幕文本会发送到用户配置的服务商。
- API Key 存储在 macOS Keychain。
- 官方智能字幕会将音频直传阿里临时OSS，用于ASR与AI校对；需说明临时存储与删除政策。
- 目录监听默认关闭，只监听用户选择的目录。
- 不收集分析数据，不追踪用户。
- 首装体验会把Apple签名的App Transaction发送至Billing验签；原始JWS和`appTransactionID`不落库，只保存不可逆摘要用于阻止重复领取。
- 阿里临时OSS音频有效期最长48小时并自动清理；Model API中的字幕结果仅加密暂存24小时。
- 用户内容只用于完成其发起的字幕处理，不用于研究、模型训练、广告或数据分析。

## 9. 提交前检查

- `swift build`
- `./script/build_and_run.sh --verify`
- `./script/release_appstore.sh --unsigned`
- 安装 Mac App Store 分发证书后运行 `./script/release_appstore.sh --package`
- 需要直传 App Store Connect 时运行 `./script/release_appstore.sh --upload`（必须能找到分发证书与 Installer 证书；不要期望 ad-hoc 包可通过审核上传）
- 在干净机器或新用户账户测试首次启动、文件选择、Apple Speech、导出 SRT、导出 FCPXML
- 在安装 Final Cut Pro 的机器测试“导出到 FCP”
- 在未安装 Final Cut Pro 的机器确认错误提示清楚
- 在开启和关闭菜单栏图标时测试 Dock / Command-Tab / 关闭窗口行为
- 在 App Store Connect 创建两个消耗型商品：`com.jago.subforge.smart.60min`（60分钟，¥6）与 `com.jago.subforge.smart.300min`（300分钟，¥18），并确认价格和本地化状态可销售。
- 使用StoreKit Sandbox验证购买、取消、pending、Server Notifications V2、只发放一次额度和到账轮询。
- App Store Connect隐私问卷与`PrivacyInfo.xcprivacy`一致，声明Audio Data、Other User Content、User ID和Purchase History用于App Functionality且不追踪。
