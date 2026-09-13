# voxelgame 安装与性能测试准备

状态：仅准备；尚未运行性能测试。后续必须得到用户的运行指令。

## 安装
独立工程：benchmarks/voxelgame/project/project.godot。
主游戏的 MCP 和 project.godot 不受影响。benchmarks/.gdignore 防止主工程扫描嵌套项目。
- voxelgame 固定提交：4cf747a8456375e527c8c976c50fb24446f9d18f
- Voxel Tools：1.7 GDExtension，v1.7x
- 引擎：当前 Godot 4.7.stable.official.5b4e0cb0f
- 下载 URL、压缩包大小和 SHA-256：benchmarks/voxelgame/dependency-lock.json
- 源码、素材、许可证纳入 Git；各平台原生二进制已安装但忽略提交，可用 tools/restore_voxel_dependency.py 按锁文件恢复。
- 上游源码保持独立；改动包括工程名、默认入口、1080p、D3D12、独立用户目录及示例存档路径。上游原始 README 和许可证保留。

## 入口与运行门槛
默认入口是 astraeon_benchmark/benchmark.tscn。打开后仅显示待命 UI，不创建体素地形或 Viewer。
只有点击 Start 或显式传入 --run-benchmark 才开始负载。
四个命名场景 initial_load.tscn、stationary.tscn、streaming.tscn、editing.tscn 可在 Inspector 调整参数；同样默认待命。

在 Astraeon 根目录：
~~~powershell
# 只查看说明
./tools/voxelgame.ps1
# 只导入、解析，不启动游戏；不要在这个嵌套工程已打开时并发执行
./tools/voxelgame.ps1 -Mode Import
# 打开嵌套工程编辑器（不会自动运行性能场景）
./tools/voxelgame.ps1 -Mode Open
~~~

以下命令仅供用户下达运行指令之后使用，本次没有执行：
~~~powershell
# 原版方块游戏菜单：保留单人、联机入口，但本次未验证游戏运行
./tools/voxelgame.ps1 -Mode Demo -Run
# 单项基准；一次一个新进程，完成即退出
./tools/voxelgame.ps1 -Mode Benchmark -Run -Case stationary -Distance 128 -Warmup 15 -Seconds 60
~~~

不带 -Run 的 Demo/Benchmark 命令会立即拒绝，不启动 Godot。
Esc 或关闭窗口会保存部分数据，标记 aborted，不当作成功结果。

## 测试矩阵
初始建议每项 64、128、256 体素视距各运行 3 次，不并发。视距单位是体素，不是区块数。
默认网格区块边长 16；种子 20260913，1920x1080 窗口，Forward+ / D3D12 / Jolt，VSync 关闭、帧率不限。
统一采用环境光与方向光阴影，关闭 SDFGI，开启地形碰撞生成。相机为固定脚本轨迹，无物理玩家。
- initial_load：新建内存世界后立即采样 60 秒。包括生成器初始化和首次加载；不是操作系统缓存清空后的磁盘冷启动。
- stationary：静止预热 15 秒，再静止采样 60 秒。
- streaming：静止预热后，以 x=16t、z=8t、y=56 的路线移动并采样；合速度约 17.9 体素/秒。
- editing：静止预热后，在原点附近跨区块边界的 16x16 地表区域按固定顺序切换空气/泥土，目标 20 次/秒；报告实际执行与跳过数量。
每种负载复用上游方块生成器和 mesher；不运行上游玩家、背包、水流 tick、网络和 UI 逻辑，因此是体素子系统基准，不代表完整游戏 FPS。
测试世界禁用 stream，不读取或写入交互示例存档。交互示例单独存入 user://interactive_demo_save。

## 采样与有效性
- frames.csv：单调时钟记录的逐帧 wall interval；不是 GPU 时间。
- summary.json：平均 FPS、帧时间均值/P50/P95/P99/最大值、超过 33.33ms 与 50ms 的帧数、编辑数量、区块事件数。
- counters.json：每秒 draw calls、图元、Godot 分配器内存和渲染内存估计、VoxelTerrain/VoxelEngine 统计。
- metadata.json：引擎与插件实际版本、插件提交、CPU/GPU、窗口、渲染器、参数和范围说明。
- 数据缓存在内存中，测量结束后写文件；每秒收集统计本身仍有小量开销。
- 中央 32x64x32 区域网格可用时间单独记录。它不等于整个视距完成加载，也不证明碰撞全部就绪。
- stationary/streaming/editing 在预热结束中央区域仍不可用时终止并标记 warmup_incomplete。需要用户决定增加预热时间后重新测量。
- initial_load 在结束时仍无中央网格、editing 没有实际编辑时，结果标记失败。
- 预热为固定时长，不保证所有后台任务排空；分析时结合 engine/terrain 队列统计，不能把尚在生成的 stationary 结果当成纯渲染极限。
- 内存值不是进程 RSS；没有 GPU 利用率与驱动级显存测量。记录真实渲染器而不是把 headless 数值当帧率。
- 初始版本使用同一进程全局种子固定上游树模板，并设置高度噪声 seed；固定代码和版本下才用于重复对比，不承诺跨版本世界兼容。

结果默认位于 tmp/voxel-bench-results/<时间_场景_视距>/。只有导入日志不表示运行过性能测试。
本次准备验证只做扩展加载、资源加载（不实例化场景）和脚本解析；实际画面、负载行为和性能数据等待后续运行验证。

## 本次准备检查结果（2026-09-13）
- Godot 4.7.stable 完整导入退出码 0，已修正准备过程中发现的统计接口名称问题。
- validate_preparation.gd 退出码 0；实际插件版本 1.7.0，edition 为 GDExtension；场景与依赖资源可加载。
- 原生依赖通过锁文件 SHA-256 校验，并验证本地压缩包恢复流程。
- PowerShell 语法检查和 Demo/Benchmark 无 -Run 的拒绝门槛检查通过。
- 没有实例化基准场景，没有生成测试世界，没有运行原版示例，没有产生 frames.csv 或 summary.json。
- 实际画面、交互及四类性能负载均待用户后续指令运行。
