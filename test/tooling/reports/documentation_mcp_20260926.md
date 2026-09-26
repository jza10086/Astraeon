# 文档与 MCP 整理验证

日期：2026-09-26。范围：文档、技能、插件提示、冷导入前置检查。未改玩法、资源参数、存档格式或原生实现。

## 工具与编辑器

- PowerShell 7 模拟进程测试：17 项通过，退出 0；覆盖同项目编辑器、其他项目、游戏/测试、空列表、带空格路径、规范化、相对/缺失/重复路径、查询失败。不启动或停止 Godot。
- 引擎解析：4.7.stable.official.5b4e0cb0f，工具链路径匹配 .godot-version。
- Windows CIM 真实进程查询返回“拒绝访问”；停止该查询路线，没有提升查询权限、终止进程或启动第二个编辑器。
- MCP 配置目标与注册表为 F:/GodotProjects/Astraeon；实时 project_get_settings 返回 ASTRAEON。
- 经仓库配置启动的任务自有 stdio MCP 客户端复用现有编辑器：完整 editor_refresh 成功（mode=full），等待空闲成功；控制台 error 列表为 0。客户端结束后重置其工具组并关闭自有桥进程。未关闭用户游戏或编辑器。
- 插件只修改文本提示，工具名称、参数、错误码和认证保持原样。没有为了测试 ALREADY_PLAYING 而启动/停止用户游戏。

## 文档与边界

迁移清单见 [迁移记录](../../../docs/tooling/tmp/2026-09-26_document_migration.md)。模块 tmp 参与 Git；根 tmp 仍忽略。116 份文档、240 个本地链接/锚点检查通过，迁移去向和旧入口检查通过；6 份迁移 JSON 与 Git 原记录比较，规范化行尾后的文本及解析数据完全一致。8 个模块 tmp 均可参与版本控制，根 tmp 仍被忽略。两份 MCP 配置的 command、args、env 一致，配置未修改。

未执行性能矩阵、玩法回归或人工视觉验收。既有 test/shading/gdscript/test_lighting_modules.gd 仍使用旧格式标记 astraeon-shading-20260922b 构造配置；这是整理时发现的现有测试契约漂移，本次不修改该玩法测试，也不把它报告为通过。后续运行该测试前应按当前 profile 格式修正夹具。

原始 MCP 响应位于根 tmp/editor_documentation_validation.json，临时迁移输入快照位于 tmp/doc_reorg_before；均不作为需长期保留的唯一证据。

本批 118 个变更路径的定向 diff 空白检查通过；4 份 PowerShell 脚本解析无错误。工作区既有 camera_post.glsl.import 的尾部空行属于本批前已存在的改动，未顺手修改。
