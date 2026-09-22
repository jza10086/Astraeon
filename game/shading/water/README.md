# 水体外观资源

`gdscript/water_appearance.gd` 定义共享只读 `AstraeonWaterAppearance`；默认资源为 `resources/default_water.tres`。它与普通 BlockSurface 并列，不继承普通方块的自发光、金属度或六面方向字段。仅实现可供后续接入的资源和参数接口，不创建水面、灯、反射相机或水下控制器。

## 参数与所有权

- shallow_color / deep_color：浅水、深水颜色；absorption：每米吸收系数；opacity / uniform_opacity：总体与统一水色回退透明度。
- roughness / specular：光泽；wave_strength：波纹最大组合位移（米）；wave_scale：空间频率倍率；wave_speed：动画时钟倍率，不是液体流速。
- sky_strength / scene_reflection_strength：天空和场景反射响应强度。场景反射强度映射到 SSR 或平面反射的对应参数。
- underwater_color / underwater_distance：水下颜色和可见距离（米），由接入方的水下环境控制器使用。

颜色使用普通 RGB 且 alpha 固定为 1；透明度单独控制。validate() 返回错误列表，不静默修正源资源。使用前应校验。资源默认值沿用当前光影样板。

## 后续接入接口

surface_parameters() 返回新的 uniform 参数字典，调用方在创建或切换共享水材质时应用；禁止逐水体素创建 Material。wave_speed 由调用方用于更新 clock，水下参数由环境控制器读取。scene_reflection_parameters(planar) 仅返回所选反射分支的强度参数；无场景反射时不调用。接口不会开启任何效果，也不修改资源。

全局光影配置负责水开关、统一水色/深度吸收选择、波纹/天空反射/水下开关、SSR/平面反射选择，以及步数、分辨率、更新频率等质量预算。接入后外观值来自本资源，配置只负责策略，避免同一字段被两处反复覆盖。当前样板尚未改接，仍沿用原有 profile。

水位、体积边界、流动状态和相机是否在水下由世界及场景提供；天空颜色来自现有昼夜系统；反射纹理和矩阵由反射组件提供。资源不包含这些实例状态，也不包含逻辑碰撞/透光规则。

注意：现有 water_surface.gdshaderinc 的深度射线裁剪写死了测试池边界，water_planar.gdshaderinc 写死了参考水位 0.75。后续接入通用水体时必须将它们参数化，不能把当前样板着色器直接用于任意水体。当前统一水色回退使用固定厚度 3 米的颜色混合，暂未改变此行为。

## 验证

Godot 4.7：`--headless --path . --script res://test/shader/gdscript/test_water_appearance.gd`，49 项检查通过，覆盖无效值、共享资源隔离、参数映射和保存重载。尚未进行新水体接入、渲染或性能验收。
