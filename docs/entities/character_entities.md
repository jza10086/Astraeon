# 玩家与生物实体

默认人物为 external_data 中的 basic_voxel 文件夹，TP 完整身体与 FP 双臂独立加载；TP 使用 21 骨八动作，FP 使用同标准骨架与三个独立动作。entities 负责实例运动、动画与视觉；world 负责地形碰撞与加载。无生物 AI、战斗或玩家状态存档。

## 模块

以下路径相对 game/entities：

- common/gdscript/character_motor.gd：共享 CharacterMotor 接受 move_intent、slow_walk_requested、sprint_requested、jump_requested，由控制器每物理帧调用 step。普通速度 4.3 m/s，快跑 5.6 m/s，重力 20，跳高 1.25 米。
- common/gdscript/character_visual.gd：读取实际速度、垂直速度和接地状态，选择六套动作；同时播放骨骼与肩部修正轨道。
- player/gdscript/player_controller.gd：玩家输入、相机与复位。
- player/scenes/player.tscn：胶囊、模型与相机组装；Visual 在进入场景树时按已保存的模型 ID 实例化资产。

## 操作与动作

WASD 移动，按住 Ctrl 慢走（0.5141 m/s），Shift 快跑，V 切换第一／第三人称，鼠标观察，空格跳跃，主世界 Esc 打开暂停菜单，回到游戏时恢复捕获；独立角色场景保留 Esc 释放鼠标、左键重新捕获。F5 经标题页进入原生体素世界，保留碰撞就绪保护；挖掘和放置仍由 world 编排。

Ctrl 慢走优先于 Shift 快跑，松开 Ctrl 恢复普通移动或仍按住的快跑；鼠标释放时慢走输入无效。

地面静止播放 Idle。低速播放 Walk（参考 0.5141 m/s），普通移动播放 Run（4.3 m/s），快跑播放 Sprint（5.6 m/s）。按实际速度选择而非按键意图，顶墙后停止迈步；Walk/Run 分界约 0.77 m/s，滞回 0.08，Run/Sprint 分界 4.95 m/s，滞回 0.15。播放倍率随实际速度变化；地面步态切换保留归一化周期相位，过渡 0.12 秒。复杂混合下的脚部接触仍需人工验收。

空格即时施加跳跃冲量，跳过 JumpStart 的蓄力段。上升时以垂直速度将 0.5167 秒至片尾映射到起跳至顶点，骨骼和形态键一起采样；下降、撞顶或自然跌落时循环 Fall。真实接地后混合回 Idle 或当前地面步态，没有虚构落地片段或旧 Jump 时间区间。

模型净高 1.74 米；移动胶囊高 1.8 米、半径 0.3 米、中心 Y=0.9，实体层 2、世界层 1。默认第一人称眼高 Y=1.62，隐藏完整 TP 模型，显示相机下的独立 FP 双臂；V 切换第三人称（观察点 Y=1.35、距离 4 米）。没有运行时 IK、布娃娃或头发/布料物理。

## 右手持方块

主世界的 HeldBlock 监听 inventory.changed，读取已提交的快捷栏选中槽。仅方块物品使用 HoldBlock_R；空槽、数量耗尽及工具恢复空手。它不扣减数量、不生成掉落物或碰撞体，不改变世界保存内容。

CharacterVisual 每帧先手动推进现有运动 AnimationPlayer，再由 common/gdscript/hold_pose.gd 采样 HoldBlock_R 中的 RightScapula、RightShoulder、RightUpperArm、RightLowerArm、Grip_R 和右侧肩部形态键。权重在 0.12 秒内淡入淡出，握持循环保持正常速度；躯干、左臂和双腿继续播放运动动作。没有把完整站立片段覆盖到跑跳上，也不修改共享动画资产。

player/gdscript/held_block.gd 将边长 0.12 m 的方块挂到 Grip_R，中心偏移为局部 (0,0,0.06) m，方块 +Y 对齐 Grip +Z。外观读取当前内容包的六面颜色或图集和裁剪透明参数；当前选中纹理由独立缓存 owner 持有，切换与退出时释放。纹理尚未就绪时暂不显示，加载失败停止世界并报告错误。当前简化材质没有接入地形体素光、发光或水面特效。

第一、第三人称分别使用自己骨架的 Grip_R 和方块显示节点，共享选中物品与外观资源。FP 独立播放 FP_Idle / FP_HoldBlock_R，过渡 0.12 秒；平视可见手臂与托举方块。尚未接入持物避墙、工具挥动或 FP 跑跳片段；左右手资源都保留，当前只接入右手。最新验证见 [成对人物与独立第一人称](../../test/entities/reports/2026-09-27_paired_character_models.md)。

## 相机行为

两种视角共用 CameraPivot/SpringArm/Camera，world 射线和 shading 引用保持稳定。第一人称弹簧臂长度、余量与碰撞掩码为 0，眼高来自角色根节点且没有水平偏移。FP 模型挂在相机下，外层 Y 旋转 180°并保留 GLB 内部骨架偏移，跟随俯仰；垂直 FOV=58.7155°、near=0.01 m。FP 不投射阴影，TP 模型整体现隐，不再切除头部三角形。两种模型仍由同一世界相机绘制，未增加穿墙始终可见的独立渲染层。

