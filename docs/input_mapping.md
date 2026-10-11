# 快捷键与按键映射

最后核对：2026-09-27。记录当前默认绑定、InputMap 动作名及生效范围；以项目配置和实际输入处理为依据。键盘绑定使用物理键位。本文件不代表已经实现游戏内改键界面。

## 主界面

F5 默认进入 `game/ui/main_menu/scenes/main_menu.tscn`。鼠标始终可见；使用 Godot 内置 `ui_up/down/left/right`、`ui_focus_next/prev`、`ui_accept`、`ui_cancel`，不新增游戏动作。

- 鼠标左键选择；方向键或 Tab / Shift+Tab 移动焦点，Enter / Space 激活。多人占位不可激活，不进入焦点循环。
- 设置页 Esc 或「返回」放弃草稿并将焦点还给设置按钮；「保存并返回」写入现有 `runtime_data/settings.cfg`。
- 主界面 Esc 或「退出游戏」打开确认框，默认焦点为取消；确认框 Esc 取消退出。载入期间锁定主按钮，忽略返回，失败后可重试。
- 标题页不处理玩家移动、挖掘或主世界 F6 设置动作。
- 单人游戏打开存档选择页：方向键选择列表项，Enter 或双击读取；Tab 切换读取／创建／删除／返回。创建页输入名称后 Enter 创建并进入；Esc 返回列表，列表 Esc 返回标题，删除确认框 Esc 保留存档。读取期间锁定操作，空列表禁用读取与删除。

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
| Space | 地面跳跃；创造双击切换飞行（0.3 秒） | `jump` | project.godot |
| Space / Ctrl（飞行时按住） | 上升 / 下降 | `fly_up` / `fly_down` | project.godot |
| 鼠标移动 | 调整观察方向 | 无；`InputEventMouseMotion` | player_controller.gd |
| Esc | 打开／关闭暂停菜单；设置中返回暂停菜单 | `ui_cancel`（内置）；背包关闭仍消费 `release_mouse` | pause_menu.gd / inventory_hud.gd |
| 鼠标左键 | 捕获鼠标 | `capture_mouse` | project.godot |
| Q / Shift+Q | 丢出选中槽一个 / 整堆；背包关闭、鼠标捕获且未保存时生效 | `drop_item` | native_world.gd 运行时注册，dropped_items.gd 消费 |
| 鼠标左键 | 生存模式长按挖掘；创造模式点击即时挖掘 | `mine_block` | native_world.gd 运行时注册 |
| 鼠标右键 | 放置当前快捷槽物品；生存扣除一个，创造不扣除 | `place_block` | native_world.gd 运行时注册 |
| F6 | 打开设置／返回暂停菜单 | `shading_settings` | world_shading.gd 运行时注册 |

