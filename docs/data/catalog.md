# 正式静态数据目录

以下相对源码路径以 game/data 为基准。

`block/gdscript/` 保存方块与有限状态 Resource 类型；`content/authoring/astraeon/pack.tres` 是原版包工程。`blocks/` 下五个完整单文件方块内嵌逻辑、外观和对应物品，`items/` 保存剑/铲/镐/斧，`fluids/water.tres` 保存水体。key 是稳定内容 ID，采用 `astraeon:xxx`，不是原生体素整数 ID。

| ID | 定义 | 硬度 | 逻辑透光阻挡 |
| --- | --- | --- | --- |
| astraeon:grass | 草方块，绿顶、土底、草土色侧面 | 0.6 | 15 |
| astraeon:dirt | 泥土方块 | 0.5 | 15 |
| astraeon:leaves | 树叶，棋盘裁剪贴图、50% 像素透明，仍有完整方块碰撞 | 0.2 | 1 |
| astraeon:log | 木头，axis_x / axis_y / axis_z，默认 axis_y | 2.0 | 15 |
| astraeon:glowstone | 发光石，纯白自发光与白色光源描述 | 1.5 | 15 |
| astraeon:water | 水，无固体碰撞 | 不适用 | 1 |

所有外观使用 shading 的资源类型，参数内嵌于完整方块文件；源图片以包工程索引关联。逻辑碰撞与透光不由视觉透明度推断。这些是可调整的初始数据；树叶已支持镂空贴图；树叶衰减、水流模拟不在本批范围。

状态 orientation 是允许状态的只读旋转模板，标准轴为上 +Y、前 -Z、右 +X。世界实例选择状态，渲染调用 appearance 的方向接口时传入该状态的 orientation，先应用 authoring_orientation 再应用状态旋转。不得修改共享模板。木头两端沿所选轴；正负轴对当前对称原木等价。普通方块 states 为空时使用隐式 default/单位旋转。

正式目录离线编译为内容包，WorldContent 在启动时读取定义装配共享渲染库；ID由世界持久化注册表维护，见 [内容包](content_packages.md)。当前接入不透明/裁剪颜色贴图方块、常量自发光及共享水外观基础参数，详见 [地图生成](../world/world_generation.md)。`test/data/resources/` 的 catalog 是低层 Resource 测试夹具，不参与正式世界注册。测试位于 `test/data/`，临时输出归 tmp；不迁移其他模块测试。详见 [整体架构](../../total_development.md)。

工具玩法标签独立于 search_tags：tool_tags 可包含多个命名空间 ID，mining_speed 默认为 1 耐久度/秒；方块只配置一个 required_tool_tag。详见 [当前挖掘规则](../gameplay/mining.md)。
