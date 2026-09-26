# 静态内容定义

## 职责与当前进度

方块、有限状态和流体 Resource；不保存逐体素实例。

## 架构与数据流

WorldContent 将正式目录编译为共享 ID 表、外观库和存档校验输入。

## 详细文档与入口

[方块数据](block_data.md)、[正式目录](catalog.md)。

源码与测试入口：game/data/block、game/data/fluid；test/data。

## 限制与待办

物品、生物和背包定义尚未实现；资源制作字段见统一规格。

## 验证证据

[测试入口](../../test/data/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。
