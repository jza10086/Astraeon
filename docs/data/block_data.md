# 当前方块数据边界

旧 GDScript DIRECT16/DIRECT32/PALETTE 后端、注册表、区段与专属测试已删除。运行时体素数据只有 Voxel Tools 原生缓冲区。

静态 Resource 类型和编辑示例移至 game/data/block，保留 UID；正式目录通过离线内容包接入 WorldContent、稳定世界ID、原生生成和外观库，见 [内容包](content_packages.md)。空气为保留空状态，草、泥土、树叶、三轴木头与水来自正式数据；编辑示例不参与注册。见 [地图生成](../world/world_generation.md)。

后续数据模块与目录规划见 [项目结构](../../total_development.md)。此前测量保留在 [历史初筛](../../test/data/reports/block_storage_results_20260916.md)，不再提供旧实现运行命令。

挖掘静态字段：hardness、单一 required_tool_tag、mining_recovery_seconds（默认 30 秒）。对应工具使用独立的 tool_tags 与 mining_speed，详见 [挖掘数据契约](../gameplay/mining.md#制作字段)。损伤进度归 gameplay，不能写回共享 BlockDefinition。
