# 项目模块与目录设计

本次已执行：删除旧 GDScript 体素后端及专属测试、运行器；保留原生后端；将静态方块 Resource 类型和示例移至 `game/data/blocks/`。以下其余目录是设计目标，尚未实施整库搬迁，也不预建空模块。

## 模块边界

| 模块 | 职责 | 不负责 | 当前状态 |
| --- | --- | --- | --- |
| 数据定义与样板 data | 方块、物品、生物、群系等静态定义，稳定键、字段校验、示例与预览 | 不保存逐个体素、生命值、背包等运行状态 | 有方块 Resource 模板及示例；尚未接入原生注册表 |
| 世界 world | 地形生成、流式调度、加载与卸载、存档读取/保存、体素编辑、派生网格/地形碰撞 | 不直接读取键鼠，不决定掉落或消耗物品 | 已有 C++ 首版与 GDScript 场景编排 |
| 实体与动画 entities | 共享移动/碰撞、生命等实例状态、动画参数和模型；玩家与生物组成实体 | 动画不修改地形或存档；共享移动器不读取玩家键鼠 | 有角色移动、动画和玩家控制；AI 未实现 |
| 光影 lighting | 日夜、环境、材质、阴影、水面、云、后处理、质量设置；未来方块光传播 | 不维护第二份权威方块世界，不生成地形 | 独立样板在嵌套基准工程，尚未整体接入主世界 |
| 交互与玩法 gameplay | 选中、挖掘、放置，以及以后背包/合成/生存规则 | 不直接操作 Region 文件或重新实现体素数组 | 挖掘/放置暂在世界编排脚本，后续拆出 |
| 应用与界面 core / ui | 主场景装配、进入/退出世界、设置菜单、HUD、保存失败提示 | 不执行逐体素算法 | 已有主场景与简单提示 |

“数据样板”分成两部分：`game/data` 保存可复用类型与正式静态内容；`samples/data` 将来放演示场景和预览操作。Resource 类型使用 GDScript 是编辑器配置层，不是被删除的 GDScript 运行时体素后端。

## 推荐目标目录

```text
Astraeon/
├─ game/
│  ├─ core/                         # main、启动/退出、模块装配
│  ├─ data/
│  │  ├─ blocks/                    # 类型、状态定义、方块目录
│  │  ├─ items/                     # 实际开发物品时再创建
│  │  ├─ entities/                  # 生物静态定义
│  │  └─ biomes/                    # 群系配置
│  ├─ world/
│  │  ├─ world.tscn / world.gd      # 原生节点组装与世界级配置
│  │  ├─ profiles/                  # 世界配置 Resource 实例
│  │  └─ materials/                 # 地形块模型库、专用材质
│  ├─ entities/
│  │  ├─ common/                    # 共享 motor、visual、动画约定
│  │  ├─ player/                    # 玩家场景、输入与相机
│  │  └─ creatures/<name>/          # 每种生物场景、行为、模型、动画
│  ├─ lighting/
│  │  ├─ environment/               # 日夜、天空、雾、曝光
│  │  ├─ shadows/                   # 阴影配置与控制
│  │  ├─ water/                     # 水面和反射
│  │  ├─ clouds/                    # 云与云影
│  │  ├─ post_process/              # 后处理
│  │  └─ profiles/                  # 质量与环境预设
│  ├─ gameplay/
│  │  ├─ interaction/               # 目标选择、挖掘、放置
│  │  ├─ inventory/                 # 按实际功能逐步增加
│  │  ├─ crafting/
│  │  └─ survival/
│  └─ ui/                           # HUD、设置、菜单
├─ native/
│  ├─ voxel_tools/                  # 固定版本的 Voxel Tools 源码
│  │  └─ astraeon/                  # 项目自编 C++，与上游一起构建
│  │     ├─ data/                   # 未来的原生静态注册表与校验
│  │     ├─ world/
│  │     │  ├─ generation/          # 生成器
│  │     │  ├─ streaming/           # viewer、调度、预加载
│  │     │  └─ persistence/         # Region 读取、写入、校验、恢复
│  │     └─ lighting/               # 未来的方块光传播等重计算
│  ├─ deps/godot-cpp/
│  └─ dependency_lock.json
├─ addons/zylann.voxel/             # 构建部署产物入口，DLL 不入库
├─ samples/                        # 可独立启动的模块演示；不是后备实现
│  ├─ data/
│  ├─ world/
│  ├─ entities/
│  └─ lighting/
├─ tests/                          # 按 data/world/entities/lighting 分类
├─ tools/                          # 构建、测试、报告工具
├─ docs/                           # 架构、契约、实测报告
├─ benchmarks/                     # 保留原生/光影评估及历史数据
└─ tmp/                            # 临时构建、测试存档、日志；不入库
```