- 默认第一人称，V 在鼠标捕获且玩家输入启用时切换视角，忽略按键重复事件；不保存视角偏好。两种视角共用相机和交互射线，主世界提示 `V View`。
- 非飞行时 Ctrl 与 Shift 同按时慢走优先，松开 Ctrl 恢复普通移动或仍按住的快跑。慢走由 player_controller.gd 消费、CharacterMotor 限速；主世界屏幕提示为 `Ctrl Walk`。鼠标释放时不接受慢走输入。
- Esc 打开暂停菜单，提供回到游戏、设置、返回标题界面；树暂停并禁用玩家输入。Esc 或回到游戏恢复鼠标捕获。设置中的 Esc / F6 / 返回按钮只回到暂停菜单；F6 在游戏中直接打开暂停设置。背包打开时第一下 Esc 只关闭背包。
- 返回标题会等待现有自动保存结束，再排空地形生成／流式任务、保存修改区段并完成背包 checkpoint。保存中禁用菜单操作；运行保存失败报错并停止世界，不提供重试或继续游戏分支。原生后台任务和缓存提交可继续排空，玩家和世界时间不推进。
- 生存挖掘每 0.05 秒结算并显示十阶段裂纹；松开/换目标保留损伤，默认停止 30 秒后恢复，暂停不计时。匹配工具标签时按工具速度加速，详见 [挖掘规则](gameplay/mining.md)。
- 准星指向 8m 内已加载且可编辑的非水体方块时显示黑色边框；暂停、菜单/背包操作或释放鼠标时隐藏。不增加按键。
- 挖掘／放置需世界就绪、未处于保存状态且鼠标已捕获；交互射线距离为 8 米。放置位置与玩家占用空间相交时拒绝放置。
- `capture_mouse` 与 `mine_block` 共用左键；重新捕获鼠标的点击由玩家控制器消费，不会同时挖掘。
- 当前没有手动保存、合成或复位快捷键；地形自动保存及正常关闭保存见 [世界后端](world/native_voxel_backend.md#当前存档格式)。

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

## 玩家物品栏

以下动作由 game/ui/inventory/gdscript/inventory_hud.gd 运行时注册，主世界就绪且未保存、未打开暂停菜单／设置时生效。背包打开时禁止移动/观察/挖掘/放置，F6 不抢占面板；设置打开时 E 不打开背包。

| 输入 | 动作 | 行为 |
| --- | --- | --- |
| E | inventory_toggle | 打开/关闭背包 |
| Esc | release_mouse（复用） | 背包打开时优先关闭并恢复捕获；其他时候由暂停菜单消费 |
| 1—9、0 | hotbar_0 … hotbar_9 | 选中十个快捷槽；0 是第十槽 |
| 滚轮上/下 | hotbar_previous / hotbar_next | 前/后槽，循环；背包打开时不切换 |
| 左键 | 槽位 GUI 事件 | 拿起整堆或放入/合并/交换；目录拿一个到鼠标 |
| 右键 | 槽位 GUI 事件 | 拿半堆，手上有物品则每次放一个 |
| 中键 | 槽位/目录 GUI 事件 | 复制一组到鼠标，来源不变 |
| Shift+左键 | 槽位 GUI 事件 | 储物区与快捷栏间快速转移 |

物品栏内 Shift 不触发世界快跑。投掷从人物右手出发；鼠标捕获时朝中央准星，背包内朝实际鼠标指针。力度在设置顶部配置。主世界点击面板外：左键丢出整堆，右键丢出一个；关闭面板丢出手上整堆。移除格仍直接删除；储物页 Shift+左键移除格清空背包和快捷栏。保存期间有鼠标持物则等待保存完成后关闭。主世界提示包含 1-0 / Wheel Select 与 E Inventory。

独立样板 test/inventory/scenes/inventory_sample.tscn 使用相同按键，但只操作内存中的预填物品，不运行玩家、世界或保存；关闭和面板外使用显式删除回调。Godot 编辑器 F6 用于运行该当前场景，不等同于游戏内 F6 光影设置。

创造背包入口：E。上方标签选择分类，右上为搜索，右下为储物栏。搜索框输入名称/ID/标签，空格分隔多个关键词；目录左键拿一个、中键拿一组，拿取后物品跟随鼠标，点击槽位才放入。搜索框有焦点时 E、数字键输入文字而不触发背包/快捷槽；Esc 关闭面板，结果区滚轮用于滚动。

## 主菜单人物选择

仅主菜单左下角「切换人物」可进入：鼠标点击左侧人物名字按钮，右侧分别播放第三人称 Idle 与第一人称 FP_Idle；列表溢出时鼠标滚轮滚动。Tab／方向键使用 Godot 默认 UI 焦点导航，Enter／Space 激活按钮。「使用此人物」保存并留在页面，已使用时显示按下的「当前使用」；「返回」或 Esc 退出并还原入口焦点。顶部「导入人物」选择包含同前缀 _tp.glb / _fp.glb 的人物文件夹，「打开人物文件夹」打开当前预览人物目录；删除移除该目录的成对副本，至少保留一个人物。不增加游戏 InputMap 动作，不提供游戏内人物切换快捷键。

## 模式输入条件

创造模式双击 jump 切换飞行；飞行中 fly_up/fly_down 使用空格/Ctrl，Ctrl 不执行 slow_walk，sprint 提升飞行速度至 16 m/s（默认 8 m/s）。菜单、背包、鼠标释放不接受飞行输入并清空双击计时；生存无法启用飞行。世界提示随模式更新。

创建世界选择模式；暂停菜单鼠标选择模式，不新增切换快捷键。生存 E 只打开普通储物窗口，无中键复制及删除；创造保留目录和搜索。两者共用槽位、鼠标持物、Q/Shift+Q 投掷与 Esc 优先级。

## 专用内容编辑器

顶部“内容编辑器”是 EditorPlugin 主工作区，不注册游戏 InputMap。以下导航只处理预览区域的 GUI 鼠标输入（2026-10-10 更新）：

| 输入 | 预览操作 |
| --- | --- |
| 中键拖动 | 围绕当前观察中心旋转 |
| Shift＋中键拖动 | 沿相机平面平移观察中心 |
| Ctrl＋中键上下拖动 | 连续缩放；上移拉近、下移拉远 |
| 滚轮上／下 | 拉近／拉远 |
| 六面／透视按钮 | 切换观察方向并重新居中 |

Shift 与 Ctrl 同按时优先平移。导航缩放距离限制为 1.2–15m；平移速度随距离与预览尺寸调整。左键拖动不再旋转预览；预览内滚轮被消费，不滚动外层面板。状态、裂纹阶段、暂停波纹仍使用界面控件。撤销 / 重做通过该工作区工具栏操作，文本控件保留 Godot 原生文本编辑行为；不覆盖编辑器全局快捷键。保存 / 放弃 / 取消对话框优先处理输入。
