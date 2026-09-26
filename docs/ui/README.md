# 界面呈现

## 职责与当前进度

设置分类菜单、帧时间 HUD、受限颜色弹窗及水下观察者滤镜已接入。

## 架构与数据流

用户设置 → 光影 profile；帧时间只测 process 间隔；UI 不执行世界缓存计算。

## 详细文档与入口

[设置与 HUD](../shading/world_shading.md)、[水下与颜色弹窗](../shading/water_light_shafts.md)。

源码与测试入口：game/ui、game/shading/gdscript/settings_panel.gd；test/shading。

## 限制与待办

基线 1920×1080；1440p、4K、超宽及完整键鼠操作需独立验收，不从旧截图推定。

## 验证证据

[测试入口](../../test/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。
