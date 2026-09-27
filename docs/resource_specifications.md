# 资源制作与交付规格

当前契约；最后核对：2026-09-26。全项目规则见 [AGENTS](../AGENTS.md)，运行时实现见对应模块文档。

## 单位与资源边界

- 1 Godot 单位 = 1 米。标准方块占据 **1m × 1m × 1m** 体素；外观不改变逻辑体积。
- 方块标准轴：上 +Y、前 -Z、右 +X；先应用制作朝向修正，再应用实例朝向。人物采用下文独立轴约定。
- 材质透明度不决定碰撞或逻辑透光；表面自发光与周围照明分别定义。静态资源共享只读，实例状态由 world/gameplay/entities 持有。
- 区块与负坐标规则见 [世界坐标](world/voxel_chunks.md)。

## 方块属性与材质契约

2026-09-22 批准。三个材质 Resource、校验、六面/UV/法线变换及示例已实现，静态方块定义已增加 appearance 引用；正式方块的纯色不透明外观及三轴状态已接入原生世界共享图集；水通过主世界光影装配使用统一水色或动态水面。颜色贴图、裁剪透明和常量表面自发光已接入；正式世界已使用受预算约束的静态灯池及动态水面，见 [主世界光影](shading/world_shading.md)。

### 所有权与资源结构

方块属性分为三部分：静态逻辑属性（ID、特性、挖掘耗时等）、动态逻辑属性（挖掘进度、坐标、当前朝向等）与材质属性。本节只设计材质部分；前两类由 data、world、gameplay 等负责模块定义，shading 不复制权威状态。

材质部分称为“方块外观定义”，覆盖六面外观、标准朝向及照明描述，由 game/shading 拥有。采用三个共享、只读的 Resource：

| 资源 | 职责 |
| --- | --- |
| BlockAppearance | 外观入口，保存默认及六面表面材质、标准朝向、可选光源描述 |
| BlockSurface | 表面贴图、颜色、透明、光泽及自发光 |
| BlockLightAppearance | 向周围照明的颜色、强度、范围及局部位置 |

上表为概念名；实现时共享 class_name 使用 Astraeon 前缀。类型归入 game/shading/blocks/gdscript，配套资源与着色器归入该功能的 resources/、shaders/，测试归入 test/shading；实现时按需创建，不预建空目录。静态方块定义引用外观资源；多个方块可共享外观，多个面可共享表面资源。资源引用不允许反向持有世界或玩法实例。

### 表面属性：BlockSurface

| 字段 | 含义与默认约定 |
| --- | --- |
| base_color | 基础颜色及透明度，默认白色、不透明 |
| albedo_texture | 可选颜色贴图；缺省为白色，与 base_color 相乘 |
| normal_texture / normal_strength | 可选法线贴图及强度；默认无贴图、强度 1 |
| roughness / metallic / specular | 粗糙度、金属度、非金属高光，默认 1 / 0 / 0.5 |
| orm_texture | 可选合并贴图，R 为材质 AO、G 为粗糙度、B 为金属度；缺省各通道为 1，G/B 分别乘对应标量 |
| alpha_mode | 不透明、裁剪透明、混合透明，默认不透明 |
| alpha_cutoff | 裁剪阈值，默认 0.5，仅裁剪模式有效 |
| emission_color | 普通颜色值，默认白色；不另设颜色 I 强度 |
| emission_energy | 表面自发光倍率，默认 0，即关闭 |
| emission_texture | 可选自发光颜色与区域贴图，缺省为白色 |
| double_sided | 是否显示背面，默认关闭 |

自发光结果 = 发光贴图 × 发光颜色 × 发光倍率。发光倍率只控制表面自发光，不自动产生周围照明。颜色贴图按颜色数据处理；法线、ORM 按线性数据处理。材质 AO 与已有顶点 AO 分开，全局顶点 AO 设置仍独立生效。

水体的波纹、深度吸收、反射继续使用专用水材质，不混入普通方块表面字段。材质透明度只描述视觉；逻辑透光、碰撞及游戏规则使用的光照等级由其他模块显式定义，不从 alpha_mode 自动推断。

### 六面与方向：BlockAppearance

