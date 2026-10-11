# 方块外观运行时接口

制作规格唯一入口：[资源规格](../resource_specifications.md#方块属性与材质契约)。

### 运行时接口与性能约束

其他模块提供外观引用、位置、当前朝向、必要的动态外观参数（例如灯开关或发光倍率）及变化通知。基础资源保持只读；实例熄灯应使用实例参数或切换外观，不修改共享资源。挖掘裂纹和选中描边作为动态覆盖效果，不属于基础材质。

加载时把共享外观整理为渲染使用的索引及贴图集合；不为每个方块复制 Resource、创建独立 Material 或灯节点。保持区段网格批量生成，六面不同材质不强制拆成六个绘制批次；图集或贴图数组的选择留给实际实现。大量发光方块仍可只显示自发光，实时照明继续受预算管理。

首版范围为六面外观、方向映射、透明模式、基础光泽、自发光与独立光源描述。贴图动画及更多特殊材质按实际需求加入。接入验收需覆盖六面方向与旋转、共享资源不被实例修改、自发光与周围照明独立、透明模式和不同照明方案的字段有效性；资源层测试已通过 360 项检查，含全部 24 种立方体旋转、UV 镜像切线、共享引用和保存重载；上述 360 项是历史资源层检查，不代表当前渲染与性能验收；主世界接入见 [主世界光影](world_shading.md)。


实现入口：game/shading/blocks/gdscript；示例为同功能 resources/ 下的 stone.tres、lamp.tres、log.tres。校验调用 validate()，返回带字段上下文的错误列表，不修改或静默修正资源。字典键使用 Face 枚举 TOP/BOTTOM/FRONT/BACK/LEFT/RIGHT（0–5）；未覆盖的面使用 default_surface。UV 先镜像后绕中心旋转，面切线满足 U×V=外法线，法线贴图解码后的向量通过 face_tangent_basis() 变换；向量的绿色通道转换由具体贴图导入契约负责。

## 树叶内部层次

闭合的树叶立方体通过 BlockAppearance.foliage_layers 显式参加层次方案；普通 cutout 材质（例如草片）不自动加入。正式树叶和 shading_test_leaves 已启用。编译器使用现有 Voxel Tools culls_neighbors 接口，网格热路径仍为 C++，没有逐体素 GDScript 生产计算或新 DLL 改动。

主世界与 shading_sample 共用“环境 → 植被 → 树叶层次方案”，foliage_mode 保存在 runtime_data/settings.cfg 的 shading 节：

| 值 | 方案 | 接触面和材质 |
| --- | --- | --- |
| 0 | 外壳剔面 | 相邻树叶剔除接触面，外壳双面；作为可选轻量方案与对照 |
| 1（默认） | 内部层叠 | 保留叶/叶接触面；两个反向面各自只绘制正面 |
| 2 | 内部层叠＋纹理错位 | 与方案 1 相同的网格，颜色图集 UV 按世界体素坐标稳定地作像素平移 |

方案 2 的平移仅在各自实际分辨率的 N×N 面图块内环绕，不越过六面图集边界；视角、时间和风动不改变随机结果。它适合可平铺的树叶测试图，不是所有贴图都适合环绕。自发光/ORM 仍按原 UV 读取，当前用途为常量属性树叶。

外壳与层叠切换创建新的已烘焙库及 mesher，VoxelTerrain 现有 set_mesher 会重置任务依赖、重建网格；旧派生网格的 dependency 不再匹配。原任务继续引用旧库，不能原地修改其剔面数据。已有环境材质引用继续共享。1 与 2 之间只改着色器参数，不更换 mesher。样板按 section 延续网格提交，不重启光传播。

foliage_layers 的层叠渲染优先采用背面剔除，即使原 BlockSurface.double_sided 为 true；薄片草仍双面。石块能遮住贴着它的树叶面，树叶的孔洞不能遮掉后面的石块。逻辑 light_opacity、碰撞契约、方块尺寸和存档 ID 表均不随方案切换改变。

限制：内部面增加网格、透明裁剪和阴影/反射开销；当前没有远距离叶层 LOD。棋盘纹理仍会产生莫尔纹，错位不能代替正式树叶贴图。内部光照使用下述阻光规则，厚树冠仍会逐层减光。本次没有性能分档结论。

实现：game/shading/blocks/gdscript/foliage_rendering.gd、共享 plant_surface.gdshaderinc 与单/双面 shader 包装。验证与截图见 [树叶层次报告](../../test/shading/reports/2026-09-26_foliage_layers.md)。

## 样板与正式世界的透光规则

两者均从 AstraeonBlockDefinition 读取 light_opacity 和 light_emission，不根据贴图透明度或 AIR/LAMP 特殊编号推断逻辑透光。正式树叶与 shading_test_leaves 的 light_opacity 均为 1；空气为 0，石块为 15。

- 竖向直射天空光：每格扣除目标格的 light_opacity，最低 0；空气保持直射，树叶每层扣 1，石块截断。
- 六邻接天空光与方块光：目标格 opacity < 15 才接收，每步扣除 max(1, opacity)。自身发光从定义的 light_emission 取值，与表面自发光、实时灯预算独立。
- GPU 采样有效性：opacity < 15 的单元参与遮挡约束插值，包括树叶；未知数据不贡献光。叶片孔洞的直接投影仍由 alpha 裁剪阴影处理。
- 生产使用原生 SectionLightCache 和分页 GPU 光场；有限样板保留测试专用 light_volume.gd 参考求解器与有限体积贴图。统一规则，不把 GDScript 逐体素求解引入正式世界。

叶层方案只改变几何/UV，不改变以上规则。未修改原生顶点 AO，因此局部接触仍可能偏暗；不使用提高全局最低环境光来掩盖传播错误。验证与截图见 [树叶透光一致性报告](../../test/shading/reports/2026-09-27_leaf_light.md)。

## 图集编译与缓存

当前使用离线 `.aebpack`。六面颜色图一次烘焙，朝向只变换网格/UV；纯色、ORM常量和自发光常量直接存六面参数，不创建ORM/自发光图片。生产构建入口为 `tools/content/compiler.gd` + C++ `AstraeonContentPack`；运行时 `compiled_block_builder.gd` 创建稳定共享模型/材质，C++视觉缓存绑定或回收纹理。

包布局、预加载/按需加载、预算、Mod与稳定ID契约统一见 [内容包](../data/content_packages.md)。旧运行时编译实现仅用于 `test/content/gdscript/reference_block_builder.gd` 对照；此前的像素载荷与逐状态编译数字属于历史报告，不代表当前路径。

## 挖掘裂纹

主世界生存模式按住左键，gameplay 的 `mining_progress.gd` 提供目标坐标、状态 ID 和 0–1 进度，`breaking_visual.gd` 仅管理显示和资源引用。进度映射为十个离散阶段；取消时恢复 `breaking_stage=-1` 并解除纹理引用。当前只显示一个准星目标的裂纹；玩法层保留多个方块的损伤，重新瞄准时恢复对应阶段。

`content_surface.gdshaderinc` 在共享地形/植被 Shader 内按未风动的世界坐标及面法线识别目标格，混合 ALBEDO 与裂纹颜色，并抑制对应像素的表面 EMISSION。周围灯光与体素传播不受影响。透明裁剪、风动、阴影路径保留；不增加覆盖网格或绘制批次，不触发区段重建。只有实际挖掉方块才进入已有编辑流程。

纹理组随 `.aebpack` 编译、按像素哈希去重，通过现有原生视觉缓存按需加载。挖掘持有引用，结束释放并进入缓存既有温存期；切换阶段只修改 uniform，不读图或重新上传。缓存提交沿用世界共享预算。材质共享键包含裂纹组参数，避免不同组误共享；没有每生产体素独立材质。

两组原版资源及尺寸字段见 [资源规格](../resource_specifications.md#挖掘裂纹breakingtexturegroup)。功能与实际 Shader 对照见 [裂纹验证](../../test/content/reports/2026-09-27_breaking/README.md)。工具标签加速和损伤恢复由 [gameplay](../gameplay/mining.md) 提供；尚未接入多人并发挖掘或非立方体裂纹映射；光影样板仍保留自身即时编辑操作。

## 准星目标边框

主世界使用 `game/shading/blocks/gdscript/block_target_visual.gd` 和 `shaders/block_target.gdshader` 显示 Minecraft 风格黑线选中框。默认黑色、约 2 个实际渲染像素宽；组件导出 `outline_color`、`width_pixels` 供制作调整，尚无玩家设置菜单项。一个世界只创建一个可复用网格/材质，不按地形方块创建节点。

固定六面盒略外扩 0.002m，Shader 根据每面 UV 的屏幕导数只绘制边线。保留深度测试、不写深度、不投影、不参加 GI；亮度不受环境光和雾影响，平面反射捕获中不显示。不会重建区段或改变方块材质/纹理组，允许和挖掘裂纹同时显示。当前几何边界为标准 1m 立方体，树叶采用整块边框，不沿纹理孔洞绘制。

玩法目标由 `game/gameplay/interaction/gdscript/block_target.gd` 维护，显示模块仅接收世界格坐标。测试见 [目标边框验证](../../test/content/reports/2026-09-27_block_target/README.md)。
