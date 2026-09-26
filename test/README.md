# 测试统一目录

与 game/ 同级，测试用途内容统一放入 `test/<测试项名称>/`。

- data：静态数据定义验证。
- world：地图生成、数据接入和自然地图启动验证。
- native_world：原生生成/存档契约、流式加载探针和专用运行器。
- entities：Basic Voxel 六动作实体测试及夹具。
- shading：光影测试、样板及专用工具。
- tooling：文档引用检查、冷导入前置检查和工具验证报告。
- voxelgame：历史基准报告；真实基准工程仍在 benchmarks/voxelgame。

每个测试项按需要使用 gdscript/、native/、scenes/、fixtures/、assets/、resources/、runners/、reports/；不预建空目录。一次性日志、测试存档、临时结果及编译输出写 tmp。

原 tests 目录内容已全部迁入并删除旧目录。不得新增旧路径包装器、别名或重复实现。历史基准报告中的原始源码路径与哈希保留作为证据，不作为当前运行入口。
