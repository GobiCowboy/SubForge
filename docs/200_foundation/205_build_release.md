# 205 构建与发布文档

## 1. 当前目标

本文件只记录当前项目已知的构建入口、产物和发布约束，为后续重做提供操作背景。

## 2. 当前构建入口

- 开发运行：`./script/build_and_run.sh`
- Release 运行：`./script/build_and_run.sh release`
- 运行校验：`./script/build_and_run.sh --verify`
- Release 校验：`./script/build_and_run.sh --release-verify`
- 日志调试：`./script/build_and_run.sh --logs`
- Release 日志：`./script/build_and_run.sh --release-logs`
- Release 遥测：`./script/build_and_run.sh --release-telemetry`
- 产物目录：`dist/SubForge.app`

## 3. 当前交付产物

- macOS 应用包
- SRT 文件
- FCPXML 文件
- 设置验证资源（随应用一起打包的测试音频）

## 4. 发布前最小检查

- 应用可启动
- 设置可保存
- 导入、转写、编辑、导出主流程可走通
- 输出文件能在目标路径找到
- FCP 工作流可验证

## 5. 已知现状

- 当前仓库存在原型式脚本和源码并存的情况
- 当前真实运行入口已经统一到 `script/build_and_run.sh`
- SwiftUI GUI 应用不再建议直接运行 `.build/.../SubForge` 裸可执行文件，统一通过 `dist/SubForge.app` 或脚本启动
- 本地 Whisper 依赖 `whisper-cli` 与模型文件，云端能力依赖用户自行配置 Key

## 6. 后续重做建议

- 重做时统一保留一个权威构建入口
- 把开发运行、打包发布、测试验证的命令边界分开
- 把本地转写依赖、测试资源和云端配置前置写进发布检查表
