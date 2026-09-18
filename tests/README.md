# 自动检查

- native_world/test_native_world.gd：当前 C++ 生成、存档、恢复合约检查。
- native_world/runtime_probe.gd：原生世界移动、碰撞、保存和帧时采样；由 tools/test_native_voxel.py 驱动。
- entities/test_player.gd：原有角色测试，仍假定旧固定地面测试场；目前不应对原生主场景直接执行，后续需要独立实体测试场景。

旧 GDScript 体素后端的 tests/blocks、tests/world 及专属运行器已删除。旧报告仅供历史参考。已有编辑器连接时不要启动第二个编辑器导入；使用现有编辑器刷新和诊断。
