# 应用装配

## 职责与当前进度

main.tscn、cache_policy.gd、cache_coordinator.gd 提供入口与场景局部策略。

## 架构与数据流

启动先进入 UI 主界面，选择单人游戏后加载 main → world/player/shading；缓存策略协调预算和驻留，world 保持权威状态。标题页不创建世界或缓存服务。

## 详细文档与入口

[源码布局](source_layout.md)、[缓存所有权](../world/world_cache.md)。

源码与测试入口：game/core；测试通过 world 与 shading 集成入口。

## 限制与待办

不增加全局管理器；无跨场景服务需求时不新增 autoload。

## 验证证据

[测试入口](../../test/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

内容包选择和加载阶段由core装配；视觉上传与光照/网格共享2ms提交软预算。视觉数值配置见 [内容包](../data/content_packages.md#运行时与资源所有权)。

## Main 内容包入口

`game/core/main.tscn` 显式配置原版 `.aebpack`，F6 直接运行同样执行包加载。F5 主菜单的「单人游戏」实例化该场景，并在入树前传入主菜单的 settings_path，确保 Mod 启用列表、缓存和光影设置来自同一份文件。切换期间禁用内容包按钮，进入 main 后冻结当前包集合。原版视觉预加载完成后才创建正式地形；按需视觉继续由区段、物品与共享缓存调度。旧存档不转换或删除。

入口功能检查为 `test/content/gdscript/test_main_entry.gd`：使用实际主菜单按钮和 main 默认视距，仅将存档/设置隔离到 tmp；不进行性能测量。

本次入口验证：[12项通过](../../test/content/reports/2026-09-27_main_entry/README.md)。

旧原型存档缺少注册表时，Main 提供显式「创建新世界（保留旧存档）」与返回主菜单入口。点击后在原目录同级创建新世界，并将目录名保存到 settings.cfg 的 world 节（format=1、active_slot）；下次启动读取该选择。禁止删除、解释或转换旧区段，原有建筑/背包不会继承。[验证：13项通过](../../test/content/reports/2026-09-27_old_world_entry/README.md)。

## 生存与创造模式

世界创建参数采用格式 2，记录初始模式；主世界将场景局部玩家状态接入库存快照格式 4，加载快照后恢复当前模式与数值。拒绝旧格式，详见 [模式保存](../gameplay/modes.md)。
