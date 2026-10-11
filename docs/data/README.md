# 静态内容定义

## 职责与当前进度

方块、有限状态、流体、物品及玩家容器 Resource；不保存逐体素实例或物品数量。

## 架构与数据流

格式 2 包工程索引单文件 BlockAsset、独立 ItemAsset、流体及外部源图片，原版与 Mod 离线编译为 `.aebpack`；WorldContent 读取轻量定义，原生缓存按需加载视觉数据，世界注册表维护稳定 ID。详见 [内容包与 Mod](content_packages.md)。

## 详细文档与入口

[方块数据](block_data.md)、[正式目录](catalog.md)、[物品和容器](../gameplay/inventory.md)。

源码与测试入口：game/data/block、game/data/fluid；test/data。

## 限制与待办

物品与 10+30 槽玩家容器定义已实现，数量由 gameplay 管理；生物与装备定义尚未实现。资源制作字段见统一规格。

## 验证证据

[测试入口](../../test/data/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

物品定义新增 creative_group 主分组与 search_tags 搜索标签；有序组名在 ItemCatalog.creative_groups 中维护。属于静态展示元数据，不复制进体素或背包实例。详见 [物品栏](../gameplay/inventory.md#创造选取与分类)。

首版非方块物品已加入剑、铲、镐、斧（每格 1 件），以空 block 引用与方块物品区分，使用工具主组和独立图标；制作目录与编译内容包同步注册。见 [工具物品](../gameplay/inventory.md#工具物品首版)。
