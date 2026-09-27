# 整体开发进度与架构

最后核对：2026-09-26。此处维护当前状态，历史测试和研究不作为当前功能承诺。开发规则见 [AGENTS](AGENTS.md)，资源契约见 [资源规格](docs/resource_specifications.md)。

## 当前可玩闭环

F5 进入主菜单，可在左下角切换人物；选择「单人游戏」进入 C++／Voxel Tools 原生世界：平原、森林、河流、海洋；玩家可移动、Ctrl 慢走、Shift 快跑、观察、跳跃、挖掘、放置选中方块，地形变更支持自动保存及正常关闭时保存。玩家已接入 10 槽快捷栏与 30 格储物区、挖掘/放置数量事务和背包恢复日志。尚无地面掉落物、合成、生存规则、生物 AI 或玩家位置/生命值存档。

玩家可在主菜单选择 Basic Voxel 标准素体或导入人物，共用六动作控制器，默认基础第一人称，V 可切回第三人称；第一人称显示同一素体的身体并隐藏头部，尚无独立手臂与持物。主世界接入光影、天气、水面与水下效果，F6 打开设置；世界、网格与派生光照采用 section 缓存和预算提交。细项支持范围以模块文档为准。

## 模块架构

| 模块 | 职责与当前进度 | 详细文档 |
| --- | --- | --- |
| data | 静态方块/流体/物品/玩家容器定义与资源校验；方块已接入 WorldContent | [data](docs/data/README.md) |
| world | 唯一权威体素数据、生成、流式加载、网格/碰撞和地形保存 | [world](docs/world/README.md) |
| entities | 玩家输入、共享运动组件、六动作与形态键混合 | [entities](docs/entities/README.md) |
| shading | 天空日夜、派生光场、水、天气和相机效果；支持范围及待办见模块 | [shading](docs/shading/README.md) |
| gameplay | 物品栏及挖掘/放置数量事务、恢复日志已实现；合成/生存未实现 | [gameplay](docs/gameplay/README.md) |
| core | 主场景组装与场景局部缓存策略、协调器 | [core](docs/core/README.md) |
| ui | 光影设置、帧时间 HUD、颜色选择与水下滤镜层级 | [ui](docs/ui/README.md) |
| tooling | Godot、MCP、构建与验证工具 | [tooling](docs/tooling/README.md) |

core 组装各模块；gameplay 调用 world/entities；世界、实体及光影消费静态数据。data 引用 shading 的只读外观 Resource，不依赖光影运行服务。网格、碰撞和光照是世界数据的派生结果，不能成为第二份权威体素状态。

C++ 承担体素基础设施热路径，GDScript 承担玩法编排、UI 和测试驱动；后台工作不修改活动场景树。源码布局见 [目录说明](docs/core/source_layout.md)。

## 当前边界与下一阶段

- 仅支持当前接口、配置和存档格式；无旧实现别名或迁移读取器。
- 当前生成高度为 [-64,192)，并非最终世界规模决定；视角、多人模式和长期进程设计仍待明确。
- 材质 normal/ORM/emission 贴图和混合透明方块仍待接入；水下折射等需求见光影待办。
- 后续围绕已批准的小闭环推进；尚未独立模块化的交互不因目录存在而视作已完成。
- 自动检查、图形检查、人工手感和性能验收分别记录。历史性能数字不外推为当前保证。

## 文档与证据

模块 README 给出详细状态和专题入口；模块 tmp 保存参与 Git 的研究资料，不能覆盖正式契约。版本化测试证据位于 test/<测试项>/reports，原始日志及生成内容位于根 tmp。

真实基准工程暂保留 benchmarks/voxelgame，属于明确的历史目录例外，不是新增测试内容的默认位置。

物品栏当前闭环与限制见 [物品栏](docs/gameplay/inventory.md)；样板入口 test/inventory/scenes/inventory_sample.tscn。

创造背包已接入分类标签、右上搜索、右下储物栏；左键取一个、中键取一组至独立鼠标堆叠，点击放入、关闭直接移除。完整生存/创造模式规则尚未实现。

人物选择闭环已接入：主菜单左下角入口 → 内置人物与用户 GLB 扫描／按钮导入 → 可滚动列表与动画预览 → 保存选择 → 进入世界实例化。只支持主菜单选择，游戏内不替换实体模型；详见 [UI](docs/ui/README.md#人物选择菜单) 与 [entities](docs/entities/character_entities.md#人物选择与实例化)。

项目业务文件统一保存在项目目录：external_data/characters 与 external_data/blocks 为外部导入资源，runtime_data/settings.cfg、runtime_data/worlds 与 runtime_data/logs 为设置、存档和应用日志；不读取系统用户目录。约定及数据搬迁说明见 [本地数据目录](docs/core/local_storage.md)。
