# 静态内容定义

## 职责与当前进度

方块、有限状态、流体、物品及玩家容器 Resource；不保存逐体素实例或物品数量。

## 架构与数据流

WorldContent 将正式目录编译为共享 ID 表、外观库和存档校验输入。

## 详细文档与入口

[方块数据](block_data.md)、[正式目录](catalog.md)、[物品和容器](../gameplay/inventory.md)。

源码与测试入口：game/data/block、game/data/fluid；test/data。

## 限制与待办

物品与 10+30 槽玩家容器定义已实现，数量由 gameplay 管理；生物与装备定义尚未实现。资源制作字段见统一规格。

## 验证证据

[测试入口](../../test/data/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

物品定义新增 creative_group 主分组与 search_tags 搜索标签；有序组名在 ItemCatalog.creative_groups 中维护。属于静态展示元数据，不复制进体素或背包实例。详见 [物品栏](../gameplay/inventory.md#创造选取与分类)。
