# 文档与开发工具验证

从项目根执行 `pwsh -NoProfile -File test/tooling/test_cold_import.ps1`，通过模拟进程记录检查冷导入冲突分类和查询拒绝；不启动 Godot、不终止任何进程。

`python test/tooling/check_documentation.py` 检查维护中的 Markdown 本地链接、锚点和旧入口；历史报告保留的原始代码路径不作为当前运行入口。

实际编辑器导入单独记录在 reports，模拟检查不代表真实编辑器或用户进程验收。
