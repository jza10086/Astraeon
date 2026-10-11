# 方块挖掘与损伤恢复

## 当前规则

生存模式按住左键持续挖掘，创造模式保留点击即时破坏。每 **0.05 秒**结算一次伤害；不足一个周期的时间累计，换目标、松开或切换工具时丢弃不足周期的余量，已结算损伤不丢失。掉帧按累计完整周期补算，不将溢出伤害转移到下一块。

方块最大耐久 = `hardness × 1.5`。空手或工具标签不匹配时速度为 **1 耐久度/秒**；匹配时使用该物品的 `mining_speed`，每周期伤害 = 速度 × 0.05。hardness=0 的方块在第一个完整周期完成。工具不匹配仍可破坏并获得现有掉落物，不引入最低工具等级、工具磨损、附魔、水下/腾空惩罚或破坏后的额外冷却。

这是参考 Minecraft 硬度和基础速度的简化规则，不是完整复制其挖掘公式。参考 [Breaking](https://minecraft.fandom.com/wiki/Breaking)、[Log](https://minecraft.wiki/w/Oak-log-top)、[Leaves](https://minecraft.fandom.com/wiki/Leaves)、[Glowstone](https://minecraft.fandom.com/wiki/Glowstone)。本项目额外允许损伤保留；发光石接受镐加速也是项目选择。

| 方块 | hardness | 最大耐久 | 加速标签 | 初版工具 / 速度 | 徒手耗时 | 工具耗时 |
| --- | --- | --- | --- | --- | --- | --- |
| 泥土 | 0.5 | 0.75 | astraeon:shovel | 铲 / 2 | 0.75 s | 0.40 s |
| 草方块 | 0.6 | 0.90 | astraeon:shovel | 铲 / 2 | 0.90 s | 0.45 s |
| 木头 | 2.0 | 3.00 | astraeon:axe | 斧 / 2 | 3.00 s | 1.50 s |
| 树叶 | 0.2 | 0.30 | astraeon:foliage | 剑 / 1.5 | 0.30 s | 0.20 s |
| 发光石 | 0.3 | 0.45 | astraeon:pickaxe | 镐 / 2 | 0.45 s | 0.25 s |

耗时向上取整到 0.05 秒，未包含纹理首次加载等待。斧/铲/镐采用木制工具基础速度；这些工具目前没有材质等级。

## 制作字段

- `BlockDefinition.required_tool_tag: StringName`：单一、命名空间化的加速标签；空字符串表示不接受工具加速。
- `BlockDefinition.mining_recovery_seconds: float`：停止挖掘后完全恢复的延迟，默认 30，范围 0–3600 秒；0 表示中断即恢复。是每种方块的数据，不是全局画面设置。
- `ItemDefinition.tool_tags: PackedStringArray`：多个互不重复的玩法标签，命中任意一个即可匹配方块要求。与创造分类和 `search_tags` 无关，工具名称也不参与判断。
- `ItemDefinition.mining_speed: float`：匹配时每秒移除的耐久度，默认 1，范围 1–1000。

在 [原版 blocks](../../game/data/content/authoring/astraeon/blocks/) 中修改嵌入的 block 字段；工具在 [items](../../game/data/content/authoring/astraeon/items/) 中修改嵌入的 item。使用 [内容构建流程](../data/content_packages.md#制作与发布) 重新编译后生效；不是运行时修改共享模板。

离线编译器 1.5 和原生包校验器都校验字段类型、值域及标签。当前编译包必须包含新增字段，旧包明确拒绝，需重新编译；不增加兼容读法。挖掘字段参与方块逻辑签名，旧签名世界按现有注册表契约拒绝，不自动迁移或删除。

## 运行状态与显示

`mining_progress.gd` 使用坐标→损伤记录的稀疏字典，只保存受损方块的状态 ID、已损伤耐久和最近挖掘时间。world 仍是唯一权威体素源。换目标、换工具、打开背包或松开左键保留已结算损伤。无挖掘达到配置延迟时一次性清零，不逐渐回血；暂停不推进恢复计时。退出世界不保存临时损伤。

当前十阶段裂纹显示在准星选中的受损方块：松开但仍瞄准时保留显示，重新瞄准另一受损方块显示它的记录。没有为所有离开准星的受损方块同时渲染裂纹。隐藏裂纹不清除损伤数据。

实际挖掘前确认区段可编辑且状态仍匹配；未加载不结算。`world.set_block` 在任何替换（包括同状态重放置）时清除该坐标损伤，防止新方块继承旧进度。完成前不修改体素，完成后只调用一次现有挖掘/掉落/日志事务。生成或 I/O 异常沿用报错停止规则。

## 验证

[2026-09-27 测试报告](../../test/content/reports/2026-09-27_mining.md)。测试验证固定周期、工具匹配、独立进度、恢复与裂纹、完整内容链路；人工手感和大量受损方块压力验收另行进行。
