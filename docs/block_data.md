# 当前方块数据边界

旧 GDScript DIRECT16/DIRECT32/PALETTE 后端、注册表、区段与专属测试已删除。运行时体素数据只有 Voxel Tools 原生缓冲区。

静态 Resource 类型和编辑示例移至 game/data/blocks，保留 UID；这些模板尚未编译到原生注册表。实际生效的六种方块定义见 [原生后端](native_voxel_backend.md)。

后续数据模块与目录规划见 [项目结构](project_structure.md)。此前测量保留在 [历史初筛](block_storage_results_20260916.md)，不再提供旧实现运行命令。
