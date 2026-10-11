# 资源制作与交付规格

当前契约；最后核对：2026-09-27。全项目规则见 [AGENTS](../AGENTS.md)，运行时实现见对应模块文档。

## 单位与资源边界

- 1 Godot 单位 = 1 米。标准方块占据 **1m × 1m × 1m** 体素；外观不改变逻辑体积。
- 方块标准轴：上 +Y、前 -Z、右 +X；先应用制作朝向修正，再应用实例朝向。人物采用下文独立轴约定。
- 材质透明度不决定碰撞或逻辑透光；表面自发光与周围照明分别定义。静态资源共享只读，实例状态由 world/gameplay/entities 持有。
- 区块与负坐标规则见 [世界坐标](world/voxel_chunks.md)。

## 方块属性与材质契约

2026-09-22 批准。三个材质 Resource、校验、六面/UV/法线变换及示例已实现，静态方块定义已增加 appearance 引用；正式方块的纯色不透明外观及三轴状态已接入原生世界共享图集；水通过主世界光影装配使用统一水色或动态水面。颜色贴图、裁剪透明和常量表面自发光已接入；正式世界已使用受预算约束的静态灯池及动态水面，见 [主世界光影](shading/world_shading.md)。

### 内容交付

制作入口为格式 2 的包工程 `.tres`：索引完整单文件 `BlockAsset`（静态逻辑、外观及可选关联物品）、独立 `ItemAsset` 与流体。原版工程为 `game/data/content/authoring/astraeon/pack.tres`。图片通过工程 `image_sources` 保存开发者指定的绝对路径或相对工程文件的路径，方块 `image_slots` 指定使用位置；源资源不直接引用 Texture2D，源图片不随游戏发布。原版源码图片存放在 `content_sources/astraeon/`，该位置是仓库选择而非 Mod 限制。交付游戏/Mod使用版本化 `.aebpack`，内容ID采用 `namespace:name`。`BlockDefinition.load_policy` 支持 preload/on_demand，默认原版预加载；不放入材质属性。游戏不合成源图片。六面颜色离线烘焙，纯色及常量ORM/自发光紧凑存储，朝向状态共享图集。制作SDK和当前支持范围见 [内容包契约](data/content_packages.md)。

### 所有权与资源结构

方块属性分为三部分：静态逻辑属性（ID、特性、挖掘耗时等）、动态逻辑属性（挖掘进度、坐标、当前朝向等）与材质属性。本节只设计材质部分；前两类由 data、world、gameplay 等负责模块定义，shading 不复制权威状态。

材质部分称为“方块外观定义”，覆盖六面外观、标准朝向及照明描述，由 game/shading 拥有。采用以下共享、只读的 Resource：

| 资源 | 职责 |
| --- | --- |
| BlockAppearance | 外观入口，保存默认及六面表面材质、标准朝向、可选光源描述 |
| BlockSurface | 表面贴图、颜色、透明、光泽及自发光 |
| BlockLightAppearance | 向周围照明的颜色、强度、范围及局部位置 |
| BreakingTextureGroup | 挖掘裂纹的十阶段遮罩、颜色与混合强度，不保存挖掘进度 |

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

完整方块文件中所有 Texture2D 字段保持空；当前颜色图通过 `image_slots` 的 `surface/default` 或 `surface/0..5` 指向包工程图片索引，编译器在私有副本上填充 `albedo_texture`。下表/字段类型描述渲染语义，不代表制作时需要 Godot 导入图片。

自发光结果 = 发光贴图 × 发光颜色 × 发光倍率。发光倍率只控制表面自发光，不自动产生周围照明。颜色贴图按颜色数据处理；法线、ORM 按线性数据处理。材质 AO 与已有顶点 AO 分开，全局顶点 AO 设置仍独立生效。

水体的波纹、深度吸收、反射继续使用专用水材质，不混入普通方块表面字段。材质透明度只描述视觉；逻辑透光、碰撞及游戏规则使用的光照等级由其他模块显式定义，不从 alpha_mode 自动推断。

### 六面与方向：BlockAppearance

