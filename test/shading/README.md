# 数据驱动光影测试入口

打开 `scenes/content_sample.tscn` 按 F6，或执行 `./test/shading/runners/lighting_sample.ps1 -Run`。

新场景通过 AstraeonWorldContent 读取正式方块/水定义，使用 VoxelBuffer 和 VoxelMesherBlocky 生成有限测试网格，复用 game/entities/player/scenes/player.tscn 的人物、动画、移动和碰撞。WASD 移动、空格跳跃、Esc 释放鼠标以操作按钮。

场景包含棋盘树叶/镂空投影、三轴原木、白色发光石暗室和统一水色测试区。发光石是固定位置实时 OmniLight3D（不是烘焙光），照明和表面自发光可独立观察。当前以单个上偏 0.6 米的点光源避开发光立方体自身遮挡，是明确的样板近似；不是为正式世界逐方块创建灯节点的实现。静态光源来自定义的光源参数。

原 `scenes/shading_sample.tscn` 保留为完整参数效果实验样板，已随目录迁移；其有限光照后端未强行改造成正式世界。新入口目前聚焦正式数据/人物接入，尚未移植旧样板全部效果菜单。

验证：D3D12 Forward+ 实际渲染，9 项检查通过，包括 50% 透明、裁剪材质、独立照明、玩家落地和截图；截图为 tmp/shading-content/content_sample.png。不是性能基准。

正式目录新增 astraeon_glowstone 后有 9 个状态（含空气、水、三轴原木）；旧存档若 ID 表不匹配会按现行契约拒绝，不进行转换或删除。测试场景不读取主世界存档。

---

# 独立光影样板

2026-09-22：样板已从嵌套评估工程迁移至根工程的 `test/shading/`。原 UID 保留，旧运行目录和工具路径不保留兼容副本。运行组件位于 `game/shading/`，根工程正式游戏入口保持原样。

## 启动

首次克隆或新增计算着色器后，在没有打开本根工程编辑器时完成 Godot 4.7 图形设备导入（本次工作区已完成）。若工程已经打开，交给该编辑器刷新，不另开导入进程。计算着色器 `camera_post.glsl` 需要首次导入；未导入时直接运行样板会报资源加载错误。

```powershell
& 'F:/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe' --path F:/GodotProjects/Astraeon --import
./test/shading/runners/lighting_sample.ps1 -Run
```

或在根工程编辑器打开 `test/shading/scenes/shading_sample.tscn`，按 F6；点击“创建光照样板”。F5 仍启动正式游戏。右键环视，WASD 移动，Q/E 升降；场景操作菜单内有洞口、玻璃彩影／金属样块、手持光、水面和地下观察点。

## 新模块

| 菜单 | 实现与设置 | 默认 |
|---|---|---|
| 光束与体积光 | 关闭／屏幕空间／真实体积光互斥。屏幕光束可调采样数、宽高倍率、强度、径向长度、衰减及深度边缘抑制；体积光可调雾密度、局部雾盒、颜色、各向异性、范围、网格、时间累积和灯光散射能量 | 关闭 |
| 屏幕空间 AO | Godot SSAO，半径、强度、衰减、细节、锐度、直射影响、半分辨率、引擎采样策略、模糊遍数 | 关闭，与顶点 AO 独立 |
| 彩色透明阴影 | 玻璃颜色／透射、覆盖范围、分辨率、深度偏移和纹素过滤半径；只影响指定接收材质上的日月直射 | 关闭；64 米／1024 |
| 曝光 | 固定／自动；ISO 敏感度上下界、适应速度、补偿倍率 | 固定 |
| 天气、降雨、潮湿表面 | 晴／阴／雨目标、权重和过渡；雨量、范围、速度、雨线尺寸／透明度；湿润／干燥速度、变暗、粗糙度和高光 | 晴；雨滴与湿润模块就绪 |
| 色彩方案 | 午夜／日出／正午／日落的直射、天顶、地平线、环境、雾颜色及直射能量，循环平滑插值；夜间倍率、饱和度、对比度 | 四时段默认色 |
| 景深 | 关闭／手动／中心体素射线自动焦点；前后清晰区域、过渡、模糊量、自动对焦速度 | 关闭 |
| 运动模糊 | 不透明几何／相机运动向量；快门角、采样数、像素半径和深度边缘拒绝 | 关闭 |
| 色差 | 径向 RGB 偏移，像素强度、开始半径和衰减幂 | 关闭 |
| 移动光源 | 关闭／相机手持／环绕；颜色、能量、范围、衰减、阴影请求、优先级及散射能量；全局点光与阴影预算、距离滞后 | 关闭；全局 32 点光／8 阴影 |
| 材质光泽 | 普通方块和金属样块分别设置粗糙度、金属度、镜面系数 | 开启；普通方块以哑光为主 |

环境／体素间接照明使用 `IRRADIANCE`；仅真正的自发光使用 `EMISSION`。SSAO 因而可以影响环境补光，配置变化不重建体素光传播或网格。太阳阴影默认偏移 0.06、法线偏移 2.0，最低环境光 0.015。

## 配置与接口

配置默认模板是 `game/shading/resources/default_profile.tres`。运行时复制，保存于根工程的 `user://settings.cfg`，节名 `shading`，格式 `astraeon-shading-20260922`。不读取旧样板配置格式；不支持的文件会提示并使用默认值，保存采用临时文件再替换。其他模块的配置节保留。

