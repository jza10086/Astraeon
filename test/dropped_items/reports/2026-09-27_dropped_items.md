# 2026-09-27 掉落物与错误停止验证

状态：通过本轮功能检查；不是性能或人工手感验收。

环境：Godot 4.7.stable.official.5b4e0cb0f，Windows，图形测试 D3D12 Forward+ / RTX 3060 Laptop。构建命令 `python tools/build_native_voxel.py --target editor --install --jobs 8` 成功；[原生清单](2026-09-27_dropped_items/editor_manifest.json) 与 [关键源码 SHA-256](2026-09-27_dropped_items/sources.json) 已留存。

所有游戏进程为本轮独立新进程，世界/设置隔离到 tmp；未终止已有编辑器。脚本通过编辑器 targeted refresh / wait_for_idle 同步；旧编辑器仍需重启以加载新增原生类，不能将外部进程通过视为旧编辑器 DLL 已更新。

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 原生运动、碰撞、休眠、chunk、快照校验 | 16 项通过 | [native](2026-09-27_dropped_items/drops_native.log) |
| 实际主世界 Q/Shift+Q、鼠标关闭、挖掘、拾取、保存、外观及生成失败 | 19 项通过 | [world/failure](2026-09-27_dropped_items/drops_failure.log) |
| 背包事务、日志与 UI 回归 | 53 项通过 | [inventory](2026-09-27_dropped_items/inventory_regression.log) |
| 实际世界模态 UI、挖掘、放置、满包与读取 | 21 项通过 | [world inventory](2026-09-27_dropped_items/inventory_world_regression.log) |
| 暂停与成功保存返回标题 | 18 项通过 | [pause](2026-09-27_dropped_items/pause_regression.log) |
| 暂停保存失败停止 | 15 项通过 | [pause failure](2026-09-27_dropped_items/pause_failure.log) |

所有测试进程退出码为 0。普通检查没有 SCRIPT ERROR / ERROR / Parser Error。两条故障注入日志各包含一次预期 ERROR：`Dropped-item generation failed: invalid record or capacity exhausted`、`Save failed or timed out:  Injected checkpoint failure`；无其他错误，不能笼统描述为日志无错误。

命令入口见 [测试说明](../README.md)。背包回归分别为 `--script res://test/inventory/gdscript/test_inventory.gd`（headless）、`--script res://test/inventory/gdscript/test_world_inventory.gd`（图形）；暂停为场景 `res://test/ui/scenes/pause_menu_check.tscn`，故障模式追加 `-- --failure`。

[显示截图](2026-09-27_dropped_items/world.png) 已人工查看：草块与剑均可显示。两者为暂停运动、放在相机前的测试夹具，截图不证明自然落地位置。运动由原生数值断言验证；没有进行长时间压力、帧率对比、磁盘故障或断电测试。屏幕上的即时 FPS 不作为性能结果。

首版不包含自动合堆、定时消失、流体推动、区域磁盘独立装卸或完整地形着色复刻；详见 [当前契约](../../../docs/entities/dropped_items.md)。