| 字段 | 含义 |
| --- | --- |
| texture_resolution | 每面正方形像素边长，默认及建议 32；特殊方块可设 1–1024 的整数，例如 16、64、128；六面共用该尺寸 |
| default_surface | 六面的默认表面材质，必须提供 |
| face_surfaces | 上、下、前、后、左、右的可选覆盖；未提供时使用默认材质 |
| face_uv_rotations | 每面 UV 旋转，限定 0/90/180/270 度，默认 0 |
| face_uv_mirrors | 每面 U/V 镜像，默认关闭 |
| authoring_orientation | 素材标准朝向到规范朝向的固定旋转，默认恒等；方块首版限保持轴对齐的立方体旋转 |
| light | 可选 BlockLightAppearance，缺省不向周围照明 |
| breaking | BreakingTextureGroup 参数内嵌于完整方块；新建时默认 null，原版显式配置通用/木纹裂纹；null 仅关闭显示 |
| foliage_layers | 闭合裁剪透明立方体参与树叶内部层次渲染，默认 false；仅允许 CUTOUT，不改变逻辑透光/碰撞。层叠方案采用正面绘制，覆盖表面的 double_sided；薄片植被不要启用 |

方块规范方向为上 +Y、前 -Z、右 +X；后 +Z、左 -X、下 -Y。该方向约定针对方块，不改写角色模型的独立资产方向契约。局部位置以方块中心为原点，单位为米；一个标准方块各轴边界为 -0.5 到 +0.5。

标准朝向是素材的固定属性；当前朝向是实例动态逻辑属性，由其他模块传入。变换顺序为素材方向修正，再应用当前放置方向。六面材质映射、贴图方向、法线、光源局部位置使用一致的变换。实现时需固定各面的 UV 切线约定并验证镜像后的法线方向。

