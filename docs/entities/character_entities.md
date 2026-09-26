# 玩家与生物实体

当前玩家使用 Basic Voxel 标准素体：19 骨骼、六套动作与八个肩部修正形态键。entities 负责实例运动、动作和视觉；world 负责地形碰撞与加载。无生物 AI、战斗或玩家状态存档。

## 模块

以下路径相对 game/entities：

- common/gdscript/character_motor.gd：共享 CharacterMotor 接受 move_intent、sprint_requested、jump_requested，由控制器每物理帧调用 step。普通速度 4.3 m/s，快跑 5.6 m/s，重力 20，跳高 1.25 米。
- common/gdscript/character_visual.gd：读取实际速度、垂直速度和接地状态，选择六套动作；同时播放骨骼与肩部修正轨道。
- player/gdscript/player_controller.gd：玩家输入、相机与复位。
- player/scenes/player.tscn：胶囊、模型与相机组装；模型引用 player/assets/basic_voxel.glb，保留原玩家模型资源 UID。

## 操作与动作

WASD 移动，Shift 快跑，鼠标观察，空格跳跃，Esc 释放鼠标，左键重新捕获。F5 为原生体素世界，保留碰撞就绪保护；挖掘和放置仍由 world 编排。

地面静止播放 Idle。低速播放 Walk（参考 0.5141 m/s），普通移动播放 Run（4.3 m/s），快跑播放 Sprint（5.6 m/s）。按实际速度选择而非按键意图，顶墙后停止迈步；Walk/Run 分界约 0.77 m/s，滞回 0.08，Run/Sprint 分界 4.95 m/s，滞回 0.15。播放倍率随实际速度变化；地面步态切换保留归一化周期相位，过渡 0.12 秒。复杂混合下的脚部接触仍需人工验收。

空格即时施加跳跃冲量，跳过 JumpStart 的蓄力段。上升时以垂直速度将 0.5167 秒至片尾映射到起跳至顶点，骨骼和形态键一起采样；下降、撞顶或自然跌落时循环 Fall。真实接地后混合回 Idle 或当前地面步态，没有虚构落地片段或旧 Jump 时间区间。

模型净高 1.74 米；移动胶囊保留高 1.8 米、半径 0.3 米、中心 Y=0.9，实体层 2、世界层 1。相机观察点 Y=1.35、距离 4 米，为临时第三人称方案。没有运行时 IK、布娃娃或头发/布料物理。

## 资产与验证入口

资产要求见 [人物资产标准](../resource_specifications.md)。导入 240 Hz，关闭动画优化/压缩，保留形态轨道和八权重蒙皮；Idle、Walk、Run、Sprint、Fall 循环，JumpStart 不循环。源文件不被游戏修改，旧 HK416 游戏资源已移除。

test/entities/scenes/player_playground.tscn 为独立固定碰撞场地，不读写正式世界。test_player.gd 检查骨架、肩部轨道、速度、起跳/下落、碰撞和图形模式下的键鼠输入；使用 --fixed-fps 60 保证按帧断言的模拟时间。

test_world_player.gd 使用 tmp/basic_voxel_entity_world 与独立光影设置，检查原生世界出生、移动、快跑、跳跃、落地和保存队列。截图写入 tmp/basic_voxel_world_*.png。

人工手感、肘膝内折重叠、极端混合、斜坡滑脚和多分辨率验收仍单独进行。

## 游戏参数与迁移边界

1.74 m 是素体净高，不自动改写碰撞。现有玩家胶囊高 1.8 m、半径 0.3 m、中心 Y=0.9；相机观察点 Y=1.35、距离 4 m。本次保留此碰撞与相机参数，碰撞回归覆盖头顶间隙、墙面、斜坡和低顶。碰撞不随摆臂、头发、帽子或裙摆扩大。

现有运动参数：普通速度 4.3 m/s、快跑 5.6 m/s、重力 20 m/s²、跳高 1.25 m、加速度 25 m/s²、制动 30 m/s²、空中加速度 8 m/s²、土狼时间 0.10 s、跳跃缓冲 0.12 s。它们属于游戏设计，不从动画预览推导。

玩家资源为 game/entities/player/assets/basic_voxel.glb，保留原玩家模型资源 UID；旧 HK416 GLB 和四动作契约已移除，没有兼容别名。测试与状态文档随资产同步更新。


验证记录见 [资产核对](../../test/entities/reports/basic_voxel_asset_20260926.md)和[接入回归](../../test/entities/reports/basic_voxel_integration_20260926.md)。
