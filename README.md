# ASTRAEON

Godot 4.7 体素生存建造游戏。

## 启动

新检出先按 [原生后端构建说明](docs/world/native_voxel_backend.md#构建与验证)构建扩展，再用指定 Godot 打开 `project.godot`，F5 运行 `game/core/main.tscn`。DLL 不纳入 Git。

验证前阅读 [开发流程](docs/tooling/development.md)。`tools/check.ps1` 是包含冷导入与启动的检查批次，不能与同 checkout 编辑器并用。

## 文档入口

- [全项目开发与文档规则](AGENTS.md)
- [整体进度与架构](total_development.md)
- [资源制作与交付规格](docs/resource_specifications.md)
- [开发环境、MCP 与验证](docs/tooling/README.md)
- [测试入口](test/README.md)
- [来源与许可](docs/credits.md)
