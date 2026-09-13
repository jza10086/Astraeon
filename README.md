# ASTRAEON
Godot 4.7 体素生存建造游戏。

## 当前状态
已初始化开发环境：MCP 编辑器插件、Codex 配置、项目技能、开发规范、功能目录和 F6/F5 可启动的 3D 占位场景。
占位地面并非体素世界；尚未实现移动、挖掘、建造、背包、存档或生存规则。预览相机不代表最终游戏视角。

## 打开与验证
使用 Godot 4.7 stable 导入 project.godot，F5 运行入口 game/core/main.tscn。
在项目根目录运行：
~~~powershell
./tools/check.ps1
~~~
该命令检查引擎版本、完整导入、主场景短时启动及 Git 元数据；日志写入 tmp/。
完整导入会写入 .godot/ 和 Godot 用户数据，受平台权限约束。自动检查不能替代画面与交互的人工验收。

## 目录
- game/core/：应用入口与场景组装。
- game/world/、player/、survival/、inventory/、building/、crafting/、ui/：按功能组织场景、脚本和专用资源。
- shared/、autoload/、assets/：实际需要的共享代码、全局服务和共享资源。
- addons/：第三方插件；tests/：后续功能测试；docs/：设计和环境文档。
- .agents/skills/：项目内技能；.codex/config.toml 和 .mcp.json：MCP 客户端配置。
- tools/：开发脚本；tmp/：Git 忽略且 Godot 不导入的临时输出。

先阅读 AGENTS.md；MCP 的连接与迁移说明见 docs/development.md。
