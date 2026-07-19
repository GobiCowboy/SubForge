# Design QA

- Source visual truth: `/Users/jago/.codex/generated_images/019f7960-d699-7582-906a-f8026ad2b06f/exec-4ac80e91-1886-4c8f-971a-819d05f15673.png`
- Implementation screenshot: `/Users/jago/Documents/docker/project/SubForge/.codex/artifacts/settings-per-plan-official-final.png`
- Viewport: macOS 设置窗口 900 × 792 pt（Retina 截图 1800 × 1584 px）；内容区对照裁切 1316 × 1408 px
- State: 浅色模式；字幕页；官方方案；常用套餐已选择；余额 8 分 27 秒
- Full-view comparison evidence: `/Users/jago/Documents/docker/project/SubForge/.codex/artifacts/settings-final-comparison.png`（方案一初版）；用户后续明确要求将顶部公共字数滑杆移入各方案配置，最终截图以上述实现截图为准
- Focused region evidence:
  - 标题、方案选择和字数滑杆：`/Users/jago/Documents/docker/project/SubForge/.codex/artifacts/settings-top-comparison.png`
  - 余额、套餐和操作按钮：`/Users/jago/Documents/docker/project/SubForge/.codex/artifacts/settings-purchase-comparison.png`

## Findings

没有需要阻塞交付的 P0、P1 或 P2 差异。

- 字体与排版：实现使用 macOS 系统字体，字号、字重和层级与视觉稿一致；页面标题略强于设计稿，这是为了与通用、样式、导出和目录监听页面共用同一标题组件。
- 间距与布局：方案选择、能力列表、方案内字幕分段配置、余额和套餐保持清晰的垂直节奏；大卡片外框已经移除，分隔线承担主要层级。顶部公共字数滑杆按用户最新反馈移除。
- 颜色与视觉 token：使用系统语义色和强调色；所有设置页容器统一引用 `SettingsVisualTokens`，以官方页边框深度为标准，同时保持深色模式适配能力。
- 图片与图标：页面没有照片或插画资产；可见图标全部使用统一的 SF Symbols，没有占位图或自绘替代。
- 文案与内容：设计稿中的核心文案全部保留；额外保留了实时服务状态和云端处理说明，它们属于现有功能反馈和隐私说明。
- 可访问性与交互：侧栏切换、官方/自定义方案切换、配置状态和表单均可操作；切换到自定义再回到官方时没有出现钥匙串弹窗。

## Comparison History

1. 首次实现对照发现选中的购买套餐使用了浅蓝底，而设计稿只使用蓝色边框。已移除套餐填充色并重新构建、截图和对照。
2. 修正后没有剩余的 P0、P1 或 P2 差异。
3. 用户验收初版后要求公共字数滑杆不再占据页面顶部。已将其改为官方、自定义、本地三个方案各自独立的配置；这是经确认的设计变更，不计为视觉稿偏差。

## Follow-up Polish

- P3：实现额外显示服务状态与隐私说明，因此购买区域比设计稿多一行辅助信息；这是为保留现有功能而接受的差异。

## Interaction Verification

- 已验证设置侧栏在通用、字幕和样式之间切换，标题规格保持一致。
- 已验证官方与自定义方案切换，并确认配置状态位于“转写”和“AI 校对”标签内部。
- 购买按钮未触发真实交易；本轮只验证布局、可见状态和按钮可用性。
- 应用通过 `./script/build_and_run.sh run` 构建并启动；`swift test` 27 项测试通过。

final result: passed