| 字段 | 含义 |
| --- | --- |
| default_surface | 六面的默认表面材质，必须提供 |
| face_surfaces | 上、下、前、后、左、右的可选覆盖；未提供时使用默认材质 |
| face_uv_rotations | 每面 UV 旋转，限定 0/90/180/270 度，默认 0 |
| face_uv_mirrors | 每面 U/V 镜像，默认关闭 |
| authoring_orientation | 素材标准朝向到规范朝向的固定旋转，默认恒等；方块首版限保持轴对齐的立方体旋转 |
| light | 可选 BlockLightAppearance，缺省不向周围照明 |

方块规范方向为上 +Y、前 -Z、右 +X；后 +Z、左 -X、下 -Y。该方向约定针对方块，不改写角色模型的独立资产方向契约。局部位置以方块中心为原点，单位为米；一个标准方块各轴边界为 -0.5 到 +0.5。

标准朝向是素材的固定属性；当前朝向是实例动态逻辑属性，由其他模块传入。变换顺序为素材方向修正，再应用当前放置方向。六面材质映射、贴图方向、法线、光源局部位置使用一致的变换。实现时需固定各面的 UV 切线约定并验证镜像后的法线方向。

例：原木上下端面使用年轮、侧面使用树皮；横放时旋转整个外观，不额外维护一套横放贴图。

### 周围照明：BlockLightAppearance

| 字段 | 含义与默认约定 |
| --- | --- |
| color | 照明颜色，默认白色 |
| energy | 照明强度，默认 0，即关闭；不直接等同于流明或体素 0–15 光照等级 |
| range | 影响距离，单位米；启用时必须为正 |
| attenuation | 距离衰减参数，由选定照明方案明确解释 |
| local_offset | 相对方块中心的局部偏移，单位米，默认零 |
| source_radius | 发光体尺寸参数，单位米，供支持的软阴影方案使用，默认 0 |
| shadow_policy | 跟随全局设置或不投射阴影，默认跟随全局 |

表面自发光和周围照明独立：普通石头两者均无；发光纹理可仅自发光；灯可同时具有两者；辅助照明可仅照亮周围。

资源不固定选择实时点光源、体素传播或其他照明方案。方案、实时灯数量、阴影预算由光影配置及光源预算系统管理；各方案须说明字段支持情况、强度映射和无效参数，不能假定效果等价。光源数据不授权 shading 持有另一份权威体素状态。


运行时校验、编译与渲染支持范围见 [方块外观接口](shading/block_appearance.md)。

## 水体外观规格

### 参数与所有权

- shallow_color / deep_color：浅水、深水颜色；absorption：每米吸收系数；opacity / uniform_opacity：总体与统一水色回退透明度。
- roughness / specular：光泽；wave_strength：波纹最大组合位移（米）；wave_scale：空间频率倍率；wave_speed：动画时钟倍率，不是液体流速。
- sky_strength / scene_reflection_strength：天空和场景反射响应强度。场景反射强度映射到 SSR 或平面反射的对应参数。
- underwater_color：水下雾色；underwater_attenuation_rate：衰减过渡长度的倒数（1/米，0 不衰减）；underwater_attenuation_start：衰减起始距离（米）。水下视距限制开关归运行时光影策略。

颜色使用普通 RGB 且 alpha 固定为 1；透明度单独控制。validate() 返回错误列表，不静默修正源资源。使用前应校验。资源默认值沿用当前光影样板。


水资源不含水位、流动、相机或反射纹理，不自动启用反射与水下效果；实现和接入边界见 [水资源接口](shading/water_appearance.md)。

## 人物资产标准


2026-09-26：以 Basic Voxel 六动作版素体为人物制作标准，采用包含左右肩胛骨的 **19 骨骼**。此前讨论的 17 骨骼方案不再作为交付标准。

标准素体已接入玩家场景，替换 HK416 V8；采用六动作控制器与本文件的导入设置。实际运行行为及验证记录见 [玩家与生物实体](entities/character_entities.md)。

## 标准来源与文件

- 制作项目：`F:/AstraBlender/Projects/basic_voxel/`。
- 参数依据：根目录 `README.md` 与 `exports/godot/README.md`；详细交付参数采用后者的六动作版说明。
- 唯一当前交换资产：`exports/godot/basic_voxel.glb`，1844716 字节。
- SHA-256：`383a153f18ee1132af0a55f8e076eafd3caa591475aa19f748e92f59e85028d6`。
- 中立源文件 `basic_voxel.blend`；动作源文件 `basic_voxel_animated.blend`；`basic_voxel_ik_authoring.blend` 含额外 4 根腿部 IK 制作骨，共 23 根。
- GLB 内含模型、蒙皮、材质、骨架、动画和形态键，无外部资源依赖。游戏不使用制作目录根部的旧 GLB、旧 SCN 或旧 17 骨骼构建脚本。
- Blender 源文件留在制作项目，游戏侧不修改；制作参考 node_0、IK 控制骨、相机、灯光不进入交付。

