体素世界功能目录。

- blocks/：共享方块定义、状态注册表、16³ 段、三运行时存储后端。
- generation/：平原、沙漠、山地、海洋；独立段、列缓存、插值三生成策略。
- persistence/：五种段编码、持久化 ID、独立文件和区域追加存储。
- runtime/：后台工作器、版本化提交、自动保存和加载范围。
- presentation/：共用暴露面网格与静态碰撞。

地图实验入口位于 tests/world/。主场景仍为占位场景；实验模块已执行解析、正确性和综合测量，持续移动吞吐仍待改进，见 [本轮结果](../../docs/world_suite_results_20260917.md)。详见 [方块数据](../../docs/block_data.md) 和 [地图实验](../../docs/world_lab.md)。
