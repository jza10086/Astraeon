# 玩家与生物实体初版

本轮只实现可控制玩家，不含生物 AI、感知、寻路、战斗或持久化。
- game/entities/common/gdscript/character_motor.gd：共享 CharacterBody3D 运动组件，接受世界空间移动意图与单次跳跃请求，由拥有者每物理帧调用 step。
- game/entities/common/gdscript/character_visual.gd：独立动画与模型朝向，接受实际运动状态。
- game/entities/player/gdscript/player_controller.gd：玩家输入、临时第三人称相机、掉出世界复位。
- game/entities/player/scenes/player.tscn：可复用玩家场景，@export 引用连接组件。
- game/core/main.tscn：F5 可运行固定碰撞试验场，不依赖地图实验方案。

操作：WASD 移动，鼠标转相机，空格跳跃，Esc 释放鼠标，左键重新捕获。
碰撞层 1 为世界，层 2 为实体；玩家当前只碰撞世界。相机弹簧臂只检测世界。
默认速度 1.1 m/s 匹配现有 Run。保持原模型、动画和材质；动作适配见 character_asset_contract.md。
固定场地提供地板、1 米平台、墙、斜坡和低顶。离开场地跌落到 Y=-20 以下回到出生点。
输入与 AI 不属于共享运动组件；未来生物可另行提供意图，无需引入全局管理器。
本阶段不接入流式体素世界；接入前须解决附近碰撞就绪、卸载边界和出生位置安全。
玩家状态未保存，重新启动回到出生点；相机参数当前为场景默认值，尚无设置界面。

## 验证记录（2026-09-17）
Godot 4.7.stable.official.5b4e0cb0f，Forward+ / D3D12，RTX 3060 Laptop GPU。
tests/entities/test_player.gd 在实际图形进程中完成 24 项检查，退出码 0，无 SCRIPT ERROR / ERROR。
涵盖站稳、速度、斜向归一、制动、跳高与禁止二段跳、三种动画、墙体、低顶、跳上一米平台、斜坡、平台跌落、复位、骨架、输入和鼠标捕获。
日志 tmp/entity_window_test.log。无界面运行跳过 6 项依赖鼠标捕获的窗口检查，不将其当作窗口验收。
可运行：Godot --path <项目目录> --script res://tests/entities/test_player.gd；脚本 60 秒超时会返回失败。
主场景实际截图与 MCP 输入模拟已检查；手动手感、极端动画混合、多分辨率及流式世界接受度尚未验收。
资产 SHA-256：8446EBCE45EB312CABC6222520DD99D21F003999145E4F435B54234156C848EF，项目副本与原 GLB 一致。
