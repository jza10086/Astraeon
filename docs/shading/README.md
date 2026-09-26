# 光影

## 职责与当前进度

已接入主世界与独立样板；原生 section 派生光场和 GPU 分页上传。

## 架构与数据流

world 快照 → 原生缓存 → GPU 页；只读外观和场景配置驱动材质、天空、水与相机效果。

## 详细文档与入口

[主世界接入](world_shading.md)、[组件](components.md)、[方块接口](block_appearance.md)、[水资源接口](water_appearance.md)、[水面与光束](water_light_shafts.md)、[待办](todo.md)。

源码与测试入口：game/shading；test/shading。

## 限制与待办

normal/ORM/emission 贴图与混合透明方块仍待接入；全局水效果不代表按流体资源完成接入。

## 验证证据

[测试入口](../../test/shading/README.md)；历史通过记录不代表本次重跑。整体状态见 [整体概览](../../total_development.md)。研究资料见 [tmp](tmp/README.md)。

角色视角切换通过世界组装连接到 reset_camera_history，立即清除 motion/post 历史并更新上一帧相机变换，避免短距离切换漏过自动阈值。相机定位与显隐由 entities 负责。