## 尺寸、坐标与静止姿态

| 项目 | 标准值 |
| --- | --- |
| 单位 / 导入缩放 | 1 单位 = 1 米 / 1.0 |
| Blender 坐标 | +Z 向上，-Y 朝前 |
| Godot 坐标 | +Y 向上，+Z 朝前；+X 为角色自身左侧 |
| 原点 | 双脚底中心，Godot Y=0 |
| 静止姿态 | 双臂自然下垂，非 T Pose 或 A Pose |
| 净高 / 最大宽 / 最大厚 | 1.740 / 0.670 / 0.310 m |
| 静止范围 | X=-0.335～0.335，Y=0～1.740，Z=-0.175～0.135 m |
| 头部 | 边长 0.310 m |
| 躯干 | 宽 0.350、厚 0.180、高约 0.660 m |
| 每只手臂 | 宽 0.160、下段厚 0.160、肩端厚 0.180、高约 0.660 m |
| 每条腿 | 宽 0.163、厚 0.180、高 0.700 m |

左右指角色自身。绑定前整理旋转与缩放，避免负缩放与非均匀缩放；绑定后不随意应用变换。共用动作的角色必须保持基准骨架的名称、层级、静止变换、骨轴和关节位置，不能只保持总身高。

## 完整骨架

名称区分大小写，按名称引用，不依赖导入索引：

```text
Root
└─ Hips
   ├─ Spine
   │  └─ Chest
   │     └─ UpperChest
   │        ├─ Neck
   │        │  └─ Head
   │        ├─ LeftScapula
   │        │  └─ LeftShoulder
   │        │     └─ LeftUpperArm
   │        │        └─ LeftLowerArm
   │        └─ RightScapula
   │           └─ RightShoulder
   │              └─ RightUpperArm
   │                 └─ RightLowerArm
   ├─ LeftUpperLeg
   │  └─ LeftLowerLeg
   └─ RightUpperLeg
      └─ RightLowerLeg
```

| 关键位置 / 骨长 | 静止值（高度为 Blender Z / Godot Y） |
| --- | --- |
| Hips / 腿根高度 | 0.700 m |
| 膝中心高度 | 0.440 m |
| 上臂旋转中心高度 | 1.280 m |
| 肘中心高度 | 1.030 m |
| 肩顶高度 | 1.360 m |
| 腋窝连接下缘高度 | 1.200 m |
| 头部底面高度 | 1.430 m |
| 大腿骨 / 小腿骨长度 | 0.260 / 0.440 m |
| 上臂骨 / 前臂骨长度 | 0.250 / 0.330 m |

完整静止变换与绑定矩阵以基准 GLB / Blender 骨架为准，不根据尺寸摘要猜测骨轴或重建骨架。

- Root 为全身根骨，所有动作固定；Hips 承载局部起伏与下蹲。
- LeftScapula、RightScapula 是正式导出骨，参与肩部形变，不得作为制作辅助骨删除。
- LowerArm 包含手，LowerLeg 包含脚；没有独立手腕、手掌、手指、脚踝、前脚掌或脚趾骨。
- Blender IK 求值结果烘焙到主体骨骼后导出，IK 目标与极向控制骨不导出；当前不要求运行时 IK。
- 不假定自动兼容完整 Humanoid 骨架。外部动作重定向需另行验证，不能添加旧骨架兼容别名。

## 网格、蒙皮和肩部修正

基准 Body 为连续网格：源文件 3860 顶点、3958 多边形；GLB 为 4788 渲染顶点、7716 三角形，1 个网格、1 个 surface。法线与 UV 接缝会拆分导出顶点。数量用于核对基准资产，不限制穿衣角色的顶点数。

线性蒙皮，单顶点最多 5 个非零影响，采用 8 权重布局，不得静默截为 4 权重。肩、髋、颈为连续网格；骨长不等于对应网格的全部长度。

