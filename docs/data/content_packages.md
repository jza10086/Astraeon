# 预编译方块内容包

## 包工程与单文件资源（制作格式 2）

原版入口是 [pack.tres](../../game/data/content/authoring/astraeon/pack.tres)，与 Mod 使用同一个编译器和 `.aebpack` 读取器。`blocks/` 每个文件为 `AstraeonBlockAsset`，内嵌 BlockDefinition、BlockAppearance、六面材质/光源/裂纹参数和可选的对应 ItemDefinition；修改一个方块不再分散到多个正式目录。`items/` 为独立工具物品，`fluids/` 为完整水体定义。旧低层 Resource 示例移至 `test/data/`，只用于资源 API 测试，不是原版第二个制作入口。

| 制作字段 | 契约 |
| --- | --- |
| `project_format` | 必须为 2；不读取旧制作格式 |
| `blocks / items / fluids` | 完整资源文件索引；关联方块物品内嵌于 BlockAsset.item，不重复加入 items |
| `image_sources` | 图片键 → 文件系统路径，支持绝对路径或相对 pack.tres 所在目录；不使用 res://、user://，不自动搜索或导入备用图片 |
| `BlockAsset.image_slots` | surface/default、surface/0..5、breaking、item/icon → 工程图片键；对应面覆盖/裂纹/物品必须已定义 |
| `ItemAsset.icon_image` | 独立物品的图标图片键；空值保留基础颜色显示 |

图片由开发者自行保管，可以放在工程外。仓库原版选择 `content_sources/astraeon/`，用 `.gdignore` 隔离 Godot 导入；包工程只保存索引，不嵌入 PNG 或 ImageTexture。移动图片后更新索引，移动包工程时检查相对路径。分享可编辑工程时，需要同时提供索引指向的源图片；`.aebpack` 仅为运行产物，不作为可逆源码工程。

编译器读取实际源文件、在私有深拷贝中绑定 Texture2D，复用 C++ 图集/压缩/校验实现。源 Resource 保持不变。六面颜色合并到视觉载荷；裂纹、物品图标作为同包内独立压缩载荷，共享图片/最终像素继续去重、支持按需读取。不增加 subpak：现有分块索引已经避免整包图片一起解压，单文件安装也不会缺少外部纹理。

输出不包含作者机器路径、Resource 脚本或外部图片依赖。路径和源文件哈希只存在本地构建 receipt 中；receipt 不随游戏发布。源图丢失、解码失败或索引无效会停止导出并保留上一次有效 `.aebpack`。游戏从打包像素创建纹理，启动不访问制作目录。导出过滤制作工程、content_sources、test 和 receipt。

编辑流程：在顶部 **内容编辑器** 主工作区打开 pack.tres，选择方块 / 物品 / 流体，在中文材质 / 逻辑折叠表单编辑，使用基础实时预览、保存全部、校验和导出。关联物品始终保存回所属方块文件。详细操作、冲突和预览边界见 [专用编辑器](../tooling/content_editor.md)。

功能证据见 [资源整合验证](../../test/content/reports/2026-09-27_authoring/README.md)。

## 制作与发布

当前 API 1；容器版本 1，编译器 aeb-content-1.5。Resource 是制作输入，主世界与 shading_sample 从 `.aebpack` 构建定义和共享模型，不在游戏中解码源图、缩放或合成图集。旧源编译器仅保留于 `test/content/gdscript/reference_block_builder.gd`，用于资源回归和性能对照。

包清单 `AstraeonContentManifest` 引用 blocks、fluids、items、dependencies。包 ID 限小写字母、数字、下划线、连字符；内容 ID 如 `astraeon:stone`，状态键如 `astraeon:log/axis_x`。包不可覆盖其他包的命名空间。缺失依赖、循环、重复 ID 和不支持版本均拒绝；不支持脚本 Mod 或运行中更换包。

`BlockDefinition.load_policy` 是逻辑定义上的 preload/on_demand 字段，不属于材质。原版基础方块 preload，SDK 特殊方块 on_demand。水采用现有单一水定义；多流体模拟不在当前实现范围。

制作入口：编辑器顶部内容编辑器，或匹配版本 Godot 的命令：

