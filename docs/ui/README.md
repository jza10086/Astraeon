# 界面呈现

## 职责与当前进度

设置分类菜单、帧时间 HUD、受限颜色弹窗及水下观察者滤镜已接入。

## 架构与数据流

用户设置 → 光影 profile；帧时间只测 process 间隔；UI 不执行世界缓存计算。

## 详细文档与入口

[快捷键与按键映射](../input_mapping.md)、[设置与 HUD](../shading/world_shading.md)、[水下与颜色弹窗](../shading/water_light_shafts.md)。

源码与测试入口：game/ui、game/shading/gdscript/settings_panel.gd；test/shading。

## 限制与待办

基线 1920×1080；1440p、4K、超宽及完整键鼠操作需独立验收，不从旧截图推定。

## 验证证据

[测试入口](../../test/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

## 物品栏与快捷栏

新增 game/ui/inventory：底部 10 格快捷栏、居中 3×10 储物区及同源快捷栏；60×60 槽位、4 像素间隙，简单灰色矩形材质。支持 E/Esc、数字 1—0、滚轮、拖放、拆分/合并、整堆交换和 Shift 快速转移。输入互斥、持久化及范围见 [物品栏](../gameplay/inventory.md)。独立交互入口为 test/inventory/scenes/inventory_sample.tscn。

物品栏「创造选取」页支持主组分页、名称/ID/sub tag 搜索、点击领取一组及满栏反馈；搜索框隔离 E/数字快捷键。详见 [分类设计](../gameplay/inventory.md#创造选取与分类)。

## 人物选择菜单

主菜单左下角「切换人物」打开人物页；左侧 ScrollContainer 显示模型名字和「预览」按钮，内容溢出时支持鼠标滚轮和焦点跟随；右侧独立 3D 视口播放所选人物 Idle。当前目录为标准素体与 Klukai。

「使用此人物」保存并返回；「返回」或 Esc 放弃预览选择，恢复左下角按钮焦点。主菜单加载世界期间入口禁用。该页面只由主菜单创建，不出现在暂停或游戏内设置中；重新进入世界时使用已保存人物。保存失败保留页面和错误提示。验证与分辨率覆盖见 [模型选择回归](../../test/ui/reports/2026-09-27_character_selection.md)。
