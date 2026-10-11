# Main 内容包接入验证

日期：2026-09-27。Godot 4.7，当前 editor/debug 扩展 4a1d7b833543。未运行性能测试。

Main 场景显式引用原版内容包；主菜单入树前传入同一设置路径，加载期间禁用内容包切换。已有 C++ 缓存、稳定注册表、编译物品和水体沿正式世界入口运行。

命令：`./tmp/content/run.ps1 -Script res://test/content/gdscript/test_main_entry.gd -Name main_entry_final -Graphical -TimeoutSeconds 115`。

结果：**12 checks，0 failures，进程退出0**。实际 ProjectSettings 主场景 -> 单人游戏按钮 -> `game/core/main.tscn`，默认64水平/32垂直视距。仅存档及设置使用 tmp 独立目录，未触碰用户存档。检查了控制器解锁、原版命名空间、编译物品/水体和视觉缓存无失败。

首轮断言错误地要求不存在的 astraeon:stone；读取包元数据确认当前基础方块为 dirt/grass/glowstone/leaves/log/water，修正断言后重跑通过。没有为测试添加虚构方块。

[日志](main_entry_final.log)、[进程身份](main_entry_final-process.json)、[截图](main_entry.png)。截图是可玩状态的功能证据，HUD 帧数不是基准结果；未等待全部远处光照队列耗尽。日志的系统证书/MCP 注册写入和渲染缓存写入警告仍存在，无 SCRIPT ERROR 或着色器编译错误。

未删除、转换或自动换用新用户存档；旧格式依然明确拒绝。本次不覆盖 SDK clean import 或 release 导出验证。