```powershell
godot --headless --path . --script res://tools/content/cli.gd -- validate res://game/data/content/authoring/astraeon/pack.tres
godot --headless --path . --script res://tools/content/build_builtin.gd
godot --headless --path . --script res://tools/content/cli.gd -- inspect res://game/data/content/packages/astraeon.aebpack
python tools/content/build_sdk.py
```

构建前遵循项目编辑器/DLL流程。SDK 默认生成到 `tmp/content/sdk/`，从当前资源脚本复制生成，不另维护类型分支。普通 Mod 作者无需编译 C++。原版包与 receipt 是生成产物；`tools/content/verify_deployment.py` 检查源依赖/包哈希，正式导出使用 `tools/content/export.ps1`，过期则在调用导出前失败。游戏不会静默编译缺失包。

## 二进制布局

所有整数小端、固定宽度；不保存 C++ 内存结构或 Godot 对象。

| 区域 | 布局 |
| --- | --- |
| 64 字节头 | magic AEBPACK1(8)、version u32、blob_count u32、metadata_bytes u64、file_bytes u64、metadata+index SHA-256(32) |
| 定义 | 规范排序的 UTF-8 JSON 数据记录，最多16MiB；不是可执行 Resource |
| 每项88字节索引 | 原始块 SHA-256(32)、offset u64、compressed_bytes u64、raw_bytes u64、压缩块 SHA-256(32) |
| 视觉载荷 | 按原始哈希排序、连续存放；每块独立 Zstandard；最大解压64MiB |

视觉块是16字节 `AVT1` 头（magic、width、height、interpretation=1，均u32）加 RGBA8 像素；解释1为 sRGB 颜色、最近邻、无 mipmap。哈希覆盖头和像素，因此不同尺寸/解释不会误共享纹理。容器上限8GiB/65536块，限制在分配和解压前检查；压缩校验和原始哈希在首次读取时检查。只读索引不会读取视觉载荷，故磁盘载荷损坏可能在首次按需访问时才报告，不能把 metadata open 当作全包校验。

默认每面32×32，允许1–1024。六面规范顺序为上、下、前、后、左、右，6N×N；UV旋转/镜像离线处理。24种轴对齐方向使用原生正交旋转表，不复制纹理。纯色六面和常量粗糙度/金属度/自发光直接存参数，不生成图片。纹理按最终像素与解释共享，材质按完整视觉参数共享。

构建缓存位于 `tmp/content/compiler_cache/`，键包含源图内容/尺寸、参数、编译器版本。重复编译仍读取源图以计算指纹，但跳过未变化图集合成。规范化数值后序列化保证相同输入字节一致；包先写 pending，再原子替换，失败保留旧输出。receipt 缺失或过期会阻止正式导出。

## 运行时与资源所有权

- `AstraeonContentBundle` 校验包集合和轻量定义；`WorldContent` 装配稳定模型/共享材质/物品目录，无逐体素 GDScript 读取。
- C++ `AstraeonVisualCache` 注册视觉索引，WorkerThreadPool 执行读盘/校验/解压。每包共享只读索引，读操作同包串行，不同包可并发。
- preload 在进入世界前加载并固定驻留；按需资源由区段绘制、选中物品及可见图标持有引用，无引用进入温缓存。共享资源被任何 preload 引用便固定驻留。
- 人物移动预测位置附近24m水平/垂直范围内，原生加载/生成结果批量报告贴图需求；预取引用在停止需求、反向或传送后撤销。温数据的可见返回继续由网格依赖申请，预取不扫描整个世界高度。
- 网格完成后原生批量收集实际材质依赖，纹理与光照页齐备才激活绘制。碰撞不等待视觉。到达/回收仅改变稳定材质的纹理绑定，不重新烘焙库或因贴图完成重建几何。
- 放置预先请求资源，未就绪时不提交背包/世界事务；快捷栏预取降低等待。UI只为可见图标持有引用。
- 世界退出等待自身读取任务并释放缓存；缓存实例不跨世界共享，旧世界结果不会发布给新世界。

| 数值配置（cache节） | 默认 |
| --- | ---: |
| visual_cpu_mib | 64 |
| visual_gpu_mib | 128 |
| visual_warm_seconds | 30 |
| visual_upload_usec | 500 |
| visual_upload_bytes | 2097152 |
| visual_jobs | 2 |

