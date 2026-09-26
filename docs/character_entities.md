# 玩家与生物实体

当前玩家使用 HK416 V8。entities 负责实例运动、动作和视觉；world 负责地形碰撞与加载。无生物 AI、战斗或玩家状态存档。

2026-09-26 已确定人物制作标准为 Basic Voxel：19 骨骼（含左右肩胛）、六动作及八个肩部修正形态键，详见 [人物资产标准](character_asset_contract.md)。当前场景、导入参数和四动作控制器尚未迁移；下文描述现有运行实现，不是新标准的验收结果。

## 模块
以下路径相对 game/entities：
- common/gdscript/character_motor.gd：共享 CharacterMotor 接受 move_intent、sprint_requested、jump_requested，由控制器每物理帧调用 step。普通速度 4.3 m/s，快跑 5.6 m/s，重力 20，跳高 1.25 米。
- common/gdscript/character_visual.gd：读取真实速度、垂直速度与接地状态，播放当前四段动作。慢跑/快跑选择有滞回，播放倍率随实际速度变化，顶墙停止迈步。
- player/gdscript/player_controller.gd：玩家输入、相机与复位。
- player/scenes/player.tscn：胶囊、模型与相机组装，模型引用 player/assets/hk416.glb 的 V8 内容。

## 操作与世界
WASD 移动，Shift 快跑，鼠标观察，空格跳跃，Esc 释放鼠标，左键重新捕获。
F5 为当前原生体素世界，沿用现有碰撞就绪保护；左键挖掘、右键放置仍由 world 编排，不属于动画组件。
Jump 即时起跳跳过蓄力，空中按物理速度采样，实际接地才播放落地段；移动可打断落地缓冲。
胶囊高 1.8 米、半径 0.3 米；实体层 2、世界层 1。相机为临时第三人称，最终视角未定。
不保留旧模型、旧 1.1 m/s 字段、Run 调用或旧跳跃时间点。

## 验证入口
test/entities/scenes/player_playground.tscn 为独立固定碰撞场地，包含地面、平台、墙、斜坡与低顶，不读写正式世界。
test/entities/gdscript/test_player.gd 检查当前资产、速度、动画与碰撞；窗口模式额外验证输入和鼠标捕获。
资产要求见 character_asset_contract.md。人工手感、极端混合姿态、斜坡滑脚与多分辨率验收仍单独进行。

## V8 迁移验证（2026-09-23）
Godot 4.7.stable.official.5b4e0cb0f，D3D12 / Forward+。
完整资源导入通过；独立图形实体回归 33 项通过；临时原生世界集成检查通过。
日志：tmp/v8_import.log、tmp/v8_player_test.log、tmp/v8_world_test.log。
世界截图：tmp/v8_world_idle.png、v8_world_walk.png、v8_world_run.png、v8_world_jump.png。
模型哈希与源 V8 一致；保留资源 UID 和 60 FPS、禁优化/压缩的导入设置。
本次为自动物理/输入/动画验证及截图检查，不等于人工操作手感或全部混合姿态验收。
