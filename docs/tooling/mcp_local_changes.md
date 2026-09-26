# MCP 本地修改与更新复核

日期：2026-09-26。范围：仓库内提示、技能和冷导入入口；不改认证、工具名称、参数或错误码。

| 层 | 本地修改 | 更新时复核 |
| --- | --- | --- |
| 项目与随附 MCP 技能 | 依赖加载、autoload、进程归属、错误记录、Windows 验证入口一致化 | 不能重新引入无条件停止游戏、忽略错误或失效命令 |
| playtest_control.gd | ALREADY_PLAYING 提示先返回/查询已有会话，停止需归属或明确授权 | fail/return/runtime_poll 行为和原错误码保持 |
| file_commands.gd、scene_commands.gd、folder_commands.gd | 场景关闭错误需核对条件、状态并保留日志 | 不新增错误屏蔽，不把异常报告成成功 |
| 工具链 Import 与 tools/check.ps1 | 共用冷导入前置检查，查询失败或身份不明时报错 | 普通游戏和其他项目编辑器不能被无条件阻止；不杀进程、不提权 |

项目技能的默认流程聚焦 Godot 4.7；分发扩展及旧版本/C#机制留在上游参考，不作为 Astraeon 默认工作流。插件升级时逐项比较本表、AGENTS 和随附技能，而不是直接覆盖项目适配。

验证结果见 [整理验证](../../test/tooling/reports/documentation_mcp_20260926.md)，迁移清单见 [研究记录](tmp/2026-09-26_document_migration.md)。
