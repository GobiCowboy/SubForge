# SubForge 文档总索引

这套文档的目标是固定产品边界、用户流程、功能清单与当前可运行骨架，为后续持续迭代提供统一依据。

当前文档除了功能层，也同步记录了已经稳定下来的项目结构、构建入口和日志约定。

## 100 需求与架构

- [101_product_requirements.md](./100_requirements_architecture/101_product_requirements.md)
- [102_user_flows.md](./100_requirements_architecture/102_user_flows.md)
- [103_architecture.md](./100_requirements_architecture/103_architecture.md)
- [104_technical_choices.md](./100_requirements_architecture/104_technical_choices.md)

## 200 基础文档

- [201_environment_config.md](./200_foundation/201_environment_config.md)
- [202_project_structure.md](./200_foundation/202_project_structure.md)
- [203_data_model.md](./200_foundation/203_data_model.md)
- [204_quality_plan.md](./200_foundation/204_quality_plan.md)
- [205_build_release.md](./200_foundation/205_build_release.md)
- [206_logging_system.md](./200_foundation/206_logging_system.md)
- [207_appstore_submission.md](./200_foundation/207_appstore_submission.md)

## 300 功能文档

- [301_workspace_intake.md](./300_features/301_workspace_intake.md)
- [302_transcription_pipeline.md](./300_features/302_transcription_pipeline.md)
- [303_ai_proofreading.md](./300_features/303_ai_proofreading.md)
- [304_subtitle_editor.md](./300_features/304_subtitle_editor.md)
- [305_export_delivery.md](./300_features/305_export_delivery.md)
- [306_settings_center.md](./300_features/306_settings_center.md)
- [307_watch_folder_workflow.md](./300_features/307_watch_folder_workflow.md)

## 900 项目记忆

- [901_feature_index.md](./900_project_memory/901_feature_index.md)
- [902_implementation_index.md](./900_project_memory/902_implementation_index.md)
- [903_abstraction_index.md](./900_project_memory/903_abstraction_index.md)
- [904_issue_index.md](./900_project_memory/904_issue_index.md)
- [905_ai_dev_checklist.md](./900_project_memory/905_ai_dev_checklist.md)

## 当前文档原则

- 先用产品语言描述问题，再进入实现。
- 只保留 P0 功能，避免把临时实现细节误写成长期需求。
- 当前已稳定的结构、日志和运行约定写入 200 / 900，不再散落在对话里。
- 能作为规则的内容写进功能文档，不能确定的实现方案先不写死。
