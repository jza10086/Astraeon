# 原生世界测试

- gdscript/test_native_world.gd：C++ 生成、存档、双记录恢复契约。
- gdscript/runtime_probe.gd：原生世界移动、碰撞、保存和帧时采样。
- runners/test_native_voxel.py：契约及短图形测试矩阵。从项目根运行 `python test/native_world/runners/test_native_voxel.py --godot <Godot控制台路径>`。

日志、测试存档和临时报告写 tmp/native-probe。已有编辑器连接时使用现有编辑器刷新，不启动第二个编辑器导入。
