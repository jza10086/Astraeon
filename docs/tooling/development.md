# 开发环境与验证流程

## 环境与入口

引擎由根 `.godot-version` 指定为 Godot 4.7 stable。Forward+、D3D12、Jolt；生产体素依赖 C++／Voxel Tools GDExtension。项目内工具链解析顺序：显式 GodotPath → GODOT_BIN → 项目技能 toolchains JSON → PATH，不修改全局 PATH。

以下命令均从项目根目录使用 PowerShell 7（pwsh）执行。新检出先按 [原生后端](../world/native_voxel_backend.md#构建与验证)构建 DLL。

```powershell
& ./.agents/skills/godot-project-tooling/scripts/invoke_godot.ps1 -Mode Version -ProjectPath .
# 仅在冷导入前置检查通过后运行；它们会写缓存和 Godot 用户数据。
& ./.agents/skills/godot-project-tooling/scripts/invoke_godot.ps1 -Mode Import -ProjectPath .
# 完整冷导入、主场景短启动与 VCS 元数据检查：
& ./tools/check.ps1
```

针对脚本时调用同一工具的 `-Mode CheckScript -ScriptPath res://实际脚本.gd`；运行测试用 `-Mode RunScript`，测试脚本必须自行退出。CheckScript 只证明解析，不证明运行行为。不得为验证读取玩家真实存档，应使用对应测试的隔离路径。

## MCP 与编辑器路线

两份客户端配置 `.codex/config.toml` 和 `.mcp.json` 均通过 cmd /c godot-mcp-server 启动，并以 GODOT_MCP_PROJECT_PATH 指向此 checkout。移动仓库时同步更新两处；环境变量在 MCP 进程启动时读取，修改后重新连接。不要输出认证令牌或修改认证来修复目标错误。

先调用 project_get_settings，要求 application/config/name 为 ASTRAEON，再结合连接路径核对 checkout。相同名称不能区分不同 checkout。连接失败不证明编辑器已关闭。

已验证编辑器：外部引擎文件修改后 editor_refresh，再 editor_wait_for_idle，检查本轮控制台。插件或共享资源修改执行完整扫描；文档修改无需刷新。保留未保存场景，不用外部保存覆盖它们。

冷导入：tools/check.ps1 与工具链 Import 模式共同调用 tools/assert_cold_import.ps1。通过可执行文件、命令行、绝对项目路径判定；同 checkout 编辑器或身份不明的候选进程阻止导入。查询被拒绝时报告原始原因，不升级权限、自动关闭进程或绕过检查。检查只约束冷导入，不能把它当成所有游戏测试的门禁。检查与启动之间仍有时间窗口，运行期间不要手动打开同 checkout 的第二个编辑器。

## 构建、进程和测量

一次只运行一个原生构建。重建 DLL 后必须重启对应编辑器再验证新 API，文件刷新不能替换已加载 DLL。重启前确认进程归属并保留未保存场景。

任务启动进程应记录 PID、启动时间、可执行文件、项目路径及用途；停止前重新核对，不能仅凭 PID 或进程名判断。ALREADY_PLAYING 时优先返回已有实例或查询运行状态；只有本任务拥有的进程或用户明确授权的进程可以停止。编辑器强制停止不是正常保存退出。

性能测量期间不运行其他测试或构建，报告竞争负载。一般游戏/test 进程不因编辑器存在而一律禁止；读写存档需隔离。

## 诊断与验收

连接/认证失败先检查目标路径与连接；编译失败先看解析/编译日志；不通过删除缓存或反复重启猜测。已知引擎噪声仍需记录触发条件及操作后状态，不能无条件忽略 ERROR。

必须检查退出状态和 SCRIPT ERROR、ERROR:、Parser/Parse Error。按更改选择最小有效验证，自动检查、编辑器导入、图形、人工与性能验收分开报告。只发现本任务需要的 MCP 组，结束后 reset。

## 项目技能

- `.agents/skills/godot-project-tooling/`：工具链、冷导入与脚本检查。
- `.agents/skills/godot-mcp-toolkit/`：已连接编辑器操作。
- `.agents/skills/mcp-extension-creator/`：明确需要新增 MCP 工具时使用。

项目规则以 [AGENTS](../../AGENTS.md) 为准；本地插件提示补丁见 [MCP 修改说明](mcp_local_changes.md)。
