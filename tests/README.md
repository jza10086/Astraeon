# 自动检查

方块数据回归：`blocks/test_block_data.gd`，覆盖三种存储后端的等价性、区块坐标和资源注册边界。

可选微基准：`blocks/benchmark_block_storage.gd`，显式执行后输出 JSON，不自动选择后端。命令、指标和验收边界见 [方块数据文档](../docs/block_data.md)。

初始化与冷启动环境检查仍使用 `tools/check.ps1`；已有编辑器连接时优先 MCP 导入与诊断，避免第二个编辑器并发导入。
