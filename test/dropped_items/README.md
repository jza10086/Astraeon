# 掉落物测试

使用当前构建的 Godot 4.7 扩展；先按项目工具规则确认引擎及编辑器状态。原生扩展更新后旧编辑器需要重启，外部新游戏进程读取当前 descriptor。

原生测试（headless）：

```powershell
& $godot --headless --path . --script res://test/dropped_items/gdscript/test_native_drops.gd
```

实际主世界集成测试（需要图形设备）：

```powershell
& $godot --path . --script res://test/dropped_items/gdscript/test_world_drops.gd
& $godot --path . --script res://test/dropped_items/gdscript/test_world_drops.gd -- --failure
```

`$godot` 指按 .godot-version / 项目 tooling skill 解析的引擎路径。世界、设置、截图写 tmp，不修改正式存档。测试不与性能测量或原生构建并行。

检查进程退出码和 JSON 标记里的 failures，并检查所有 SCRIPT ERROR/ERROR/Parser Error。最后一条故障注入命令**应且只应产生一次** `ERROR: Dropped-item generation failed: invalid record or capacity exhausted`，同时有 19 项通过的结果；其他错误均为失败，不能将该命令描述为无错误日志。

原生覆盖落地/休眠、支撑移除、未加载冻结、跨 chunk、负坐标、延迟、部分移除、快照和非法数据；主世界覆盖 Q/Shift+Q、关闭持物、挖掘、满包/部分拾取、配对存档、显示节点及故障停止。截图中的草块和剑为冻结在相机前的显示夹具，用于观察外观，不作为物理验收。

现有物品栏回归仍在 test/inventory。尚未覆盖长期大量掉落物压力、合堆/消失（未实现）或硬件断电。详见 [证据](reports/2026-09-27_dropped_items.md) 和 [实现契约](../../docs/entities/dropped_items.md)。

投掷与设置集成检查：`--script res://test/dropped_items/gdscript/test_throwing.gd`（图形）。覆盖动画手部、第三人称瞄准、自由指针、初速度、设置重读、主菜单取消／保存与非法值拒绝。证据见 [投掷设置](reports/2026-09-27_throwing.md)。

挖掘随机偏移、向上弹跳及默认 0 的朝玩家力度由 `gdscript/test_throwing.gd` 验证，包括实际原生运动和设置草稿／保存：[验证记录](reports/2026-09-27_mining_bounce.md)。

颜色空间检查：`--script res://test/dropped_items/gdscript/test_drop_colors.gd`（图形），使用真实掉落网格构建接口，对比旧线性解释、修正后的 sRGB 顶点色与地形 source_color 颜色约定；[报告](reports/2026-09-27_drop_colors/README.md)。