这是同一模块在编辑器层和原生层的分工，不是两套世界实现。C++ 热路径放在 `native`；场景、配置和轻量编排放在 `game`。不单独建立第二个 C++ 世界插件，避免跨 GDExtension ABI 和重复类注册。

## 世界模块内的流程

1. 流式加载根据 viewer、水平/垂直范围决定需要哪些区段，并安排优先级、取消过期请求。
2. 存档读取检查当前格式和校验和；存在则加载，不存在才生成。损坏不等于不存在，不能自动生成覆盖修改。
3. 生成器由种子、生成版本、配置产生原生体素数据；生成不创建活动场景节点。
4. 网格和碰撞从同一权威体素数据派生，后台准备、主线程受预算提交。
5. 玩法编辑通过原生区域/单块接口修改数据、标记脏段，再触发网格/碰撞更新。
6. 保存获取一致快照，进入写入队列，校验并持久化；退出协调等待实际完成，向 UI 报错。

因此“加载”和“读取”不另立两个顶层模块：加载是流式生命周期管理，读取是持久化后端的一项操作。保存与读取共同拥有格式契约，避免两份不同的版本或 ID 映射规则。

## 依赖与数据所有权

`core` 装配各模块；`gameplay` 调用 `world` 和 `entities`；世界、实体、光影读取静态 `data`；`ui` 展示状态并提交操作请求。世界模块不依赖某个玩家节点、HUD 或具体生物。多个观察者通过 viewer 接口提供需求。

- 静态 Resource 共享，只读；原生注册表未来在世界启动时批量校验/编译，固定后供工作线程查询。
- 逐体素权威状态只有原生世界一份。光影需要采样时使用受控区域快照/查询，不自建一份长期世界镜像。
- 实体运行状态归实体实例；动画层消费运动/行为参数。AI 和玩家输入分别产生移动意图。
- 当前体素存档只保存区段。未来生物、玩家和背包应有独立快照/文件，由世界会话协调，不塞进 Region 体素记录。
- UI、场景提交在主线程；重计算和磁盘 I/O 在原生工作线程。
- 未来原生注册表接入时同步更新生成器、网格库和当前存档契约，拒绝不支持的格式，不增加旧格式转换。

## 当前到目标的迁移顺序

| 当前路径 | 目标 | 本次处理 |
| --- | --- | --- |
| `game/world/blocks` 里的 Resource 定义 | `game/data/blocks` | 已移动，UID 保留 |
| `game/world/native` | `game/world` 与其 profiles/materials | 保持现状，后续拆编排与交互后迁移 |
| `game/entities`、`game/player` | `game/entities/common`、`game/entities/player` | 保持现状，避免模型/动画 UID 无必要变化 |
| `native/voxel_tools/astraeon/*.cpp` | 同目录下按 data/world/lighting 分组 | 仅设计；迁移时同步 SConstruct，目前 Glob 只收集直属 cpp |
| `benchmarks/voxelgame/project/astraeon_lighting` | 正式实现进 game/lighting，演示进 samples/lighting | 保留当前样板；先替换其自有 sample_world 接口再迁入 |
| `tests/native_world` | `tests/world` | 保持现状；后续统一测试命名时更新运行器 |

先拆当前 `native_world.gd` 中的交互与界面，再整理实体目录，最后接入光影。模型与专用材质随功能放置，跨模块共享资产才进入统一 assets。不要为未实现的物品、AI、联网提前建立服务、autoload 或通用框架。

## 本次删除范围

删除 DIRECT16/DIRECT32/PALETTE GDScript 存储、GDScript 注册表/区段、旧生成/持久化/工作器/网格器，及其专属 tests/blocks、tests/world 和两个 Python 运行器。历史报告与原始归档保留；原生代码、原生测试、角色和光影样板保留。旧代码需要考古时从 Git 历史查看，不在当前工程保留兼容路径。

`game/data/blocks/example_catalog.tres` 仍是独立编辑示例，包含实验方块；它不驱动原生世界。当前真正生效的是原生固定六类 ID 与 `game/world/native/block_library.tres`。数据模板接入原生注册表属于下一步开发，不能将编辑示例当作已生效游戏配置。

## 清理后验证

游戏与测试输入资源路径检查通过；移动后的 Resource 示例实际加载通过；原生数据合约 17 项通过；原生世界短烟测包含连续编辑保存、移动及传送，444 帧、无失败和脚本/引擎错误。该短测用于确认删除未破坏接入，不作性能排名。
