# ASTRAEON
Godot 4.7 体素生存建造游戏。

## 当前状态
已初始化开发环境：MCP 编辑器插件、Codex 配置、项目技能、开发规范、功能目录和 F6/F5 可启动的 3D 占位场景。
占位地面并非体素世界；尚未实现移动、挖掘、建造、背包、存档或生存规则。预览相机不代表最终游戏视角。

## 打开与验证
使用 Godot 4.7 stable 导入 project.godot，F5 运行入口 game/core/main.tscn。
在项目根目录运行：
~~~powershell
./tools/check.ps1
~~~
该命令检查引擎版本、完整导入、主场景短时启动及 Git 元数据；日志写入 tmp/。
完整导入会写入 .godot/ 和 Godot 用户数据，受平台权限约束。自动检查不能替代画面与交互的人工验收。

## 目录
- game/core/：应用入口与场景组装。
- game/world/、player/、survival/、inventory/、building/、crafting/、ui/：按功能组织场景、脚本和专用资源。
- shared/、autoload/、assets/：实际需要的共享代码、全局服务和共享资源。
- addons/：第三方插件；tests/：后续功能测试；docs/：设计和环境文档。
- .agents/skills/：项目内技能；.codex/config.toml 和 .mcp.json：MCP 客户端配置。
- tools/：开发脚本；tmp/：Git 忽略且 Godot 不导入的临时输出。

先阅读 AGENTS.md；MCP 的连接与迁移说明见 docs/development.md。

## voxelgame 基准工程
已安装独立voxelgame与Voxel Tools 1.7扩展。当前基准采用水平16区块（256体素）圆形半径与独立垂直范围；区块定义、坐标和加载契约见 [区块文档](docs/voxel_chunks.md)。主游戏仍为占位场景，不依赖嵌套工程的res://。

圆形加载原生检查已通过。性能测试按用户要求停止：19项完整完成，限帧编辑中断，限帧移动未启动；128方块编辑三轮通过，静态和移动未全面达标。详见 [圆形加载结果](docs/voxelgame_circular_performance_20260913.md)。

运行方法见 [测试说明](docs/voxelgame_benchmarks.md)。历史资料：[盒形性能结果](docs/voxelgame_performance_20260913.md)、[初期执行记录](docs/voxelgame_benchmark_results_20260913.md)。此前Duet WinTab退出崩溃已在卸载重启后消除。

## P0 光照样板

独立评估工程已增加 64³ 光照样板：天空光/单色方块光增量传播、太阳/月亮直射与阴影、天空色彩、固定曝光，以及开闭屋顶/窗口和放置光源的交互。自动正确性检查与实际 D3D12 渲染/脚本驱动编辑检查通过，完整键鼠人工验收和性能测试待进行。主游戏状态不变；启动与边界见 [P0 光照文档](docs/lighting_p0.md)。

## P1 / P2 模块化光影

独立样板已加入可调 AO、距离雾、FXAA/TAA、阴影档位、静态水面与水下效果、植被风动/透光、简化体积云和可选 Bloom。水面采用单次深度吸收，发光方块使用带阴影点光源与弱补光；另有硬/软阴影、模糊半径、日月阴影分辨率、FPS 显示与限帧设置。分组设置支持保存和恢复默认；实机组合检查与多分辨率截图完成。范围、验证和已知近似见 [P1/P2 文档](docs/lighting_p1_p2.md)。最新新增环境光平滑参数，以及方块体积云与仅日月直射的简单云影分支，详见 [环境光与云分支](docs/lighting_environment_clouds_20260915.md)。未进行正式性能基准。

水面现已增加颜色、吸收、波纹、高光、水下参数及可独立关闭的专用 SSR（三档质量），详见 [水面调节与反射](docs/lighting_water_20260915.md)。

最新更新：已实现平面反射，并将质量档位拆为显式参数（SSR 步数、反射分辨率 / 更新频率、阴影滤波采样等），详见 [平面反射与调节说明](docs/lighting_planar_reflections_20260915.md)。
