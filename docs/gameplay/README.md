# 交互与玩法

## 职责与当前进度

已实现玩家物品栏、10 槽快捷栏、独立鼠标持物及创造分类选取、物品操作事务、挖掘/放置与背包数量联动；世界场景负责装配。

## 架构与数据流

静态物品定义 → InventoryState → UI 操作请求；InventoryInteraction 校验目标与物品数量，经 InventoryStore 日志提交后调用世界编辑接口。

## 详细文档与入口

[物品栏与交互](inventory.md)、[世界接口](../world/native_voxel_backend.md)。

源码与测试入口：game/gameplay/interaction、inventory、crafting、survival。

## 限制与待办

尚无地面掉落物、箱子实体、配方、工具耐久或生存规则。背包满时阻止产生掉落的挖掘；玩家位置仍未保存。

## 验证证据

[测试入口](../../test/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。
