# 角色实体

## 职责与当前进度

共享运动、玩家输入、第一／第三人称相机与六动作控制器已接入；默认第一人称，V 切换视角；按住 Ctrl 慢走，松开恢复普通移动，Shift 快跑。快捷栏选中方块时叠加右臂握持动作并显示挂点方块；空槽和工具放下手臂。

掉落物已接入：C++ 记录池、重力碰撞、休眠/唤醒、附近查询；场景层管理显示和背包事务，见 [掉落物](dropped_items.md)。

## 架构与数据流

输入 → CharacterMotor → 实际运动状态 → CharacterVisual；world 提供地形碰撞。

## 详细文档与入口

[实体行为与参数](character_entities.md)、[资源规格](../resource_specifications.md#人物资产标准)。

源码与测试入口：game/entities/common、game/entities/player；test/entities。

## 限制与待办

生物 AI、战斗、运行时 IK 和玩家存档未实现；人工手感独立验收。

## 验证证据

[切换瞬间回归](../../test/entities/reports/view_cut_20260926.md)、[第一人称回归](../../test/entities/reports/first_person_20260926.md)、[慢走回归](../../test/entities/reports/slow_walk_20260926.md)、[测试入口](../../test/entities/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

人物模型：全部放入 external_data/characters 的人物文件夹，TP/FP 同前缀固定后缀，单个按钮成对选择并同时预览。第一人称使用独立双臂与 FP 动画，第三人称使用完整身体；只在主菜单更换人物。[当前契约](character_entities.md#人物选择与实例化)与[验收](../../test/entities/reports/2026-09-27_paired_character_models.md)。

## 生存与创造模式

创造飞行已接入共享运动组件：双击空格切换、空格/Ctrl 升降、Shift 加速；保留碰撞，无输入悬停。生命与饱食度由 gameplay 管理，详见 [模式规则](../gameplay/modes.md)。
