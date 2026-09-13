# 开发环境
参考 GodotParty 的通用工程规范，保留 GDScript 显式类型、@export 依赖、按功能组织、main 分支及适量验证。
派对玩法、SDK、玩家数量、联机要求未迁移。体素技术选型、视角、地图规模和多人模式待后续确定。

## MCP
插件已在 project.godot 启用，MCPRuntimeServer 为配套开发桥。
本机已有 godot-mcp-server，两个客户端配置都通过 cmd /c godot-mcp-server 启动，并以 GODOT_MCP_PROJECT_PATH 固定到 F:/GodotProjects/Astraeon。
配置未自动放宽客户端工具审批。复制自 GodotParty 的第三方插件与技能保留许可证和来源。

打开本项目编辑器后，MCP 面板应显示 localhost 服务。客户端需要重新加载项目配置或重新连接 MCP 才能使用新增配置。
连接后先调用 project_get_settings，核对 application/config/name 是 ASTRAEON，再修改场景。
若同时打开多个工程，不可仅凭端口判断目标；LSP 还需各自独立端口，按 addons/godot_mcp_toolkit/docs/multi-instance.md 配置。
目录移动后同时更新 .codex/config.toml 与 .mcp.json 中的 GODOT_MCP_PROJECT_PATH。

## 项目技能
- .agents/skills/godot-project-tooling/SKILL.md：版本解析、导入、脚本检查、Git 元数据。
- .agents/skills/godot-mcp-toolkit/SKILL.md：已连接编辑器的工作流。
- .agents/skills/mcp-extension-creator/SKILL.md：仅在需要扩展 MCP 时使用。
技能已经在项目中提供，当前已开启任务的技能列表不保证即时刷新；AGENTS.md 提供直接入口。

Godot 工具链沿用本机 4.7 stable 路径，位于 .agents/skills/godot-project-tooling/godot-toolchains.json。
其他机器可通过 GODOT_BIN 或 tools/check.ps1 -GodotPath 指定控制台可执行文件，不要修改全局 PATH。
保留 Forward Plus、D3D12、Jolt Physics。无 GDExtension、C# 或外部体素模块依赖。
