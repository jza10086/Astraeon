# 权威世界

## 职责与当前进度

C++ 生成、流式加载、网格/碰撞、保存及权威缓存。

## 架构与数据流

静态定义 → WorldContent → 原生状态表与 VoxelTerrain；section 快照供 shading 派生计算。

## 详细文档与入口

[原生后端](native_voxel_backend.md)、[生成](world_generation.md)、[坐标与加载](voxel_chunks.md)、[缓存](world_cache.md)。

源码与测试入口：game/world；test/world、test/native_world。

## 限制与待办

无流体模拟、玩家状态存档或多人写入协议；历史 GDScript 后端已删除。

## 验证证据

[测试入口](../../test/world/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。