基准材质不透明、双面、中性灰 PBR，线性 RGBA=(0.50, 0.53, 0.58, 1)，Metallic=0，Roughness=0.85，无贴图。盒式 UV 用于切线生成，不是无重叠绘画图集。现有材质名 Neutral_Gray_17Bone 不表示骨骼数量，也不作为通用人物命名要求。

必须保留以下八个肩部修正形态键（Basis 不计入），默认值为 0：

| 左侧 | 右侧 | 外展角 |
| --- | --- | --- |
| LeftShoulder_30 | RightShoulder_30 | 30° |
| LeftShoulder_60 | RightShoulder_60 | 60° |
| LeftShoulder_90 | RightShoulder_90 | 90° |
| LeftShoulder_120 | RightShoulder_120 | 120° |

源规则：中心角 c∈{30,60,90,120}，a 为同侧上臂相对静止姿态的外展角，`u=max(0,1-abs(a-c)/30)`，`weight=u*u*(3-2*u)`。例如 45° 时同侧 30°、60° 目标各为 0.5。

六套动作均已烘焙肩胛运动和八个形态键，普通播放无需额外驱动。混合时骨骼与形态键轨道必须一起混合。GLB 不执行 Blender 表达式；以后若通过 IK 或代码抬臂，需要根据最终姿势同步求解肩胛和形态键，明确动画与程序的写入顺序。上述权重公式不能代替肩胛求解；超过 120° 外展及极端复合扭转尚未验收。

## 动作契约

源时间线为 **60 FPS**，GLB 从 0 秒开始，以 **240 samples/s** 烘焙骨骼和形态键；不是游戏运行帧率。

| 动作名 | 时长 / s | 源播放帧 | 闭合帧 | Godot 循环 | 参考速度 |
| --- | --- | --- | --- | --- | --- |
| Idle | 3.000000 | 1–180 | 181 | Linear | 0 |
| Walk | 1.066667 | 1–64 | 65 | Linear | 约 0.5141 m/s |
| Run | 0.600000 | 1–36 | 37 | Linear | 4.3 m/s |
| Sprint | 0.500000 | 1–30 | 31 | Linear | 5.6 m/s |
| JumpStart | 0.733333 | 1–45 | 无 | None | 物理控制 |
| Fall | 1.000000 | 1–60 | 61 | Linear | 物理控制 |

闭合帧只表示周期终点，不额外延长一个源帧。Run 完整左右步周期参考位移 2.58 m，Sprint 为 2.80 m；Walk 是慢速步态，不能直接按 4.3 m/s 驱动。保持项目普通移动 4.3 m/s、快跑 5.6 m/s 时，分别选择 Run、Sprint；低于约 0.77 m/s 的实际速度使用 Walk，带 0.08 m/s 滞回。玩家按住 Ctrl 以 0.5141 m/s 慢走；输入规则见 [按键映射](input_mapping.md)。

所有动作原地播放，Root 不位移、不旋转。水平移动、重力、跳跃冲量和全身升降归 CharacterBody3D；不得把 Hips 局部起伏累计为根运动。

JumpStart 的源起跳标记在第 32 帧，约 0.5167 秒，末姿势衔接 Fall；没有独立落地片段，也没有导出的动画事件。玩家采用即时起跳：跳过蓄力，以正向垂直速度将起跳点至片尾映射到整个上升过程；下降或撞顶后播放 Fall，真实接地后混合回地面动作。自然跌落直接播放 Fall，不经过 JumpStart。

## Godot 导入基线

以下采用源交付 README 的复现参数，已应用于玩家资产的 .import 配置。

| 参数 | 基线 |
| --- | --- |
| Import As / Root Scale | Scene / 1.0 |
| Animation Import / FPS | On / 240 |
| Animation Trimming | Off |
| Remove Immutable Tracks | Off |
| Import Rest As RESET | Off |
| Skins Use Named Skins | On |
| Meshes Ensure Tangents | On |
| Meshes Generate LODs | Off |
| Meshes Force Disable Compression | On |
| AnimationPlayer Optimizer / Compression | 均关闭 |

在高级导入中按动作表设置循环，不假设 GLB 自带循环配置。以后降低采样率或开启优化时，重新验证支撑脚、快速收腿、形态键与循环边界。

交付报告记录的节点路径（相对 GLB 根节点）：

```text
AnimationPlayer
BasicVoxel_Rig/Skeleton3D
BasicVoxel_Rig/Skeleton3D/Body
```

