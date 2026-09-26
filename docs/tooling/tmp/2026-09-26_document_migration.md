# 文档迁移清单

日期：2026-09-26。状态：已采纳。依据：本次文档与 MCP 整理计划。

下表记录旧入口的唯一主去向；拆分的规格、接口和历史证据在备注中列出。旧文件不保留跳转副本。

| 原位置 | 当前主位置 | 处理 |
| --- | --- | --- |
| `docs/project_structure.md` | `total_development.md` | 架构合并整体概览；规则归 AGENTS；旧验证记录归 tooling/tmp |
| `docs/character_asset_contract.md` | `docs/resource_specifications.md` | 资源规格合并；运动参数归 entities；核对记录归 test/entities/reports |
| `docs/voxel_chunks.md` | `docs/world/voxel_chunks.md` | 坐标/加载保留；制作规格合入资源规格；运行接口归 shading；基准复现归 test/voxelgame/reports |
| `docs/block_data.md` | `docs/data/block_data.md` | 迁移并更新引用 |
| `docs/native_voxel_backend.md` | `docs/world/native_voxel_backend.md` | 迁移并更新引用 |
| `docs/world_generation.md` | `docs/world/world_generation.md` | 迁移并更新引用 |
| `docs/world_cache.md` | `docs/world/world_cache.md` | 迁移并更新引用 |
| `docs/character_entities.md` | `docs/entities/character_entities.md` | 迁移并更新引用 |
| `docs/world_shading.md` | `docs/shading/world_shading.md` | 迁移并更新引用 |
| `docs/shading_water_light_shafts.md` | `docs/shading/water_light_shafts.md` | 迁移并更新引用 |
| `docs/shading_todo.md` | `docs/shading/todo.md` | 迁移并更新引用 |
| `docs/development.md` | `docs/tooling/development.md` | 迁移并更新引用 |
| `docs/world_lab.md` | `docs/world/tmp/2026-09-18_world_lab.md` | 迁移并更新引用 |
| `docs/makeup_ultra_fast_analysis.md` | `docs/shading/tmp/2026-09-13_makeup_ultra_fast_analysis.md` | 迁移并更新引用 |
| `docs/makeup_ultra_fast_source.json` | `docs/shading/tmp/2026-09-13_makeup_ultra_fast_source.json` | 迁移并更新引用 |
| `docs/godot_exit_crash_diagnosis_20260913.md` | `docs/tooling/tmp/2026-09-13_godot_exit_crash_diagnosis.md` | 迁移并更新引用 |
| `docs/voxelgame_benchmarks.md` | `docs/tooling/voxelgame_benchmarks.md` | 迁移并更新引用 |
| `docs/block_storage_results_20260916.md` | `test/data/reports/block_storage_results_20260916.md` | 迁移并更新引用 |
| `docs/benchmarks/block_storage_20260916.json` | `test/data/reports/block_storage_20260916.json` | 迁移并更新引用 |
| `docs/world_suite_results_20260917.md` | `test/world/reports/world_suite_results_20260917.md` | 迁移并更新引用 |
| `docs/benchmarks/world_suite_20260917.json` | `test/world/reports/world_suite_20260917.json` | 迁移并更新引用 |
| `docs/native_voxel_results_20260918.md` | `test/native_world/reports/native_voxel_results_20260918.md` | 迁移并更新引用 |
| `docs/benchmarks/native_voxel_20260918.json` | `test/native_world/reports/native_voxel_20260918.json` | 迁移并更新引用 |
| `docs/voxelgame_benchmark_results_20260913.md` | `test/voxelgame/reports/voxelgame_benchmark_results_20260913.md` | 迁移并更新引用 |
| `docs/voxelgame_circular_performance_20260913.md` | `test/voxelgame/reports/voxelgame_circular_performance_20260913.md` | 迁移并更新引用 |
| `docs/voxelgame_circular_performance_20260913.json` | `test/voxelgame/reports/voxelgame_circular_performance_20260913.json` | 迁移并更新引用 |
| `docs/voxelgame_performance_20260913.md` | `test/voxelgame/reports/voxelgame_performance_20260913.md` | 迁移并更新引用 |
| `docs/voxelgame_performance_20260913.json` | `test/voxelgame/reports/voxelgame_performance_20260913.json` | 迁移并更新引用 |
| `AGENTS.md` | `AGENTS.md` | 保留；修正当前引用，历史数据不改写 |
| `README.md` | `README.md` | 保留；修正当前引用，历史数据不改写 |
| `docs/credits.md` | `docs/credits.md` | 保留；修正当前引用，历史数据不改写 |
| `game/data/README.md` | `game/data/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/entities/player/README.md` | `game/entities/player/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/gameplay/crafting/README.md` | `game/gameplay/crafting/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/gameplay/interaction/README.md` | `game/gameplay/interaction/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/gameplay/inventory/README.md` | `game/gameplay/inventory/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/gameplay/survival/README.md` | `game/gameplay/survival/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/shading/README.md` | `game/shading/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/shading/water/README.md` | `game/shading/water/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/ui/README.md` | `game/ui/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `game/world/README.md` | `game/world/README.md` | 保留路径；详细说明归模块文档，代码 README 只留入口 |
| `test/README.md` | `test/README.md` | 保留；修正当前引用，历史数据不改写 |
| `test/data/README.md` | `test/data/README.md` | 保留；修正当前引用，历史数据不改写 |
| `test/entities/README.md` | `test/entities/README.md` | 保留；修正当前引用，历史数据不改写 |
| `test/native_world/README.md` | `test/native_world/README.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/README.md` | `test/shading/README.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/cache_20260924.md` | `test/shading/reports/cache_20260924.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/cache_20260924_matrix.md` | `test/shading/reports/cache_20260924_matrix.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/day_cycle_fix.md` | `test/shading/reports/day_cycle_fix.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_cost_20260918.md` | `test/shading/reports/lighting_cost_20260918.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_cost_20260918_complete.md` | `test/shading/reports/lighting_cost_20260918_complete.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_cost_20260918_supplement.md` | `test/shading/reports/lighting_cost_20260918_supplement.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_environment_clouds_20260915.md` | `test/shading/reports/lighting_environment_clouds_20260915.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_local_schemes_20260915.md` | `test/shading/reports/lighting_local_schemes_20260915.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_p0.md` | `test/shading/reports/lighting_p0.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_p1_p2.md` | `test/shading/reports/lighting_p1_p2.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_performance_results_20260918.md` | `test/shading/reports/lighting_performance_results_20260918.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_performance_suite.md` | `test/shading/reports/lighting_performance_suite.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_planar_reflections_20260915.md` | `test/shading/reports/lighting_planar_reflections_20260915.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_settings_menu_20260918.md` | `test/shading/reports/lighting_settings_menu_20260918.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_update_20260914.md` | `test/shading/reports/lighting_update_20260914.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/lighting_water_20260915.md` | `test/shading/reports/lighting_water_20260915.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/motion_stutter_20260923.md` | `test/shading/reports/motion_stutter_20260923.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/motion_stutter_plan.md` | `test/shading/reports/motion_stutter_plan.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/shading_extensions_20260922.md` | `test/shading/reports/shading_extensions_20260922.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/shadows_celestial.md` | `test/shading/reports/shadows_celestial.md` | 保留；修正当前引用，历史数据不改写 |
| `test/shading/reports/world_shading.md` | `test/shading/reports/world_shading.md` | 保留；修正当前引用，历史数据不改写 |
| `test/world/README.md` | `test/world/README.md` | 保留；修正当前引用，历史数据不改写 |
| `README.md` | `README.md` | 缩减为启动与导航；状态归 total_development |
| `AGENTS.md` | `AGENTS.md` | 全项目规则与文档维护约定 |

迁移边界：真实 benchmarks/voxelgame 工程及其资源不移动。历史报告中的旧源码路径和原始命令保留为证据。
