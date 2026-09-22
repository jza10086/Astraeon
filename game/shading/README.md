# Shading 模块

可复用的天空色彩、材质、环境和镜头效果位于本目录；组合样板、有限体素数据、测试夹具和性能工具位于 `test/shading/`。尚未接入正式流式世界，正式游戏入口不变。

- `gdscript/shading_profile.gd`：运行时复制的配置资源，当前格式 `astraeon-shading-20260922`，共 227 个显式设置。
- `gdscript/day_palette.gd`：四时段循环色彩；`camera_effects.gd`：SSAO、体积雾、主相机曝光和景深。
- `gdscript/camera_post.gd`、`shaders/camera_post.glsl`：屏幕光束、运动模糊、色差的 HDR CompositorEffect；计算着色器需要先完成 Godot 导入。
- `gdscript/light_budget.gd`、`moving_light.gd`：真实移动点光源和共享点光源／阴影预算。不写入体素传播。
- `gdscript/weather_effects.gd`：相机周围 GPU 雨滴、表面高度图遮挡、湿润与干燥。世界模块通过 `set_surface_map(image, origin, extent, revision)` 提供派生表面图。
- `gdscript/colored_shadows.gd`：注册玻璃网格的日月透射图，独立深度和颜色纹理，仅最近一层。
- `gdscript/planar_reflection.gd`：平面水池反射，相机曝光独立，SSAO／体积雾分别选择，镜头后处理不继承。
- `shaders/surface_material.gdshaderinc`：GGX 高光和湿润参数；`glass_receiver.gdshaderinc`：只调制日月直射的彩色阴影。

`light_volume.gd` 等有限体素脚本只属于测试夹具，不是生产世界存储或光照后端。不得将其搬入本模块作为第二份权威体素数据。

用法、验证状态及限制见 [独立样板说明](../../test/shading/README.md)。
