# 应用装配

## 职责与当前进度

main.tscn、cache_policy.gd、cache_coordinator.gd 提供入口与场景局部策略。

## 架构与数据流

main → world/player/shading；缓存策略协调预算和驻留，world 保持权威状态。

## 详细文档与入口

[源码布局](source_layout.md)、[缓存所有权](../world/world_cache.md)。

源码与测试入口：game/core；测试通过 world 与 shading 集成入口。

## 限制与待办

不增加全局管理器；无跨场景服务需求时不新增 autoload。

## 验证证据

[测试入口](../../test/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。
