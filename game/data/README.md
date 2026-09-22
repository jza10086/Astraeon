# 静态数据定义

blocks/gdscript/ 保存 Resource 类型，blocks/resources/ 保存编辑示例，不保存逐体素运行状态。example_catalog.tres 尚未接入原生世界；实际生效方块库为 game/world/resources/block_library.tres。设计见 ../../docs/project_structure.md；测试统一目标为 test/data/，现有测试迁移由模块 agent 负责。

方块静态逻辑定义后续引用 shading 的共享外观资源；不在 data 重复定义材质字段，也不将当前朝向、坐标等实例状态写入模板。已批准但尚未接入的材质契约见 [方块规格](../../docs/voxel_chunks.md#方块属性与材质契约)。
