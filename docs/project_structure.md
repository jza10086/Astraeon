# 当前模块与目录规范

生产内容按功能归入 game，光影模块统一命名 shading。项目 C++ 与 GDScript 同属业务模块，但放在分开的子目录。此结构已落实；光影样板及其工具、报告已迁入 test/shader，其余现有测试由对应模块逐步迁移。

```text
Astraeon/
├─ game/
│  ├─ core/main.tscn                     # 应用入口与装配
│  ├─ data/block/
│  │  ├─ gdscript/                      # Resource 类型
│  │  └─ resources/                     # 静态配置、编辑示例
│  ├─ data/fluid/                       # 流体类型与静态水定义
│  ├─ world/
│  │  ├─ gdscript/native_world.gd        # 当前世界编排
│  │  ├─ gdscript/world_content.gd      # 从正式定义构建共享 ID 与外观库
│  │  └─ native/                        # .gdignore，仅项目 C++
│  │     ├─ generation/
│  │     ├─ persistence/
│  │     └─ streaming/
│  ├─ entities/
│  │  ├─ common/gdscript/               # 共享移动与动画组件
│  │  └─ player/
│  │     ├─ gdscript/                   # 输入、相机
│  │     ├─ scenes/player.tscn
│  │     └─ assets/hk416.glb
│  ├─ shading/                          # 可复用光影组件；正式世界接入待开发
│  ├─ gameplay/
│  │  ├─ interaction/                   # 挖掘/放置职责
│  │  ├─ inventory/
│  │  ├─ crafting/
│  │  └─ survival/
│  └─ ui/
├─ native/
│  ├─ voxel_tools/                      # 上游代码及必要接入补丁
│  ├─ deps/godot-cpp/
│  └─ dependency_lock.json
├─ addons/zylann.voxel/                 # 扩展描述与部署二进制
├─ test/                               # 新统一测试目录，见下文
├─ tools/                              # 生产构建与开发工具
├─ docs/                               # 架构、接口、开发规范
└─ tmp/                                # 忽略的临时输出
```

## 模块职责与依赖

| 模块 | 拥有的内容 |
| --- | --- |
| data | 静态方块、物品、生物、群系定义和校验；不是逐体素运行时存储 |
| world | 权威体素数据、生成、流式调度、读写存档、网格和地形碰撞 |
| entities | 共享移动组件、玩家/生物实例、行为、模型、动画 |
| shading | 天空、日夜、环境、阴影、水面、云、后处理和未来原生光照计算 |
| gameplay | 目标选择、挖掘/放置及未来背包、合成、生存规则 |
| core / ui | 组装、生命周期、设置、菜单与显示 |

core 装配模块；gameplay 调用 world 和 entities；世界、实体和光影读取 data。加载决定哪些区段驻留，读取是 persistence 的磁盘操作；缺失才生成，损坏必须报错。世界数据是唯一权威源，网格/碰撞/光影都是派生内容。动画只消费实体状态，不直接决定地形修改或持久化。

尚未实现的职责不等于已经独立组件化：当前挖掘/放置、简单提示仍在 native_world.gd 内，后续可提取到 gameplay/interaction/gdscript 与 ui/gdscript；本次未改变玩法行为。正式数据目录已接入原生生成与基础外观编译；完整光影效果仍待开发。只为已实现功能增加代码，不为目录完整预建空框架。

## 同模块语言分层

功能模块一般采用 gdscript/、native/、scenes/、resources/、assets/、shaders/，按实际需要建立。大模块可先按功能分层，例如 entities/player/gdscript。C++ 继续负责体素热路径，GDScript 负责编排、界面和测试驱动。

所有项目自编原生类的源文件位于 game/<module>/native。构建工具同步到 tmp/native-build/voxel_tools/astraeon/<module>，生成显式源文件清单，并与上游编译为同一扩展。该 tmp 路径仅为构建输出，不是可编辑源码。未列入清单的旧文件不能参与编译。使用上游源码根目录 include 路径，避免依赖旧 astraeon 目录深度。

Voxel Tools 的注册、调度或圆形加载等上游接入补丁仍在 native/voxel_tools 中。依赖不复制进 game；DLL 不提交。构建指纹分别记录上游源码与项目模块源码。移动代码不改变现有存档格式，也不新增旧路径适配。

## 统一测试目录

新目录 test/ 与 game/ 同级。今后所有测试代码、测试场景、样板/演示、基准、夹具、测试专属资源/资产、测试运行器和需版本化的报告都放在 test/<module>/。可按需要细分 gdscript/、native/、scenes/、fixtures/、resources/、assets/、runners/、reports/。

光影样板、光影专属测试、运行器和历史报告已迁入 test/shader/，运行组件位于 game/shading/，不保留 astraeon_lighting 目录别名。其他 tests/、benchmarks/ 和角色测试暂未批量迁移；角色固定碰撞夹具仍位于 tests/entities/fixtures。

临时结果、测试存档、日志与编译二进制仍写 tmp，不提交到 test。迁移需保留 UID、更新所有调用并验证，禁止保留旧路径兼容副本或别名。

## 生效位置

硬性开发规则位于根 AGENTS.md 的 Modules and directories 节。各模块 README 说明其当前实现边界；本文件是实际目录和职责说明，不再采用此前的 game/lighting 或顶层 astraeon 项目源码布局。

## 本次验证

编辑器现有进程已完成完整资源扫描/导入；编辑器版与 template_release 原生扩展编译通过。资源引用检查、移动前后 UID 一致性和模型内容哈希验证通过；Resource 与玩家场景加载成功，原生合约 17 项通过，528 帧短烟测无失败。实际主场景已启动并确认出生碰撞就绪。未运行新的性能矩阵或迁移现有测试内容。

## 已批准的方块外观边界

材质设计见 [方块规格](voxel_chunks.md#方块属性与材质契约)，与 1 单位 = 1 米的方块尺寸约定共同生效。shading 拥有 BlockAppearance、BlockSurface、BlockLightAppearance 的类型和资源；data 的静态逻辑定义引用这些只读资源，world/gameplay 提供实例位置、当前朝向及动态显示参数。该引用是静态资源依赖，不创建 data 到光影运行服务的依赖，也不允许外观资源反向持有逻辑实例。Resource 类型、校验和方向接口已实现于 game/shading/blocks，测试归入 test/shader；纯色不透明方块和统一水色已接入启动期共享编译；其他外观特性仍待接入。

## 当前方块与流体数据

静态定义使用 game/data/block 与 game/data/fluid，ID 为 astraeon_xxx。方块目录收录草、泥土、树叶、三轴木头，流体目录定义水；外观类型与共享材质仍归 shading。木头状态保存允许的旋转，世界实例只选择状态。具体入口和当前接入边界见 game/data/README.md。

地图生成版本 2 及数据接入边界见 [地图生成](world_generation.md)。
