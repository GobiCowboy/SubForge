# 201 环境与配置文档

## 1. 运行环境

- 操作系统：macOS 14 及以上
- 目标形态：本地桌面应用
- 用户数据：本地文件系统
- 外部依赖：可选云端 ASR、可选云端 LLM、可选 Final Cut Pro
- Apple 转写验证：首次使用需要系统语音识别权限
- 本地 Whisper：需要 `whisper-cli` 与模型文件

## 2. 本地资源

- 输入素材：音频、SRT；不支持 MP4、MOV、MKV 等视频文件
- 输出文件：SRT、FCPXML
- 日志目录：用户本地 Application Support
- 模型资源：本地 Whisper 模型按需下载到 `Application Support/SubForge/models`
- 设置验证资源：内置测试音频 `test_audio.m4a`

## 3. 配置分类

### 3.1 必要配置

- 转写引擎
- 语言
- 导出参数

### 3.2 可选配置

- AI 校对开关
- 云端服务地址与密钥
- 字幕样式
- 最大字幕长度
- 监听目录与监听模式

## 4. 密钥原则

- 本地优先，不应默认要求云端密钥
- 云端能力只有在用户明确启用时才需要配置
- 密钥不写入项目文档正文，不提交到仓库

## 5. 当前可见运行入口

- 本地构建 / 运行入口：`./script/build_and_run.sh`
- 运行校验入口：`./script/build_and_run.sh --verify`
- GUI 产物目录：`dist/SubForge.app`
- App Store 打包 / 上传：`./script/release_appstore.sh`（`--unsigned` / `--signed` / `--package` / `--upload`）
- 站外 Developer ID 公证分发：`./script/release_developer_id.sh`
- App Store 产物目录：`dist/appstore/`
- 站外分发产物目录：`dist/developer-id/`

签名与 entitlement 文件在 `Config/`：

| 文件 | 用途 |
|------|------|
| `SubForge.entitlements` | App Store 主程序（含 App Sandbox） |
| `SubForge.debug.entitlements` | 本地 ad-hoc 调试签名 |
| `SubForge.inherit.entitlements` | App Store 嵌套 `whisper-cli`（sandbox + inherit） |
| `SubForge.developer-id.entitlements` | 站外分发主程序与嵌套二进制（**无** Sandbox） |

## 6. 文档约束

- 本文件记录“需要哪些配置”
- 不规定“配置一定以哪种代码结构保存”