游戏外层场景组装碰撞、移动、相机与动画，不直接修改生成的导入场景。资源归入 game/entities 对应功能的 assets/，不照搬外部 README 的示例目录或脚本。

## 衣服、鞋子与角色变体

- 从素体追加衣服、头发、挂饰，可删除被完全覆盖的身体表面；可整个人物一次导出，不要求运行时换装框架。
- 鞋与小腿、手套与前臂共用绑定，鞋底保持 Y=0；不为服装改变腿长、膝高、臂长或静止姿态。
- 肩部衣物需随肩胛、权重与修正形态键共同变形；改变拓扑后制作对应修正目标，不能复制顶点不匹配的增量。
- 刚性帽饰可随 Head；头发、裙摆、挂饰可增加附属骨链，但不能插入、改名或重排上述 19 根主体骨。
- 附属骨可烘焙动画或以后使用 Godot 次级物理，同一轨道的最终姿势需明确由一方负责。本阶段不要求运行时头发或布料物理。


运动和碰撞参数属于 [实体行为](entities/character_entities.md)，不由制作规格推导。资产核对证据见 [交付验证](../test/entities/reports/basic_voxel_asset_20260926.md)。

## Klukai 角色变体

- 来源：`F:/AstraBlender/Projects/klukai_voxel/klukai_voxel.glb` 与同目录 README；项目资产为 `game/entities/player/assets/klukai_voxel.glb`。原文件不修改，14,669,684 字节，SHA-256 `cb7458b4f1432331258eca222dd322ccefa5839c4a9bba919606a6a87ad963f6`。
- 与标准素体共用 19 根主体骨的名称、层级和静止变换；增加 12 条、每条 4 根的头发骨链，共 67 根骨骼。附属骨不改变主体骨契约，也不参与人物移动碰撞。
- 328 个网格，其中 94 个带各 8 个肩部修正形态键；六动作每套包含 752 条形态轨道。服装修正目标随动作一并导出，不将素体形态增量直接复制到不同拓扑。
- 动作仍为 `Idle / Walk / Run / Sprint / JumpStart / Fall`，时长与上述基准相同；保持 240 FPS 导入、关闭优化和压缩。JumpStart 不循环，其余循环。根运动不驱动游戏位置。
- 动画播放器路径为 `AnimationPlayer`，骨架为 `Klukai_Rig/Skeleton3D`。游戏公共逻辑不依赖具体 Rig 名称。头发骨当前无独立动画轨道，也未启用 Godot 物理。
- Godot 导入提取的 `klukai_voxel_Body sleeve wrist mask.png` 及其 `.import` 一并纳入资源；这张小贴图使用无损压缩（`compress/mode=0`），避免当前 D3D12 的 VRAM 压缩纹理创建错误。GLB 原始交付仍自包含。

这是一整个角色变体，可在主菜单与标准素体之间选择；尚不支持服装部件拼装或游戏内切换。运行时行为由 [entities](entities/character_entities.md#人物选择与实例化) 定义。

## 外部人物运行时导入

外部人物目录为项目根目录下的 `external_data/characters/`，由 project_paths.gd 统一解析。本阶段采用平铺 GLB 文件，无 character.json；文件名（不含扩展名）作为显示名，完整文件名构成稳定选择 ID。更名相当于新人物。只扫描目录第一层，不接受 .blend/.gltf 或额外脚本。

交付须为自包含 GLB 2.0，贴图和缓冲区嵌入文件，单文件不超过 128 MiB。沿用本文件的 19 根主体骨名称、层级、静止变换和骨架根变换；允许附属骨。场景须有网格、单个 Skeleton3D、根节点下的 AnimationPlayer，六动作名字和时长沿用当前标准。动画和衣物形态键随 GLB 交付，不自动从素体复制。

运行时以 240 FPS、保留不可变轨道、不裁剪生成场景；启用切线和命名蒙皮，关闭网格压缩。显式设置 JumpStart 不循环，其余五动作循环；此路径不执行编辑器导入优化或动画压缩，也不读取 `.import`。当前校验不替代服装变形、脚底对齐和穿模的人工验收。

按钮导入先校验，再复制临时文件并重命名发布；同名不同内容不覆盖。直接放入目录的文件在打开人物菜单时校验，失败文件保留并显示原因，不加入可选列表。更新同名 GLB 后重新打开菜单即可刷新。不修改 Blender 来源文件，也不提供任意骨架自动重定向。
