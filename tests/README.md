# 自动检查

方块数据回归：`blocks/test_block_data.gd`，覆盖三种存储后端的等价性、区块坐标和资源注册边界。

可选微基准：`blocks/benchmark_block_storage.gd`，显式执行后输出 JSON，不自动选择后端。命令、指标和验收边界见 [方块数据文档](../docs/block_data.md)。

初始化与冷启动环境检查仍使用 `tools/check.ps1`；已有编辑器连接时优先 MCP 导入与诊断，避免第二个编辑器并发导入。

限时选型测试：tools/run_block_storage_suite.py 驱动 blocks/benchmark_block_selection.gd，每后端独立进程采集实际内存并比较同一轨迹。见 [初筛报告](../docs/block_storage_results_20260916.md)。

地图综合实验：world/world_data_suite.gd 与 world/world_benchmark.tscn，驱动 tools/run_world_suite.py。默认待命，显式 --run 才执行。2026-09-16 仅实现，等待用户指令测试；见 [地图实验说明](../docs/world_lab.md)。
