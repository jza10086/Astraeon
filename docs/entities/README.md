# 角色实体

## 职责与当前进度

共享运动、玩家输入、相机与六动作控制器已接入；按住 Ctrl 慢走，松开恢复普通移动，Shift 快跑。

## 架构与数据流

输入 → CharacterMotor → 实际运动状态 → CharacterVisual；world 提供地形碰撞。

## 详细文档与入口

[实体行为与参数](character_entities.md)、[资源规格](../resource_specifications.md#人物资产标准)。

源码与测试入口：game/entities/common、game/entities/player；test/entities。

## 限制与待办

生物 AI、战斗、运行时 IK 和玩家存档未实现；人工手感独立验收。

## 验证证据

[慢走回归](../../test/entities/reports/slow_walk_20260926.md)、[测试入口](../../test/entities/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。
