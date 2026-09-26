# 光影组件与接入

下列相对源码路径以 game/shading 为基准。

可复用的天空色彩、材质、环境和镜头效果位于 game/shading；组合样板、有限体素数据、测试夹具和性能工具位于 `test/shading/`。已由正式主世界装配，F6 打开光影设置；接口与限制见 [主世界光影](world_shading.md)。

- `gdscript/shading_profile.gd`：运行时复制的配置资源，当前格式 `astraeon-shading-20260926-underwater`，通过显式字段配置。
- `gdscript/day_palette.gd`：四时段循环色彩；`camera_effects.gd`：SSAO、体积雾、主相机曝光和景深。
- `gdscript/camera_post.gd`、`shaders/camera_post.glsl`：屏幕光束、运动模糊、色差的 HDR CompositorEffect；计算着色器需要先完成 Godot 导入。
- `gdscript/light_budget.gd`、`moving_light.gd`：真实移动点光源和共享点光源／阴影预算。不写入体素传播。
- `gdscript/weather_effects.gd`：相机周围 GPU 雨滴、表面高度图遮挡、湿润与干燥。生产世界通过 `configure_cache` 绑定原生天气页；全图 set_surface_map 只留在 test/shading 的有限夹具。
- `gdscript/colored_shadows.gd`：注册玻璃网格的日月透射图，独立深度和颜色纹理，仅最近一层。
- `gdscript/planar_reflection.gd`：平面水池反射，相机曝光独立，SSAO／体积雾分别选择，镜头后处理不继承。
- `shaders/surface_material.gdshaderinc`：GGX 高光和湿润参数；`glass_receiver.gdshaderinc`：只调制日月直射的彩色阴影。

`light_volume.gd` 等有限体素脚本只属于测试夹具，不是生产世界存储或光照后端。不得将其搬入本模块作为第二份权威体素数据。

用法、验证状态及限制见 [独立样板说明](../../test/shading/README.md)。

## 已批准的方块材质设计

方块外观由本模块拥有，采用 BlockAppearance、BlockSurface、BlockLightAppearance 三类共享只读资源，明确分离表面自发光与周围照明。六面贴图、标准朝向、字段及接口约定见 [方块规格](../resource_specifications.md#方块属性与材质契约)。资源结构已实现于 blocks/gdscript，示例位于 blocks/resources，静态方块定义已引用它们；原生世界已通过 blocks/gdscript/block_library_builder.gd 接入不透明/裁剪方块、颜色贴图、常量自发光及三轴朝向；独立光影样板已用 shading_test 方块复用材质编译器并保留测试光照着色器，法线/ORM/发光贴图与混合透明仍待实现。validate() 检查配置，方向及 UV 接口只返回派生值，不修改共享模板。

验证：Godot 4.7 headless 执行 `--script res://test/shading/gdscript/test_block_appearance.gd`，360 项检查通过。测试不包含图形或性能验收。

独立水体材质资源已实现于 water/，提供默认资源、校验及参数接口，后续接入边界见 [水体材质说明](water_appearance.md)。正式世界已接入原生水网格、深度吸收、波纹、SSR/平面反射和水下判断。

天空着色器支持程序化/贴图日月，彩色阴影支持六种比较过滤；样板验证见 [阴影与日月报告](../../test/shading/reports/shadows_celestial.md)。硬阴影由硬采样控制，shadow_blur 使用中性值 1，禁止以零倍率模拟硬边。

## 原生 section 缓存

`native/cache/` 保存增量光照求解、天气柱及 GPU 页池。体素读取使用 world 带版本的 section 快照，提交校验依赖；人物决定驻留，转视角不触发重算。GPU 逻辑页 16KiB，默认容量下 256 页合并为一数组层，仍逐页上传。策略由 core 持有，UI 不参与计算。详见 [缓存设计与测试](../world/world_cache.md)。旧整片参考求解器仅位于 test/shading/native/reference，发布版不编译。

## 后期功能待办

已记录的后期光影功能需求见 [光影模块待办](todo.md)，其中水下折射待开发，独立水下视距衰减控制已实现；状态以待办表为准。

水下距离雾由 `gdscript/distance_fog.gd` 统一应用，提供独立视距限制开关、每米衰减率和起始距离。具体单位、默认值及边界见 [水面与光束](water_light_shafts.md#水下视距控制2026-09-26)。

关闭水下视距限制（或衰减率为 0）时，`gdscript/underwater_tint.gd` 提供可调不透明度的观察者滤镜，位于 HUD 下方。光影颜色按钮使用 `game/ui/gdscript/bounded_color_picker.gd` 约束弹窗尺寸并支持滚动。
