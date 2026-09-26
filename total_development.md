# 整体开发进度与架构

最后核对：2026-09-26。此处维护当前状态，历史测试和研究不作为当前功能承诺。开发规则见 [AGENTS](AGENTS.md)，资源契约见 [资源规格](docs/resource_specifications.md)。

## 当前可玩闭环

F5 启动 C++／Voxel Tools 原生世界：平原、森林、河流、海洋；玩家可移动、Ctrl 慢走、Shift 快跑、观察、跳跃、挖掘、放置泥土，地形变更支持自动保存及正常关闭时保存。尚无背包事务、掉落物、合成、生存规则、生物 AI 或玩家状态存档。

玩家使用 Basic Voxel 标准素体及六动作控制器，默认基础第一人称，V 可切回第三人称；第一人称暂不显示手臂、身体和持物。主世界接入光影、天气、水面与水下效果，F6 打开设置；世界、网格与派生光照采用 section 缓存和预算提交。细项支持范围以模块文档为准。

## 模块架构

| 模块 | 职责与当前进度 | 详细文档 |
| --- | --- | --- |
| data | 静态方块/流体定义、有限状态与资源校验；已接入 WorldContent | [data](docs/data/README.md) |
| world | 唯一权威体素数据、生成、流式加载、网格/碰撞和地形保存 | [world](docs/world/README.md) |
| entities | 玩家输入、共享运动组件、六动作与形态键混合 | [entities](docs/entities/README.md) |
| shading | 天空日夜、派生光场、水、天气和相机效果；支持范围及待办见模块 | [shading](docs/shading/README.md) |
| gameplay | 挖掘/放置已存在，当前仍由世界脚本编排；背包/合成/生存未实现 | [gameplay](docs/gameplay/README.md) |
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
