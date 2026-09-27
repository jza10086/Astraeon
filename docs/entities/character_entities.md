# 玩家与生物实体

当前玩家可在主菜单选择 Basic Voxel 标准素体或 Klukai；两者遵守 19 根主体骨、六套动作与肩部修正形态键标准。entities 负责实例运动、动作和视觉；world 负责地形碰撞与加载。无生物 AI、战斗或玩家状态存档。

## 模块

以下路径相对 game/entities：

- common/gdscript/character_motor.gd：共享 CharacterMotor 接受 move_intent、slow_walk_requested、sprint_requested、jump_requested，由控制器每物理帧调用 step。普通速度 4.3 m/s，快跑 5.6 m/s，重力 20，跳高 1.25 米。
- common/gdscript/character_visual.gd：读取实际速度、垂直速度和接地状态，选择六套动作；同时播放骨骼与肩部修正轨道。
- player/gdscript/player_controller.gd：玩家输入、相机与复位。
- player/scenes/player.tscn：胶囊、模型与相机组装；Visual 在进入场景树时按已保存的模型 ID 实例化资产。

## 操作与动作

WASD 移动，按住 Ctrl 慢走（0.5141 m/s），Shift 快跑，V 切换第一／第三人称，鼠标观察，空格跳跃，Esc 释放鼠标，左键重新捕获。F5 为原生体素世界，保留碰撞就绪保护；挖掘和放置仍由 world 编排。

Ctrl 慢走优先于 Shift 快跑，松开 Ctrl 恢复普通移动或仍按住的快跑；鼠标释放时慢走输入无效。

地面静止播放 Idle。低速播放 Walk（参考 0.5141 m/s），普通移动播放 Run（4.3 m/s），快跑播放 Sprint（5.6 m/s）。按实际速度选择而非按键意图，顶墙后停止迈步；Walk/Run 分界约 0.77 m/s，滞回 0.08，Run/Sprint 分界 4.95 m/s，滞回 0.15。播放倍率随实际速度变化；地面步态切换保留归一化周期相位，过渡 0.12 秒。复杂混合下的脚部接触仍需人工验收。

空格即时施加跳跃冲量，跳过 JumpStart 的蓄力段。上升时以垂直速度将 0.5167 秒至片尾映射到起跳至顶点，骨骼和形态键一起采样；下降、撞顶或自然跌落时循环 Fall。真实接地后混合回 Idle 或当前地面步态，没有虚构落地片段或旧 Jump 时间区间。

模型净高 1.74 米；移动胶囊保留高 1.8 米、半径 0.3 米、中心 Y=0.9，实体层 2、世界层 1。默认第一人称眼高 Y=1.62，隐藏自身 Visual，未实现手臂、持物或身体显示；V 可切换第三人称（观察点 Y=1.35、距离 4 米）。没有运行时 IK、布娃娃或头发/布料物理。

## 相机行为

两种视角共用 CameraPivot/SpringArm/Camera，world 的射线和 shading 的引用保持稳定。第一人称弹簧臂长度与余量为 0、碰撞掩码为 0，由人物胶囊防止眼睛进入地形；隐藏整个自身模型，也不显示自身模型的阴影。眼高来自角色根节点，不跟随动画头骨，避免步态引起镜头晃动。

默认水平看向前方；鼠标控制水平转向与俯仰，第一人称上下限 ±85°，第三人称恢复 -65°～20°。移动只使用水平朝向，不受抬头低头影响。V 切换时恢复第三人称的距离、余量、碰撞掩码和模型显示；俯仰超出第三人称范围时钳制。第一人称不增加手臂、持物、头部晃动或视角偏好保存。

视角请求在下一个物理帧提交：使用与弹簧臂相同的形状、碰撞掩码和玩家排除项，先计算第三人称安全距离，再同时更新相机位置与人物显隐，重置相机支架子树的物理插值。提交后发出 view_changed，由世界组装连接到 shading.reset_camera_history，清除 motion/post 历史；短距离切换同样重置，不依赖 3 米阈值。

## 资产与验证入口

