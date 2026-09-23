# 世界

gdscript/ 保存场景编排；gdscript/world_content.gd 从正式数据目录构建共享 ID 和外观库；native/ 按 generation、persistence、streaming 保存项目 C++。上游体素存储、网格和任务系统在顶层 native/voxel_tools。测试目标为 test/world，原生世界测试与运行器位于 test/native_world，地图测试位于 test/world。

缓存接入保留唯一 VoxelData 权威存储：带版本 section、温缓存驻留、CPU 网格/碰撞复用、Region 句柄与并行 I/O，以及共用主线程提交预算。完整生命周期与预算见 [world_cache.md](../../docs/world_cache.md)。光照/天气是 shading 的派生缓存，不能反向修改地图。
