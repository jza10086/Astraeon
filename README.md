# ASTRAEON
Godot 4.7 体素生存建造游戏。

## 当前状态
主世界已接入光影装配，F6 打开设置；接口与验证边界见 [主世界光影](docs/world_shading.md)。
已初始化开发环境：MCP 编辑器插件、Codex 配置、项目技能、开发规范、功能目录和 F5 可启动的原生体素主场景。
静态方块 Resource 类型与编辑示例位于 `game/data/block/gdscript/` 与 `resources/`，已关联 game/shading/blocks 下的共享外观 Resource（六面材质、标准朝向、自发光及独立光源描述），正式目录已接入原生生成与基础渲染，编辑示例不参与注册；见 [方块材质规格](docs/voxel_chunks.md#方块属性与材质契约)。旧 GDScript 体素后端及专属测试已删除，仅保留历史测试报告。模块与目录规划见 [项目结构](docs/project_structure.md)。
主场景已接入玩家实体：WASD 移动、鼠标观察、空格跳跃、碰撞和 HK416 的 Idle/Run/Jump 动画。主场景现使用 C++ 原生四生物群系地形，支持左键挖掘、右键放置泥土和地形保存；尚未接入背包、玩家状态存档或生存规则。第三人称测试相机不代表最终游戏视角。模块说明见 [角色实体](docs/character_entities.md)，资产交付约定见 [模型约定](docs/character_asset_contract.md)。
历史地图实验的实现与专属运行器已删除；历史记录见 [综合测试报告](docs/world_suite_results_20260917.md)。当前世界仅使用 C++ 后端。

生产体素底层已确定采用 **C++／Voxel Tools GDExtension 二次开发**，GDScript 用于玩法编排、UI、场景接入和测试驱动。首版原生生成、网格/碰撞、预测预加载与双副本 Region 保存已接入主场景；旧 GDScript 实验已删除，仅保留历史测量资料。源码位置和职责见 [C++ 体素底层](docs/native_voxel_backend.md)。

**当前处于原型阶段，不保留任何向后兼容内容。**接口、配置和存档只支持当前契约，不维护旧接口别名、兼容适配、旧格式读取或迁移转换；变更时同步更新调用方、资源、测试和文档。不支持的格式明确拒绝读取。

## 打开与验证
新检出先按 [原生构建说明](docs/native_voxel_backend.md) 构建扩展，再使用 Godot 4.7 stable 导入 project.godot，F5 运行入口 game/core/main.tscn。DLL 不纳入 Git。
在项目根目录运行：
~~~powershell
./tools/check.ps1
~~~
该命令检查引擎版本、完整导入、主场景短时启动及 Git 元数据；日志写入 tmp/。
完整导入会写入 .godot/ 和 Godot 用户数据，受平台权限约束。自动检查不能替代画面与交互的人工验收。

## 目录
- game/core/：应用入口与场景组装。
- game/data/、world/、entities/、shading/、gameplay/、ui/：按功能组织；GDScript 与项目 C++ 分别位于模块内 gdscript/、native/。
- shared/、autoload/、assets/：实际需要的共享代码、全局服务和共享资源。
- addons/：第三方插件；test/：统一测试目标目录（现有测试由模块 agent 后续迁移）；docs/：设计和环境文档。
- .agents/skills/：项目内技能；.codex/config.toml 和 .mcp.json：MCP 客户端配置。
- tools/：开发脚本；tmp/：Git 忽略且 Godot 不导入的临时输出。

先阅读 AGENTS.md；MCP 的连接与迁移说明见 docs/development.md。

## voxelgame 基准工程
已安装独立voxelgame与Voxel Tools 1.7扩展。当前基准采用水平16区块（256体素）圆形半径与独立垂直范围；区块定义、坐标和加载契约见 [区块文档](docs/voxel_chunks.md)。主游戏使用根目录原生扩展，不依赖嵌套工程的res://。

圆形加载原生检查已通过。性能测试按用户要求停止：19项完整完成，限帧编辑中断，限帧移动未启动；128方块编辑三轮通过，静态和移动未全面达标。详见 [圆形加载结果](docs/voxelgame_circular_performance_20260913.md)。

运行方法见 [测试说明](docs/voxelgame_benchmarks.md)。历史资料：[盒形性能结果](docs/voxelgame_performance_20260913.md)、[初期执行记录](docs/voxelgame_benchmark_results_20260913.md)。此前Duet WinTab退出崩溃已在卸载重启后消除。

## P0 光照样板

2026-09-22 当前入口已迁移至 `test/shading/scenes/shading_sample.tscn`，可复用组件在 `game/shading/`。新增光束、SSAO、彩色透明阴影、自动曝光、雨天湿润、色彩、镜头效果、移动灯与材质光泽已接入代码；根工程导入、核心逻辑、独立 GPU 编译及 513 项短时组合检查通过，四种分辨率截图已生成；正式性能与完整键鼠人工验收另行进行。启动和边界见 [当前光影样板说明](test/shading/README.md)。下文保留前序阶段的验收与性能记录。

独立评估工程已增加 64³ 光照样板：天空光/单色方块光增量传播、太阳/月亮直射与阴影、天空色彩、固定曝光，以及开闭屋顶/窗口和放置光源的交互。自动正确性检查与实际 D3D12 渲染/脚本驱动编辑检查通过，完整键鼠人工验收和性能测试待进行。主游戏状态不变；启动与边界见 [P0 光照文档](test/shading/reports/lighting_p0.md)。

## P1 / P2 模块化光影

独立样板已加入可调 AO、距离雾、FXAA/TAA、阴影档位、静态水面与水下效果、植被风动/透光、方块体积云和可选 Bloom。水面采用单次深度吸收，发光方块使用带阴影点光源与弱补光；另有硬/软阴影、模糊半径、日月阴影分辨率、FPS 显示与限帧设置。分组设置支持保存和恢复默认；实机组合检查与多分辨率截图完成。范围、验证和已知近似见 [P1/P2 文档](test/shading/reports/lighting_p1_p2.md)。最新新增环境光平滑参数，以及方块体积云与仅日月直射的简单云影分支，详见 [环境光与云分支](test/shading/reports/lighting_environment_clouds_20260915.md)。独立样板的设置成本测试结果见下文。

水面现已增加颜色、吸收、波纹、高光、水下参数及可独立关闭的专用 SSR（三档质量），详见 [水面调节与反射](test/shading/reports/lighting_water_20260915.md)。

最新更新：已实现平面反射，并将质量档位拆为显式参数（SSR 步数、反射分辨率 / 更新频率、阴影滤波采样等），详见 [平面反射与调节说明](test/shading/reports/lighting_planar_reflections_20260915.md)。

样板新增最低环境光、动画测试人物、固定批量光源按钮，以及五种局部照明方案；具体操作和近似边界见 [局部光源方案与人物测试](test/shading/reports/lighting_local_schemes_20260915.md)。

最新设置界面采用一级分类和二级模块菜单，方案切换仅显示有效参数；方块自发光倍率已修复，写实简化体积云已删除。当前配置不读取旧格式。见 [设置菜单与自发光修正](test/shading/reports/lighting_settings_menu_20260918.md)。

1080p 光影设置成本测试已完成首轮及附加档位补测：分别耗时 56 分 8 秒、8 分 4 秒，覆盖 98 个可评级设置、166/166 对照用例，累计 18 组复测。测试期间存在温控限频，多数细小差异仍为待定，详见 [结果与完整表格](test/shading/reports/lighting_performance_results_20260918.md)。脚本默认仅预览，矩阵、指标、时间预算及启动方式见 [光影性能测试方案](test/shading/reports/lighting_performance_suite.md)。

当前地图使用平原、森林、河流、海洋生成版本 2，正式 data/block 与 data/fluid 目录已接入原生生成、共享外观编译和存档校验。详见 [地图生成](docs/world_generation.md)。

当前数据驱动光影入口为 `test/shading/scenes/content_sample.tscn`，复用正式方块数据及人物，包含棋盘叶片和白色发光石；原完整参数样板仍为同目录下 `shading_sample.tscn`。

## 主世界光影接入（2026-09-23）

主场景已装配当前光影模块，F6 打开设置。世界数据仍由 C++ 体素后端管理，光场为只读快照的派生结果；现有样板继续作为对比工具。详细接口、验证及性能边界见 [主世界光影](docs/world_shading.md)。此前独立样板阶段的“未接入”描述属于历史记录。
