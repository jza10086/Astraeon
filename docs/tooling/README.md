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
