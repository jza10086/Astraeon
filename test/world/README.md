# 世界模块测试

Godot 4.7 无界面入口：

- `gdscript/test_landscape.gd`：22 项检查，覆盖自然/测试群系、森林、负坐标跨区段一致性、种子、三轴原木实际图集、水碰撞、保存及拒绝不兼容元数据。
- `gdscript/test_world_startup.gd`：以默认自然布局启动真实主场景，等待出生碰撞并正常保存退出。

原有 `test/native_world/gdscript/test_native_world.gd` 已同步新接口，18 项保存恢复契约通过；原 tests 目录现已迁入对应 test 测试项。新世界、记录和日志写 tmp。头部128字节/生成版本2。没有运行性能矩阵或人工视觉验收。
