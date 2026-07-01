# 305 导出与交付

## 1. 功能目标

把编辑结果稳定输出为外部可直接使用的文件，而不是只停留在应用内部。

## 2. 主要场景

- 导出 SRT 交给剪辑或分发流程
- 导出 FCPXML 进入 Final Cut Pro
- 同时导出 SRT 与 FCPXML
- 导出后自动打开 Final Cut Pro 并导入 FCPXML
- 在固定目录中查找输出结果

## 3. 功能范围

包含：

- 生成 SRT
- 生成 FCPXML
- 生成 SRT + FCPXML 组合输出
- 选择输出位置
- 可选：导出后通过 AppleScript 打开 Final Cut Pro 并导入 FCPXML
- 与 FCP 工作流衔接

不包含：

- 多格式批量导出中心
- 云端发布

## 4. 关键规则

- 导出入口必须明确
- 编辑页顶部按钮、菜单命令和快捷键必须复用同一套导出逻辑
- 输出路径必须可预测
- 空字幕处理策略必须一致
- 输出文件应与当前编辑结果保持同步
- “导出到 FCP”是 FCPXML 的后续动作，不是独立文件格式
- 导出行为必须反映设置页里的格式、保存位置、自动覆盖和导出到 FCP 条件
- 自动导入 Final Cut Pro 需要 macOS 自动化权限

## 5. 输出要求

- SRT 适合通用字幕交付
- FCPXML 适合剪辑软件工作流
- SRT + FCPXML 适合同时交付字幕文件和剪辑工程导入文件
- 当目录中存在 FCP 目标上下文时，应尽量减少用户额外操作
- 开启导出到 FCP 时，导出成功后应直接把 FCPXML 交给 Final Cut Pro
- FCPXML 中的字幕样式必须来自设置页“基本样式”，包括字体、字号、颜色、描边/填充近似与 X/Y/Z 位置
- FCPXML 标题 Position 直接使用基本样式里的 X/Y/Z；横屏默认 `0 -467 0`，竖屏默认 `0 -495 0`
- FCPXML 必须通过 Final Cut Pro DTD 校验：`resources` 只放资源项，`text-style-def` 跟随对应 `title` 并包含 `text-style`
- FCPXML 必须输出一条连续主故事线：主 `spine` 放一个覆盖全时长的外层 `gap`，字幕和空白放在该 `gap` 内部的二级 `spine lane="1"`；字幕片段之间的真实空白用内部 `gap` 显式占位；零时长空白不能写成 FCPXML 元素，避免 Final Cut Pro 因 `duration="0s"` 拒绝导入

## 6. 验收标准

- 可得到 SRT 文件
- 可得到 FCPXML 文件
- 可通过一个选项同时得到 SRT 和 FCPXML 文件
- 用户知道文件保存到了哪里
- FCP 工作流下交付结果可继续使用
- 开启导出到 FCP 后，系统能触发 Final Cut Pro 打开/导入流程；未授权时需要给出失败反馈
