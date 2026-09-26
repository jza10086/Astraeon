# 交互与玩法

## 职责与当前进度

挖掘/放置已由 native_world.gd 实现，gameplay 目录仍为职责边界。

## 架构与数据流

玩家选择目标后调用世界编辑接口；未来背包、合成、生存应在所属功能实现。

## 详细文档与入口

[世界接口](../world/native_voxel_backend.md)。

源码与测试入口：game/gameplay/interaction、inventory、crafting、survival。

## 限制与待办

没有背包扣除、掉落物、配方或生存规则；本次未提取现有交互实现。

## 验证证据

[测试入口](../../test/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。
