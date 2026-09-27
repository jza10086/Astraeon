# 物品栏测试与交互样板

在 Godot 中打开 `scenes/inventory_sample.tscn`，按编辑器 F6。包含预填物品的 10 槽快捷栏与 30 格储物区，不修改正式存档。E/Esc 切换，1—0 或滚轮选槽，左键拿起/放下，右键拆半/放一个，Shift+左键快速转移；目录左键拿一个、中键拿一组。右上搜索、右下储物栏；手上物品不占槽，关闭直接移除。

从项目根运行：

```powershell
$godotExe = 'F:/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe'
& $godotExe --headless --path . --script res://test/inventory/gdscript/test_inventory.gd
& $godotExe --path . --script res://test/inventory/gdscript/test_inventory.gd
& $godotExe --path . --script res://test/inventory/gdscript/test_world_inventory.gd
```

前两项覆盖规则/恢复/UI，图形运行另输出 tmp/inventory-ui 截图。最后一项进入隔离 tmp 世界测试真实交互，必须有图形设备以初始化现有 GPU 缓存。每个脚本成功后自动退出；检查退出码、错误输出及结尾测试摘要。正式世界从主界面「单人游戏」进入，首次为空背包。

[实现与边界](../../docs/gameplay/inventory.md)。版本化验证记录在 reports/；测试存档/日志/截图原始输出在 tmp/。

创造选取同样位于上述样板的 E 面板内；分类/搜索/领取边界检查：`--script res://test/inventory/gdscript/test_creative.gd`，图形模式在 tmp/inventory-work/cursor_creative.png 与 cursor_storage.png 输出截图。