资产要求见 [人物资产标准](../resource_specifications.md)。导入 240 Hz，关闭动画优化/压缩，保留形态轨道和八权重蒙皮；Idle、Walk、Run、Sprint、Fall 循环，JumpStart 不循环。源文件不被游戏修改，旧 HK416 游戏资源已移除。

test/entities/scenes/player_playground.tscn 为独立固定碰撞场地，不读写正式世界。test_player.gd 检查骨架、肩部轨道、速度、起跳/下落、碰撞和图形模式下的键鼠输入；使用 --fixed-fps 60 保证按帧断言的模拟时间。

test_world_player.gd 使用 tmp/basic_voxel_entity_world 与独立光影设置，检查原生世界出生、移动、快跑、跳跃、落地和保存队列。截图写入 tmp/basic_voxel_world_*.png。

人工手感、肘膝内折重叠、极端混合、斜坡滑脚和多分辨率验收仍单独进行。

## 游戏参数与迁移边界

1.74 m 是素体净高，不自动改写碰撞。现有玩家胶囊高 1.8 m、半径 0.3 m、中心 Y=0.9；第一人称眼高 1.62 m；第三人称观察点 Y=1.35、距离 4 m。本次保留此碰撞与相机参数，碰撞回归覆盖头顶间隙、墙面、斜坡和低顶。碰撞不随摆臂、头发、帽子或裙摆扩大。

现有运动参数：慢走 0.5141 m/s、普通速度 4.3 m/s、快跑 5.6 m/s、重力 20 m/s²、跳高 1.25 m、加速度 25 m/s²、制动 30 m/s²、空中加速度 8 m/s²、土狼时间 0.10 s、跳跃缓冲 0.12 s。它们属于游戏设计，不从动画预览推导。

标准素体资源为 game/entities/player/assets/basic_voxel.glb，保留其资源 UID；旧 HK416 GLB 和四动作契约已移除，没有兼容别名。测试与状态文档随资产同步更新。


验证记录见 [资产核对](../../test/entities/reports/basic_voxel_asset_20260926.md)和[接入回归](../../test/entities/reports/basic_voxel_integration_20260926.md)。

## 人物选择与实例化

`common/gdscript/character_models.gd` 合并内置与外部模型目录；内置人物为`basic_voxel`（标准素体）和 `klukai`（Klukai）。主菜单提供选择、预览、确认和本地列表删除；配置写入 `runtime_data/settings.cfg` 的 `[character] model`，缺少该项时默认标准素体。同节的 `removed`（PackedStringArray）记录隐藏的内置模型 ID，不删除内置资源。外部模型 ID 为 `user/<完整文件名>`，由 `character_library.gd` 扫描 `external_data/characters/*.glb` 生成，不需要手改目录代码。删除当前内置模型时在同一次配置写入中保存剩余模型；删除当前外部模型先保存剩余选择，再删除用户目录中的单个 GLB，最后一项不可删除。保存先载入并保留其他设置节，再写临时文件并重命名；未知 ID 或无法解析的配置不静默兼容。

`CharacterVisual` 只在 `_ready` 中读取一次选择并创建 `Model/AnimationPlayer`。两种模型共用现有运动、碰撞、相机和六动作状态控制器；没有游戏内替换入口。预览使用独立 SubViewport，不创建运动实体或世界地形。退出预览释放模型并停止其视口更新。

Klukai 保留 48 根头发附属骨；本次不添加次级物理。模型切换不改变胶囊、速度、眼高和角色状态，不是运行时换装系统。资源契约见 [人物资源](../resource_specifications.md#klukai-角色变体)，验证见 [模型选择回归](../../test/ui/reports/2026-09-27_character_selection.md)。

外部 GLB 使用 GLTFDocument 在运行时加载并生成 PackedScene，不加载外部脚本或编辑器 `.import`。按内容哈希缓存已校验场景；每次打开人物菜单重新扫描，预览/实例化前检查文件变化。外部选择失效时使用首个可用项；外部文件全部消失且内置人物都被隐藏时，标准素体作为可用回退。不更改正在世界中运行的实体。
