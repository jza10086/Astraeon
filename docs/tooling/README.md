# 开发工具

## 职责与当前进度

Godot 4.7 stable、项目 MCP 技能、C++ 构建与针对性验证入口。

## 架构与数据流

确认目标 → 选择已连接编辑器或冷导入 → 执行 → 诊断。

## 详细文档与入口

[开发流程](development.md)、[MCP 本地修改](mcp_local_changes.md)、[基准入口](voxelgame_benchmarks.md)。

源码与测试入口：tools、.agents/skills、addons/godot_mcp_toolkit；test/tooling。

## 限制与待办

MCP 连接失败不证明编辑器关闭；进程信息不可读时阻止冲突导入，其他工作按依赖继续。

## 验证证据

[测试入口](../../test/tooling/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

[内容编译器、SDK与导出入口](../data/content_packages.md#制作与发布)：tools/content、addons/astraeon_content；缺失或过期原版包在正式导出前报错。

## 内容包制作入口

格式 2 包工程、单文件方块与外部图片索引见 [内容包](../data/content_packages.md#包工程与单文件资源制作格式-2)。[专用内容编辑器](content_editor.md)主工作区和 headless CLI 共用 tools/content/compiler.gd；build_sdk.py 从当前类型和单文件示例生成 SDK。原版图片位于 content_sources，不参与 Godot 导入或游戏发布；本地 receipt 记录外部图片指纹，verify_deployment.py 检查新鲜度。
