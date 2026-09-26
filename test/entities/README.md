# 实体测试

scenes/player_playground.tscn 为独立固定场地，可 F6 运行。gdscript/fixtures/character_playground.gd 创建碰撞夹具。
gdscript/test_player.gd 使用该场地验证标准素体的 19 骨骼、肩部形态轨道、六动作、4.3/5.6 速度、跳跃、碰撞和动画，不使用主世界或世界存档。

运行 Godot --path <项目> --fixed-fps 60 --script res://test/entities/gdscript/test_player.gd。
--headless 跳过窗口输入检查；需核对 ENTITY_TEST 完成标记、失败数和退出码。

gdscript/test_world_player.gd 是原生世界集成烟测，使用 tmp/basic_voxel_entity_world 与独立光影设置路径；检查出生、移动、快跑、跳跃和落地，图形模式截图写 tmp/basic_voxel_world_*.png。

按帧驱动的图形回归采用 --fixed-fps 60，使时间步与断言一致；它验证功能，不用于测量实时帧率。
