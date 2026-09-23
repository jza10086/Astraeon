# Shading 模块

可复用的天空色彩、材质、环境和镜头效果位于本目录；组合样板、有限体素数据、测试夹具和性能工具位于 `test/shading/`。已由正式主世界装配，F6 打开光影设置；接口与限制见 [主世界光影](../../docs/world_shading.md)。

- `gdscript/shading_profile.gd`：运行时复制的配置资源，当前格式 `astraeon-shading-20260922b`，通过显式字段配置。
- `gdscript/day_palette.gd`：四时段循环色彩；`camera_effects.gd`：SSAO、体积雾、主相机曝光和景深。
- `gdscript/camera_post.gd`、`shaders/camera_post.glsl`：屏幕光束、运动模糊、色差的 HDR CompositorEffect；计算着色器需要先完成 Godot 导入。
- `gdscript/light_budget.gd`、`moving_light.gd`：真实移动点光源和共享点光源／阴影预算。不写入体素传播。
- `gdscript/weather_effects.gd`：相机周围 GPU 雨滴、表面高度图遮挡、湿润与干燥。世界模块通过 `set_surface_map(image, origin, extent, revision)` 提供派生表面图。
- `gdscript/colored_shadows.gd`：注册玻璃网格的日月透射图，独立深度和颜色纹理，仅最近一层。
- `gdscript/planar_reflection.gd`：平面水池反射，相机曝光独立，SSAO／体积雾分别选择，镜头后处理不继承。
- `shaders/surface_material.gdshaderinc`：GGX 高光和湿润参数；`glass_receiver.gdshaderinc`：只调制日月直射的彩色阴影。

`light_volume.gd` 等有限体素脚本只属于测试夹具，不是生产世界存储或光照后端。不得将其搬入本模块作为第二份权威体素数据。

用法、验证状态及限制见 [独立样板说明](../../test/shading/README.md)。

## 已批准的方块材质设计

方块外观由本模块拥有，采用 BlockAppearance、BlockSurface、BlockLightAppearance 三类共享只读资源，明确分离表面自发光与周围照明。六面贴图、标准朝向、字段及接口约定见 [方块规格](../../docs/voxel_chunks.md#方块属性与材质契约)。资源结构已实现于 blocks/gdscript，示例位于 blocks/resources，静态方块定义已引用它们；原生世界已通过 blocks/gdscript/block_library_builder.gd 接入不透明/裁剪方块、颜色贴图、常量自发光及三轴朝向；独立光影样板已用 shading_test 方块复用材质编译器并保留测试光照着色器，法线/ORM/发光贴图与混合透明仍待实现。validate() 检查配置，方向及 UV 接口只返回派生值，不修改共享模板。

验证：Godot 4.7 headless 执行 `--script res://test/shading/gdscript/test_block_appearance.gd`，360 项检查通过。测试不包含图形或性能验收。

独立水体材质资源已实现于 water/，提供默认资源、校验及参数接口，后续接入边界见 [水体材质说明](water/README.md)。正式世界已接入原生水网格、深度吸收、波纹、SSR/平面反射和水下判断。

天空着色器支持程序化/贴图日月，彩色阴影支持六种比较过滤；样板验证见 [阴影与日月报告](../../test/shading/reports/shadows_celestial.md)。硬阴影由硬采样控制，shadow_blur 使用中性值 1，禁止以零倍率模拟硬边。