新增 UI 元数据位于 `shading_controls.gd`：统一名称、分组及模式依赖。所有开关采用选择框，关闭后隐藏无效参数。SSAO 的采样策略是引擎公开的枚举，不是项目低／中／高预设；半分辨率、半径、模糊等仍独立可调。

`weather_effects.set_surface_map` 接收世界 X/Z 区域的绝对顶面高度图（RF 或带 R 通道的图像）、米制起点／范围及版本号。湿润纹理是高度＋湿度（RGF）。顶面高度变更后该格湿度归零，其他格保留。有限样板 adapter 仅在体素编辑后扫描；不在生产世界逐方块调用脚本。

灯光预算按优先级、含滞后的距离、稳定实例 ID 排序。固定灯保留原照明方案的资格限制，再与移动灯共同申请全局预算。光源能量为零代表关闭照明，不隐藏发光方块的可见模型。移动源不向体素光场注入能量。

平面反射相机固定中性曝光，不执行主相机的景深、运动模糊、色差或屏幕光束；倒影 SSAO 与体积雾可单独启用。色彩调整只在主图像应用一次。

## 功能验证

```powershell
# 无 GPU 样板的配置、UI、预算、湿润逻辑
Godot_v4.7-stable_win64_console.exe --headless --path F:/GodotProjects/Astraeon --script res://test/shading/gdscript/test_shading_logic.gd
# D3D12 着色器编译探针，无需启动编辑器
Godot_v4.7-stable_win64_console.exe --path F:/GodotProjects/Astraeon --script res://test/shading/gdscript/test_shader_compile.gd
# 导入完成后的短时组合验证与截图
Godot_v4.7-stable_win64_console.exe --path F:/GodotProjects/Astraeon --script res://test/shading/gdscript/test_shading_extensions.gd -- --render --output=res://tmp/shading-extensions
```

运行状态见 [2026-09-22 验证记录](reports/shading_extensions_20260922.md)。这些检查不是性能基准。历史 2026-09-18 报告仍可作历史证据；新增模块没有经过原一小时矩阵，工具明确列为未覆盖，不产生误导性性能等级。现行性能 manifest 为 `astraeon-shading-cost-2`，旧 manifest 不可用于当前运行器。

## 首版限制

- 彩色阴影只记录离日月最近的一层玻璃，不累计多层吸收，不给点光、环境光或体积雾染色；不替代引擎不透明阴影。
- 玻璃样块为水平雨棚。高度图遮雨只适合垂直雨；洞穴和多层楼板使用最上层遮挡。人物暂不写入遮雨高度图，侧壁不模拟水流。
- 雨滴无逐粒子碰撞、飞溅和雨声。湿润只改变指定材质，不生成积水和地面 SSR。
- 自动焦点射线只检测样板体素，不检测透明水面、玻璃和测试人物；景深受引擎透明深度限制。
- 运动模糊不添加透明物体速度，水面／玻璃／雨滴不具备独立速度模糊；瞬移／观察点切换／分辨率变化重置运动处理。
- 屏幕光束依赖屏幕内的日月方向和不透明深度，不能代替真实体积遮挡；真实体积光可能出现时间累积拖影，需要人工调节。
- 水面仍是固定平面，手持光只是视觉演示，没有火把物品、碰撞、背包或游戏规则。
- 现有 P0 初始化、纹理打包，以及各新增 pass 的成本统一留到后续性能优化；不保证 120 FPS。

## shading_sample 的主体接口接入

保留房间、水池、地底走廊、树冠等固定布局。sample_world 使用原生 VoxelTool.do_box 批量填充；light_volume 的唯一方块存储改为 VoxelBuffer，光照数组是派生结果；section_meshes 使用原生区段批量复制和 VoxelMesherBlocky，并复用 AstraeonBlockLibraryBuilder 编译材质。样板光照求解与效果面板仍为测试实现，不属于正式流式世界的光照后端。

独立定义位于 resources/blocks：shading_test_air、shading_test_stone、shading_test_lamp、shading_test_wood、shading_test_leaves；水单独使用 shading_test_water 流体定义。测试方块的外观子资源各自独立，仅棋盘纹理作为只读资产复用。它们不加入正式 block_catalog，不受正式世界 ID 前缀与生成角色约束。STATE_KEYS 显式对应缓冲内 0–4 的有限测试 ID，不是生产存档 ID。

网格先经主体材质编译器生成共享图集，再由样板专用 ShaderMaterial 消费图集和体素光照纹理，以保留风动、AO、云影等开关。灯的表面仍由局部灯夹具绘制，避免自遮挡；测试 UI 可覆盖灯颜色/强度以及水面参数，原始资源保持只读。水池继续使用专用连续水面；草、彩色标杆、玻璃与金属展示物是效果夹具网格，不是体素方块。

验证：原生存储光照一致性测试 61 项、实际 D3D12 场景检查 18 项通过。渲染检查覆盖原生网格完成、图集绑定、叶片裁剪、灯与窗口交互。截图 tmp/shading-native-sample/native-sample.png；未进行性能基准。GDScript 光照求解仍逐单元访问原生缓冲，后续性能优化需独立测量，当前不宣称无额外开销。

硬阴影零倍率问题已复现并修复；新增七种彩色阴影过滤及两种日月外观，入口和截图见 [阴影与日月对比](reports/shadows_celestial.md)。光照更新优化暂缓。
