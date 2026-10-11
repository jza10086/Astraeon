# 单人暂停菜单

日期：2026-09-27。Godot 4.7.stable.official.5b4e0cb0f，D3D12 Forward+。

通过已识别的 Astraeon 编辑器运行 `res://test/ui/scenes/pause_menu_check.tscn`，结果：

```
PAUSE_MENU_CHECK checks=20 failures=0
```

真实原生世界放在 tmp 下；检查 Esc 打开和关闭、冻结玩家、阻止暂停中打开背包、设置返回层级与焦点、F6 路径、背包 Esc 优先消费、暂停中持久化保存、保存成功后返回标题、标题恢复未暂停与正常窗口关闭状态。注入背包 checkpoint 错误验证保存失败不离场、按钮解锁可重试，清除注入后正常保存成功。通过日志无 SCRIPT ERROR / ERROR。

另在正常主世界进行 MCP 键盘与按钮交互，人工检查暂停菜单截图和设置页；返回后运行时场景路径为标题页。共享按钮主题从标题场景提取为独立 Theme。

共享主题提取后重跑 `res://test/ui/scenes/main_menu_check.tscn`：六种窗口尺寸，`MAIN_MENU_CHECK checks=102 failures=0`。

工具边界：全量 MCP 刷新仍出现既有 progress dialog / message queue 工具诊断，不视作无错误导入；本次成功的运行测试与脚本检查单独计证。首轮测试驱动遗漏物理键码且未等待场景切换的空档，修正驱动后重跑通过。物理多显示器和长期保存压力不在本次验收内。
