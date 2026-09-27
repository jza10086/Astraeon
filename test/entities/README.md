# 实体测试

scenes/player_playground.tscn 为独立固定场地，可 F6 运行。gdscript/fixtures/character_playground.gd 创建碰撞夹具。
gdscript/test_player.gd 使用该场地验证标准素体的 19 骨骼、肩部形态轨道、六动作、4.3/5.6 速度、跳跃、碰撞、视角切换和动画，不使用主世界或世界存档。

运行 Godot --path <项目> --fixed-fps 60 --script res://test/entities/gdscript/test_player.gd。
--headless 跳过窗口输入检查；需核对 ENTITY_TEST 完成标记、失败数和退出码。

gdscript/test_world_player.gd 是原生世界集成烟测，使用 tmp/first_person_entity_world 与独立光影设置路径；检查第一人称眼位、模型隐藏、地形射线与挖掘，以及出生、移动、快跑、跳跃和落地，图形模式截图写 tmp/first_person_world_*.png。

按帧驱动的图形回归采用 --fixed-fps 60，使时间步与断言一致；它验证功能，不用于测量实时帧率。

人物变体回归：`test_player.gd` 默认固定标准素体；命令末尾增加 `-- klukai` 验证 Klukai 的 67 骨骼与 752 条肩部形态轨道，以及相同的运动、碰撞、六动作与视角检查。`test_world_player.gd` 同样支持 `-- klukai`；不依赖或修改用户人物选择。测试进程会停止自身 MCP runtime 监听，避免外部编辑器操作混入输入回归。最新证据见 [人物选择](../ui/reports/2026-09-27_character_selection.md)。
