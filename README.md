# ASTRAEON

Godot 4.7 体素生存建造游戏。

## 启动

新检出先按 [原生后端构建说明](docs/world/native_voxel_backend.md#构建与验证)构建扩展，再用指定 Godot 打开 `project.godot`，先在 Content Packages 面板编译原版清单（或运行 `tools/content/build_builtin.gd`），再 F5 进入主界面，在左下角「切换人物」选择模型，再选择「单人游戏」，从存档列表读取或创建世界。主界面入口为 `game/ui/main_menu/scenes/main_menu.tscn`。DLL 不纳入 Git。若提示旧原型存档不支持，可点击「创建新世界（保留旧存档）」继续；原存档保留且不会自动迁移。

验证前阅读 [开发流程](docs/tooling/development.md)。`tools/check.ps1` 是包含冷导入与启动的检查批次，不能与同 checkout 编辑器并用。

## 文档入口

- [全项目开发与文档规则](AGENTS.md)
- [整体进度与架构](total_development.md)
- [资源制作与交付规格](docs/resource_specifications.md)
- [快捷键与按键映射](docs/input_mapping.md)
- [开发环境、MCP 与验证](docs/tooling/README.md)
- [测试入口](test/README.md)
- [来源与许可](docs/credits.md)
