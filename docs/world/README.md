# 权威世界

## 职责与当前进度

C++ 生成、流式加载、网格/碰撞、保存及权威缓存。

## 架构与数据流

静态定义 → WorldContent → 原生状态表与 VoxelTerrain；section 快照供 shading 派生计算。

标题页单人存档列表通过 core/world_selection 选择 runtime_data/worlds 的独立子目录，创建和读取后注入 world_directory；世界仍自行校验内容注册表和原生区段版本。存档名不参与原生状态表或生成算法，旧格式不转换。

## 详细文档与入口

[原生后端](native_voxel_backend.md)、[生成](world_generation.md)、[坐标与加载](voxel_chunks.md)、[缓存](world_cache.md)。

源码与测试入口：game/world；test/world、test/native_world。

## 限制与待办

无流体模拟、玩家位置存档或多人写入协议。生命、饱食度和模式已由 gameplay 保存，见 [玩家状态](../gameplay/modes.md#保存与职责)；玩家背包与掉落物已通过 gameplay 日志与地形编辑配对保存，详见 [掉落物](../entities/dropped_items.md)。历史 GDScript 后端已删除。

## 验证证据

[测试入口](../../test/world/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

内容包轻量定义 → 世界追加式注册表 → 原生数值ID；Region格式3绑定世界标识，详见 [内容包与存档](../data/content_packages.md#世界与-mod)。

命名创建的存档通过 world.cfg（format=1）保存创建种子与 biome_layout，临时文件成功替换后才进入世界；参数不可读取或版本不支持时拒绝启动。场景直接启动且没有此可选参数文件时使用导出参数，原生区段头仍校验种子和生成版本。
