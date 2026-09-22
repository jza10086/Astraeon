# 测试统一目录

与 game/ 同级，是今后所有测试用途内容的唯一目标目录，按 data、world、entities、shading、gameplay、core、ui 模块归类；shading 模块的测试目录使用 test/shader/。

每个模块按实际需要使用 gdscript/、native/、scenes/、fixtures/、assets/、resources/、runners/、reports/ 子目录；不预建空目录。测试样板、演示、基准程序、测试专属工具、夹具和测试专属资产均放在对应模块内。需要纳入版本控制的结果报告归入 reports/；一次性运行日志、测试存档、临时结果及编译输出仍写 tmp/，不入库。

光影测试已迁入 test/shader/。其余现有 tests/、benchmarks/ 和其他历史测试内容由对应模块 agent 按用户要求后续迁移；不要为迁移新增旧路径包装器、别名或双份实现。迁移时统一更新调用、资源路径、UID、构建清单与文档并验证。
