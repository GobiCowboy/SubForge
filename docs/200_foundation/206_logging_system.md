# 206 日志系统文档

## 1. 目标

日志的作用是帮助用户和开发者理解任务进行了什么、卡在哪一步、失败原因是什么。

## 2. 日志关注点

- 应用启动与退出
- 文件导入
- 转写开始 / 完成 / 失败
- AI 校对开始 / 完成 / 失败
- 编辑关键动作
- 导出结果
- 目录监听事件

## 3. 用户侧要求

- 出错时要有用户可理解提示
- 用户应能看到或定位日志文件路径
- 日志不应挤占主工作区

## 4. 开发侧要求

- 关键流程必须有开始、成功、失败三类记录
- 自动化工作流必须能回溯处理到哪一步
- 不在日志中明文泄露密钥

## 5. 分类建议

- `lifecycle`
- `import`
- `transcription`
- `proofreading`
- `editor`
- `export`
- `watcher`
- `settings`

## 6. 本轮约束

当前实现已经统一收口到 `Sources/Utilities/AppLog.swift`，分类与本文建议保持一致。

建议调试命令：

- 全量应用日志：`log stream --style compact --info --predicate 'process == "SubForge"'`
- AI 校对日志：`log stream --style compact --info --predicate 'subsystem == "SubForge" AND category == "proofreading"'`
- 编辑快捷键日志：`log stream --style compact --info --predicate 'subsystem == "SubForge" AND category == "editor"'`

后续新增日志时，优先扩展现有分类，不重新散落到页面里各自定义。
