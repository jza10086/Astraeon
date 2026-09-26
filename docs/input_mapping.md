# 快捷键与按键映射

最后核对：2026-09-26。记录当前默认绑定、InputMap 动作名及生效范围；以项目配置和实际输入处理为依据。键盘绑定使用物理键位。本文件不代表已经实现游戏内改键界面。

## 主世界

入口：`game/core/main.tscn`。移动与观察需玩家输入启用且鼠标处于捕获状态；加载、保存及设置菜单会影响可用操作。

| 默认输入 | 功能 | InputMap 动作 | 注册位置 |
| --- | --- | --- | --- |
| W | 向前移动 | `move_forward` | project.godot |
| S | 向后移动 | `move_back` | project.godot |
| A | 向左移动 | `move_left` | project.godot |
| D | 向右移动 | `move_right` | project.godot |
| Ctrl（按住） | 慢走，0.5141 m/s | `slow_walk` | project.godot |
| Shift（按住） | 快跑 | `sprint` | project.godot |
| V | 切换第一／第三人称 | `toggle_view` | project.godot |
| Space | 跳跃 | `jump` | project.godot |
| 鼠标移动 | 调整观察方向 | 无；`InputEventMouseMotion` | player_controller.gd |
| Esc | 释放鼠标 | `release_mouse` | project.godot |
| 鼠标左键 | 捕获鼠标 | `capture_mouse` | project.godot |
| 鼠标左键 | 挖掘命中的方块 | `mine_block` | native_world.gd 运行时注册 |
| 鼠标右键 | 在命中面相邻位置放置泥土 | `place_block` | native_world.gd 运行时注册 |
| F6 | 打开／关闭光影设置 | `shading_settings` | world_shading.gd 运行时注册 |

- 默认第一人称，V 在鼠标捕获且玩家输入启用时切换视角，忽略按键重复事件；不保存视角偏好。两种视角共用相机和交互射线，主世界提示 `V View`。
- Ctrl 与 Shift 同按时慢走优先，松开 Ctrl 恢复普通移动或仍按住的快跑。慢走由 player_controller.gd 消费、CharacterMotor 限速；主世界屏幕提示为 `Ctrl Walk`。鼠标释放时不接受慢走输入。
- 打开光影设置时释放鼠标并禁用玩家输入，关闭时重新捕获；世界继续运行。Esc 当前只负责玩家鼠标释放，不是关闭光影设置的专用动作。
- 挖掘／放置需世界就绪、未处于保存状态且鼠标已捕获；交互射线距离为 8 米。放置位置与玩家占用空间相交时拒绝放置。
- `capture_mouse` 与 `mine_block` 共用左键。重新捕获鼠标的点击没有独立的统一事件隔离规则，不承诺该次点击绝不会同时触发挖掘。
- 当前没有手动保存、背包、合成或复位快捷键；地形自动保存及正常关闭保存见 [世界后端](world/native_voxel_backend.md#当前存档格式)。

## 独立光影样板

仅适用于 `test/shading/scenes/shading_sample.tscn` 的自由相机，需先创建样板。数据驱动的 `content_sample.tscn` 使用正式玩家控制，参见 [样板说明](../test/shading/README.md)。

| 默认输入 | 功能 | InputMap 动作 |
| --- | --- | --- |
| 鼠标右键（按住）＋鼠标移动 | 捕获鼠标并环视，松开右键释放 | `p0_look` ＋ `InputEventMouseMotion` |
| W / S / A / D | 相机前／后／左／右移动 | `p0_forward` / `p0_back` / `p0_left` / `p0_right` |
| Q / E | 相机局部下／上移动 | `p0_down` / `p0_up` |
| Esc | 释放鼠标 | `p0_release` |

这些动作由 `test/shading/gdscript/shading_sample.gd` 运行时注册；相机移动仅在鼠标捕获时生效。场景按钮不属于键盘绑定。

## 编辑器运行入口

编辑器默认 F5 运行主场景，F6 运行当前场景；它们是 Godot 编辑器快捷键，不属于游戏 InputMap。游戏窗口获得输入时，主世界中的 F6 才表示光影设置。编辑器自定义快捷键以本机设置为准。

## 维护与代码依据

- [项目 InputMap](../project.godot)：静态绑定。
- [玩家输入](../game/entities/player/gdscript/player_controller.gd)：移动、跳跃、观察和鼠标捕获。
- [世界交互](../game/world/gdscript/native_world.gd)：挖掘／放置绑定及可用条件。
- [光影设置](../game/shading/gdscript/world_shading.gd)：F6 绑定及菜单输入状态。
- [自由相机样板](../test/shading/gdscript/shading_sample.gd)：样板专用绑定。

新增、删除或修改绑定时，同步更新此表、InputMap 或运行时注册、输入消费者及屏幕操作提示；明确生效场景、菜单状态和重键冲突。只记录已经生效的功能，不为未实现功能预留空动作。全项目维护规则见 [AGENTS](../AGENTS.md)。