视觉上传计入 VoxelEngine 的2ms总提交软预算；不可中断的一次纹理创建允许超预算并计数。活动资源不驱逐，固定资源超过目标在进入世界前报错；资源错误/容量压力可在缓存面板看到。CPU/GPU数字是受管理的像素载荷估算，不包括驱动、ShaderMaterial、Godot对象等全部内存。原生section预算预留视觉CPU容量，避免各模块重复使用总预算。

## 世界与 Mod

每世界 `content_registry.0/.1` 保存稳定状态键到 uint16 的映射，空气固定0、总量65536。新状态追加，安装顺序/排序变化不重排旧ID。逻辑契约改变、缺失既有状态/包拒绝进入，纯视觉更新不改变ID。注册表带代次和SHA-256，双记录持久化完成后才发布新ID。

Region格式3绑定世界随机标识，生成版本仍2，不再绑定整个当前目录哈希；背包/玩家/掉落物格式4也绑定同一世界标识。区段CRC/双记录及背包恢复日志保持。旧原型世界保留且明确拒绝，无删除、迁移或旧格式读取器。

主菜单 Content Packages 可安装包到 `external_data/blocks/` 并选择启用项，设置存于 settings.cfg 的 content节（format1）。进入世界时固定本次包集合。新物品加入创造目录，沿用选择、朝向放置、挖掘及事务保存；不会自动改变世界生成。

实现入口：`game/data/native/content/`、`game/shading/native/content/`、`game/world/native/persistence/astraeon_content_registry.*`、`tools/content/`。测试和报告见 [内容测试](../../test/content/README.md)。

## 验证边界

功能与阶段测量见 [2026-09-27 报告](../../test/content/reports/2026-09-27_content_packages/README.md)。后续性能测试按用户指令暂停。SDK 独立冷导入因进程预检拒绝访问未完成；发布前需构建匹配当前源码的 release 扩展并验证导出，不能使用旧 release DLL。制作 SDK 仅包含 editor/debug 扩展。

旧原型存档缺少注册表时，Main 提供显式「创建新世界（保留旧存档）」与返回主菜单入口。点击后在原目录同级创建新世界，并将目录名保存到 settings.cfg 的 world 节（format=1、active_slot）；下次启动读取该选择。禁止删除、解释或转换旧区段，原有建筑/背包不会继承。[验证：13项通过](../../test/content/reports/2026-09-27_old_world_entry/README.md)。

物品记录的 block 是必填字符串：空字符串表示非放置物品，非空按正常方块引用/依赖校验；无 block 时 orient_to_face 必须为 false。非放置物品不会参与方块掉落唯一性校验或体素状态注册。内置剑、铲、镐、斧以此方式发布，图标沿用视觉载荷和按需缓存。

## 裂纹纹理组编译与读取

当前编译器为方块记录写入必需的 `breaking` 字典，禁用或水体写空字典；非空包含 `visual`、`resolution`、`stages=10`、`tint`、`strength`。启动时校验元数据及视觉载荷索引，缺少当前字段的旧内容包明确拒绝，需重新编译；本项不改变世界逻辑状态契约。

制作输入为 `BlockAppearance.breaking` 的十阶段条带，单独编译为 AVT1 RGBA8 视觉载荷，按最终像素去重，不按方块数/朝向重复图片。裂纹参数内嵌在方块文件；条带通过包工程 image_sources 和方块 breaking 图片槽关联。BlockAppearance 默认不隐式引用原版纹理组，原版方块文件显式选择 common/wood。构建收据包含被引用的源图片，修改组或图片会使部署收据过期。SDK 从当前资源类型和单文件示例生成，不维护另一套代码。

裂纹资源不因方块 preload 而固定驻留：仅正在挖掘时通过已有 C++ 视觉缓存 request/release，未使用的组不读取像素、不分配纹理；发布与回收使用原有预算和引用保护。基础方块视觉仍按各自 load_policy 运行。测试见 [裂纹验证](../../test/content/reports/2026-09-27_breaking/README.md)。

当前编译器 1.5 增加必填挖掘逻辑记录：方块 required_tool_tag / mining_recovery_seconds，物品 tool_tags / mining_speed。原生读取校验拒绝缺字段旧包；更新资源后重新编译。制作字段与数值见 [挖掘规则](../gameplay/mining.md)。
