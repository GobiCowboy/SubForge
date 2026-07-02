# 207 App Store 提交准备

## 1. 当前结论

SubForge 已进入 App Store 提交准备阶段，但当前本机还不能直接上传：

- 当前本机缺少 Mac App Store 分发签名身份。
- `script/release_appstore.sh --signed` 会因缺少 app signing identity 停止，这是预期保护。
- `script/release_appstore.sh --unsigned` 可生成 release app bundle，用于结构检查。

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
```

可配置环境变量：

```bash
APP_VERSION=1.0
APP_BUILD=1
TEAM_ID=4UNNXY925R
APP_SIGN_IDENTITY="3rd Party Mac Developer Application: ..."
INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: ..."
```

## 3. 签名要求

需要安装或配置：

- Mac App Store app signing identity
- Mac App Store installer signing identity
- Bundle ID: `com.jago.subforge`
- Team ID: `4UNNXY925R`

当前本机只检测到：

- `Apple Development`
- `Developer ID Application`

这两个不能替代 Mac App Store 上传签名。

## 4. Entitlements

主 app 使用：

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.automation.apple-events`

语音识别只保留 `NSSpeechRecognitionUsageDescription` 权限说明。Apple 远端校验不接受 macOS app bundle 签名中包含 `com.apple.security.personal-information.speech-recognition` entitlement。

嵌入命令行工具使用继承 entitlement：

- `com.apple.security.app-sandbox`
- `com.apple.security.inherit`

## 5. 隐私清单

已提供并随 app bundle 打包：

- `Resources/PrivacyInfo.xcprivacy`

当前声明：

- 不追踪用户
- 不收集隐私数据类型
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
- 检查 `otool -L` 不再包含 `/opt/homebrew` 或 `/usr/local`
- 打包第三方 license 到 `Contents/Resources/ThirdPartyNotices`

## 7. App Review Notes 草稿

SubForge is a macOS utility for turning user-selected audio or video into editable subtitles, then exporting SRT and Final Cut Pro XML files. The app can optionally watch a user-selected folder for new audio exported from Final Cut Pro. Folder watching is off by default and only starts after the user selects a folder.

The app uses Apple Speech Recognition by default. Local Whisper transcription is optional and runs on-device using bundled whisper.cpp components. Cloud proofreading is off by default; if the user enables it and enters their own API key, subtitle text is sent to the configured provider for proofreading.

The app requests Apple Events permission only for the user-triggered “Export to Final Cut Pro” action, which opens Final Cut Pro with the generated FCPXML file.

No account is required. No sample login credentials are needed.

## 8. 隐私政策要点

隐私政策必须覆盖：

- 用户选择的音频、视频和字幕文件只在本机处理，除非用户显式启用云端服务。
- Apple 语音识别由系统能力处理。
- 本地 Whisper 不上传音频。
- 云端校对默认关闭；启用后，字幕文本会发送到用户配置的服务商。
- API Key 存储在 macOS Keychain。
- 目录监听默认关闭，只监听用户选择的目录。
- 不收集分析数据，不追踪用户。

## 9. 提交前检查

- `swift build`
- `./script/build_and_run.sh --verify`
- `./script/release_appstore.sh --unsigned`
- 安装 Mac App Store 分发证书后运行 `./script/release_appstore.sh --package`
- 在干净机器或新用户账户测试首次启动、文件选择、Apple Speech、导出 SRT、导出 FCPXML
- 在安装 Final Cut Pro 的机器测试“导出到 FCP”
- 在未安装 Final Cut Pro 的机器确认错误提示清楚
- 在开启和关闭菜单栏图标时测试 Dock / Command-Tab / 关闭窗口行为
