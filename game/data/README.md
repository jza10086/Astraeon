# 静态数据定义

`block/gdscript/` 保存方块与有限状态 Resource 类型，`block/resources/block_catalog.tres` 收集本批四种正式定义。`fluid/gdscript/` 保存流体定义，`fluid/resources/astraeon_water.tres` 定义水。key 是稳定内容 ID，采用 `astraeon_xxx`，不是原生体素整数 ID。

| ID | 定义 | 硬度 | 逻辑透光阻挡 |
| --- | --- | --- | --- |
| astraeon_grass | 草方块，绿顶、土底、草土色侧面 | 0.6 | 15 |
| astraeon_dirt | 泥土方块 | 0.5 | 15 |
| astraeon_leaves | 树叶，当前为实心绿色立方体，有碰撞 | 0.2 | 1 |
| astraeon_log | 木头，axis_x / axis_y / axis_z，默认 axis_y | 2.0 | 15 |
| astraeon_water | 水，无固体碰撞 | 不适用 | 1 |

所有外观引用 shading 的共享资源。逻辑碰撞与透光不由视觉透明度推断。这些是可调整的初始数据；树叶镂空贴图、树叶衰减、水流模拟不在本批范围。

状态 orientation 是允许状态的只读旋转模板，标准轴为上 +Y、前 -Z、右 +X。世界实例选择状态，渲染调用 appearance 的方向接口时传入该状态的 orientation，先应用 authoring_orientation 再应用状态旋转。不得修改共享模板。木头两端沿所选轴；正负轴对当前对称原木等价。普通方块 states 为空时使用隐式 default/单位旋转。

正式目录已由 WorldContent 在启动时编译为共享 ID 表和渲染库，并用于原生生成与存档校验。当前接入纯色方块与统一水色，详见 `../../docs/world_generation.md`。`example_catalog.tres` 是既有编辑示例，不与正式目录合并注册。测试位于 `test/data/`，临时输出归 tmp；不迁移其他模块测试。详见 `../../docs/project_structure.md`。