例：原木上下端面使用年轮、侧面使用树皮；横放时旋转整个外观，不额外维护一套横放贴图。
贴图制作仍为默认表面＋按面覆盖，可共用图片，不要求六张独立文件。建议每面 32×32，特殊方块在 BlockAppearance.texture_resolution 明确指定更低或更高尺寸；该像素值不改变方块 1m 尺寸或 16³ section。编译时按最近邻将每面源图采样到 N×N，再排列为 [上][下][前][后][左][右] 的 6N×N 图集，默认 192×32。原图未修改；高分辨率输入只有配置了相应 N 才保留更多细节，低分辨率输入放大不会凭空增加细节。一个外观的六面目前共用同一 N，不能逐面指定不同图块尺寸；手工六面图集不会自动拆分。运行时生命周期和内存说明见 [方块外观接口](shading/block_appearance.md#图集编译与缓存)。

### 挖掘裂纹：BreakingTextureGroup

实际类型为 `AstraeonBreakingTextureGroup`，挂在 `BlockAppearance.breaking`。不同方块可以共享或选择不同组；原版包工程提供 `breaking_common`（通用分叉裂纹）和 `breaking_wood`（木材纵向劈裂）两张图片索引，原木选择后者。图片为项目原创，不使用 Minecraft 贴图。

| 字段 | 制作契约 |
| --- | --- |
| stages_texture | 编译器临时绑定，制作文件保持空，通过 BlockAsset.image_slots["breaking"] 引用工程图片索引；十阶段水平条带，尺寸 10N×N，N 为 1–1024 整数；建议 N=32，即 320×32；从左到右阶段 0–9 |
| tint | 裂纹颜色，默认深褐近黑；Alpha 乘入混合强度 |
| strength | 混合强度，0–1，默认 0.9 |

遮罩读取 R 通道作为线性数据：黑色不改变原材质，白色完整应用配置强度；源图 Alpha 不参与裂纹遮罩。建议后续阶段保留前一阶段裂纹并扩展。六面复用同一阶段图，使用方块规范面 UV 并随实例朝向旋转；不按六面或朝向重复生成图片。最近邻采样、无 mipmap。此图独立于六面颜色图集，不改变 `texture_resolution`。

裂纹是目标方块的动态 Shader 混合，不覆盖树叶原有透明孔洞，不改变碰撞、传播光或光源强度。运行时与交互边界见 [方块外观接口](shading/block_appearance.md#挖掘裂纹)；进度由 gameplay 持有，不写回共享 Resource。

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


2026-09-27：以 Basic Voxel 八动作握持骨版为人物制作标准，共 **21 根骨骼**：19 根主体骨和 Grip_R / Grip_L。

标准素体已接入玩家场景，替换 HK416 V8；采用六动作控制器与本文件的导入设置。实际运行行为及验证记录见 [玩家与生物实体](entities/character_entities.md)。

## 标准来源与文件

- 制作项目：`F:/AstraBlender/Projects/basic_voxel/`。
- 参数依据：根目录 `README.md` 与 `exports/godot/README.md`；详细交付参数采用后者的八动作握持骨版说明。
- 第三人称交换资产：`exports/godot/basic_voxel.glb`，2466136 字节。
- SHA-256：`b2db9553bebf48a143d37d2f80ad6594f34badb0c853a859aa695300e59e75d4`。
- 第一人称来源：`F:/AstraBlender/Projects/basic_voxel_fp/exports/godot/basic_voxel_fp.glb`，849624 字节，SHA-256 `c87ba6f9e6b678e408dddeb25478fbad9faf187ea3d5475a1688115ae1d92f75`。
- 默认交付为 `external_data/characters/basic_voxel/basic_voxel_tp.glb` 与 `basic_voxel_fp.glb`；分别原样复制上述来源。制作源文件与 IK 控制器不导入。
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
   │        │           └─ Grip_L
   │        └─ RightScapula
   │           └─ RightShoulder
   │              └─ RightUpperArm
   │                 └─ RightLowerArm
   │                    └─ Grip_R
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
- 当前投掷起点采用对应视角骨架 Grip_R 的世界位置；第一、第三人称使用各自骨架当前姿态，不混用偏移。
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

八套动作均已烘焙肩胛运动和八个形态键，普通播放无需额外驱动。混合时骨骼与形态键轨道必须一起混合。GLB 不执行 Blender 表达式；以后若通过 IK 或代码抬臂，需要根据最终姿势同步求解肩胛和形态键，明确动画与程序的写入顺序。上述权重公式不能代替肩胛求解；超过 120° 外展及极端复合扭转尚未验收。

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
| HoldBlock_R | 2.000000 | 1–120 | 121 | Linear | 0 |
| HoldBlock_L | 2.000000 | 1–120 | 121 | Linear | 0 |

右手 HoldBlock_R 已通过右臂与右肩形态键过滤叠加到运动动作；HoldBlock_L 仅保留资源，尚未接入玩法。Grip_R / Grip_L 为对应 LowerArm 子骨，不参与蒙皮；局部 +Z 指向承托面外、+Y 指向肘部。中心原点的 0.12 m 方块可放在挂点局部 (0, 0, 0.06) m。

闭合帧只表示周期终点，不额外延长一个源帧。Run 完整左右步周期参考位移 2.58 m，Sprint 为 2.80 m；Walk 是慢速步态，不能直接按 4.3 m/s 驱动。保持项目普通移动 4.3 m/s、快跑 5.6 m/s 时，分别选择 Run、Sprint；低于约 0.77 m/s 的实际速度使用 Walk，带 0.08 m/s 滞回。玩家按住 Ctrl 以 0.5141 m/s 慢走；输入规则见 [按键映射](input_mapping.md)。

所有动作原地播放，Root 不位移、不旋转。水平移动、重力、跳跃冲量和全身升降归 CharacterBody3D；不得把 Hips 局部起伏累计为根运动。

JumpStart 的源起跳标记在第 32 帧，约 0.5167 秒，末姿势衔接 Fall；没有独立落地片段，也没有导出的动画事件。玩家采用即时起跳：跳过蓄力，以正向垂直速度将起跳点至片尾映射到整个上升过程；下降或撞顶后播放 Fall，真实接地后混合回地面动作。自然跌落直接播放 Fall，不经过 JumpStart。

## Godot 导入基线

以下为源交付 README 的制作基线。当前人物全部由运行时 GLTFDocument 加载，不读取编辑器 .import；运行时实现见下文。

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

运行时按动作表设置循环，不假设 GLB 自带循环配置。以后降低采样率或开启优化时，重新验证支撑脚、快速收腿、形态键与循环边界。

交付报告记录的节点路径（相对 GLB 根节点）：

```text
AnimationPlayer
BasicVoxel_Rig/Skeleton3D
BasicVoxel_Rig/Skeleton3D/Body
```

游戏外层场景组装碰撞、移动、相机与动画，不直接修改生成的导入场景。人物 GLB 成对放入 external_data/characters 下的人物文件夹，不保留 game/ 内置模型副本。

## 衣服、鞋子与角色变体

- 从素体追加衣服、头发、挂饰，可删除被完全覆盖的身体表面；可整个人物一次导出，不要求运行时换装框架。
- 鞋与小腿、手套与前臂共用绑定，鞋底保持 Y=0；不为服装改变腿长、膝高、臂长或静止姿态。
- 肩部衣物需随肩胛、权重与修正形态键共同变形；改变拓扑后制作对应修正目标，不能复制顶点不匹配的增量。
- 刚性帽饰可随 Head；头发、裙摆、挂饰可增加附属骨链，但不能插入、改名或重排上述 21 根标准骨。
- 附属骨可烘焙动画或以后使用 Godot 次级物理，同一轨道的最终姿势需明确由一方负责。本阶段不要求运行时头发或布料物理。


运动和碰撞参数属于 [实体行为](entities/character_entities.md)，不由制作规格推导。资产核对证据见 [交付验证](../test/entities/reports/basic_voxel_asset_20260926.md)。

## 第一人称模型与动作

FP 模型独立于完整身体，默认包含双臂：1368 个渲染顶点、1952 个三角形、1 个网格和材质，保留相同 21 根标准骨与八个肩部修正形态键。上述完整身体尺寸、脚底原点仅适用于 TP；FP 的骨架对象已有 glTF 平移 (0, -1.40, +0.06) m，不能重复应用。两种视角的标准骨静止变换与各自根变换保存在 `game/entities/common/gdscript/character_rig_standard.gd`，校验不依赖另一个可删除的人物文件。

FP 必须交付 `FP_Idle`、`FP_HoldBlock_R`、`FP_HoldBlock_L`，均为 2 秒、240 samples/s，运行时线性循环。FP 使用自己的 AnimationPlayer，在空手与右手持方块之间以 0.12 秒混合；跑跳继续由 TP 六动作控制器处理，当前没有独立 FP 跑跳片段。左手片段保留但未接入操作。

制作预览相机位于原点，16:9、水平 FOV 90°（垂直约 58.7155°）、near=0.01 m。Godot 将 FP 挂在相机下，外层绕 Y 旋转 180°，把模型 +Z 朝前转换到相机 -Z；保留 GLB 内部偏移。FP 不带相机、灯光或展示方块。Grip 轴与 0.12 m 方块偏移沿用上文。

## 外部人物运行时导入

人物统一位于项目根目录 `external_data/characters/`，由 project_paths.gd 解析；桌面导出后位于可执行文件旁。每个人物一个文件夹，文件夹名与两个 GLB 的前缀完全一致：

```text
external_data/characters/
└─ basic_voxel/
   ├─ basic_voxel_tp.glb
   └─ basic_voxel_fp.glb
```

固定后缀为 `_tp.glb`（第三人称）、`_fp.glb`（第一人称）。前缀同时作为显示名与选择 ID，一个文件夹对应一个按钮；更名时目录和两文件同步更名。两份齐全并校验通过才可选，不支持平铺旧 GLB、旧 `user/<文件名>` ID 或单视角人物。默认人物也按此规则存放，不设内置回退。

每份须为自包含 GLB 2.0，贴图与缓冲区内嵌，单文件不超过 128 MiB。需有网格、一个 Skeleton3D、根节点下的 AnimationPlayer。标准骨名称、层级、静止变换及对应视角根变换必须匹配，允许附属骨；TP 必须含八动作，FP 必须含上述三动作。动画、衣物与形态键随各自 GLB 交付，不自动复制或重定向。

运行时以 240 FPS、保留不可变轨道、不裁剪生成场景；启用切线和命名蒙皮，关闭网格压缩。JumpStart 不循环，其他必需动作循环。不执行编辑器导入优化或动画压缩。校验不替代服装变形、手部构图和穿模的人工验收。

可直接复制整个文件夹后重新打开人物页，或用「导入人物」选择该文件夹。按钮导入先校验，复制两文件至暂存目录，核对哈希并再次校验，再重命名整个目录发布。同名同内容复用，同名不同内容拒绝覆盖。错误显示原因并保留来源；不自动修复或迁移。不递归扫描其他层级，也不持续监听。

external_data 内容按项目规则不提交 Git；发行时必须随程序提供默认人物文件夹。缺失所选人物会报告并停止相关操作，不静默替换人物。当前验收见 [成对人物与独立第一人称](../test/entities/reports/2026-09-27_paired_character_models.md)。