默认水平看向前方；鼠标控制水平转向与俯仰，第一人称上下限 ±85°，第三人称恢复 -65°～20°。移动只使用水平朝向，不受抬头低头影响。V 切换时恢复第三人称的距离、余量、碰撞掩码和模型显示；俯仰超出第三人称范围时钳制。切回第三人称恢复原 FOV 与 near。尚无头部晃动或视角偏好保存。

视角请求在下一个物理帧提交：使用与弹簧臂相同的形状、碰撞掩码和玩家排除项，先计算第三人称安全距离，再同时更新相机位置与人物显隐，重置相机支架子树的物理插值。提交后发出 view_changed，由世界组装连接到 shading.reset_camera_history，清除 motion/post 历史；短距离切换同样重置，不依赖 3 米阈值。

## 资产与验证入口

资产要求见 [人物资产标准](../resource_specifications.md)。导入 240 Hz，关闭动画优化/压缩，保留形态轨道和八权重蒙皮；Idle、Walk、Run、Sprint、Fall 循环，JumpStart 不循环。源文件不被游戏修改，旧 HK416 游戏资源已移除。

test/entities/scenes/player_playground.tscn 为独立固定碰撞场地，不读写正式世界。test_player.gd 检查骨架、肩部轨道、速度、起跳/下落、碰撞和图形模式下的键鼠输入；使用 --fixed-fps 60 保证按帧断言的模拟时间。

test_world_player.gd 使用 tmp/basic_voxel_entity_world 与独立光影设置，检查原生世界出生、移动、快跑、跳跃、落地和保存队列。截图写入 tmp/basic_voxel_world_*.png。

人工手感、肘膝内折重叠、极端混合、斜坡滑脚和多分辨率验收仍单独进行。

## 游戏参数与迁移边界

1.74 m 是素体净高，不自动改写碰撞。现有玩家胶囊高 1.8 m、半径 0.3 m、中心 Y=0.9；第一人称眼高 1.62 m；第三人称观察点 Y=1.35、距离 4 m。本次保留此碰撞与相机参数，碰撞回归覆盖头顶间隙、墙面、斜坡和低顶。碰撞不随摆臂、头发、帽子或裙摆扩大。

现有运动参数：慢走 0.5141 m/s、普通速度 4.3 m/s、快跑 5.6 m/s、重力 20 m/s²、跳高 1.25 m、加速度 25 m/s²、制动 30 m/s²、空中加速度 8 m/s²、土狼时间 0.10 s、跳跃缓冲 0.12 s。它们属于游戏设计，不从动画预览推导。

标准素体为 external_data/characters/basic_voxel/ 下的 basic_voxel_tp.glb 和 basic_voxel_fp.glb；game/ 下的旧 GLB 与 first_person_body.gd 已删除。固定骨架校验由 character_rig_standard.gd 提供，不依赖内置模型。


验证记录见 [资产核对](../../test/entities/reports/basic_voxel_asset_20260926.md)和[接入回归](../../test/entities/reports/basic_voxel_integration_20260926.md)。

## 人物选择与实例化

`common/gdscript/character_library.gd` 扫描 external_data/characters 的直接子目录，每个目录按同前缀 `_tp.glb` / `_fp.glb` 校验为一个人物。character_models.gd 将前缀保存到 runtime_data/settings.cfg 的 `[character] model`，缺省选择 basic_voxel；旧 removed 配置、未知 ID 和无法解析的配置均拒绝，不自动回退。配置保存保留其他设置节，使用临时文件与重命名。

CharacterVisual 在创建实体时读取一次选择，同时实例化 TP 和 FP，各用自己的动画播放器；游戏内只切换视角，不更换人物。模型选择不改变速度、胶囊或角色状态。加载失败停止相关实体；主世界报告错误并停止启动。

人物页左侧一个名字按钮代表整个人物，右侧同时预览 TP Idle 和 FP_Idle。第一人称预览使用固定 16:9 构图；两个独立 SubViewport 不创建运动实体或地形。关闭页面释放两模型并停止视口更新。

按钮导入选择文件夹，按成对文件校验、暂存、再次校验及目录重命名发布；同名不同内容拒绝覆盖。打开文件夹定位当前预览人物。删除只处理人物目录中的两份 GLB，不碰原始来源；有额外文件或子目录时拒绝，最后一个人物不可删除。删除当前人物先保存另一个有效选择，再删除目录；I/O 失败立即报告，不自动重试。

GLTFDocument 在运行时生成 PackedScene，不读取编辑器 .import；按两份文件的组合哈希缓存。重新打开菜单扫描，实例化前检查变化，不影响已进入世界的实体。无内置模型副本或缺失回退。交付契约见 [资源规格](../resource_specifications.md#外部人物运行时导入)，最新证据见 [成对人物验收](../../test/entities/reports/2026-09-27_paired_character_models.md)。

## 生存与创造模式

创造模式允许飞行，速度 8/16 m/s；运动输入与地面共用控制器，Ctrl 飞行时下降。菜单清空输入，切回生存清空运动并恢复重力。飞行开关和位置不保存；[详细规则](../gameplay/modes.md)。
