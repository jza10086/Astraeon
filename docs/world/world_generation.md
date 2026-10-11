# 首版地图生成（生成版本 2）

生产算法位于 game/world/native/generation/astraeon_native_generator.cpp，继续由 Voxel Tools 在线程中按需生成。Y 范围 [-64,192)，水面 Y=32，不支持 LOD。首版仅包含平原、森林、河流、海洋；没有沙漠、山地、洞穴、矿物或水流模拟。

## 分布与分层

四组种子派生的 OpenSimplex2S/FBm 噪声分别控制大陆、河道、森林和地表起伏。陆地为约 42 格的低起伏地表，海床约 20 格；河流沿河道噪声的零等值线切入陆地，河床最低约 27 格，并与海洋共用水位。当前是等高水面的河网原型，没有真实流域、坡降或水文模拟。水下表层使用泥土，露出水面的地表使用草，地下暂时全部使用泥土，以匹配当前批准的数据目录。

森林采用 8 格世界网格，种子散列决定树的位置与高度；三轴木头中生成直立 axis_y，树冠使用树叶。区段生成查询外扩 2 格的树锚点，只写入自身范围，正负坐标和区段顺序不影响结果。出生点附近留出树木空隙。测试布局 biome_layout=1 沿 X 以 1024 格重复展示平原、森林、河流、海洋；默认 0 使用自然分布。

## 数据与渲染接入

主场景读取 `game/data/content/packages/astraeon.aebpack`，WorldContent 从轻量定义构建模型并使用世界追加注册表，空气 `astraeon:air/default` 固定为0。生成器启动时 configure_content 解析必需内容，一次配置后禁止重配，热路径没有逐体素GDScript调用。详见 [内容包](../data/content_packages.md)。

shading 的 BlockLibraryBuilder 启动时编译共享六面图集，支持当前不透明/裁剪颜色贴图、常量自发光及状态旋转。normal/ORM/emission 贴图与混合透明方块尚未接入；不存在逐方块 Material 或 Node。共享水资源提供基础颜色、透明度、粗糙度和高光。主世界已接入原生水网格、波纹、深度吸收、SSR/平面反射与水下判断；这些效果由场景光影配置驱动，不代表按流体资源字段完成全部接入。详见 [主世界光影](../shading/world_shading.md)和[水资源接口](../shading/water_appearance.md)。

## 保存与启动

区域格式版本和生成版本均为 2；头部 128 字节，包含种子、布局、状态数和有序状态 key 的 SHA-256。双记录 CRC 与持久化恢复保持有效。旧版本或状态表不匹配明确拒绝，不迁移、不回退。默认新世界目录 runtime_data/worlds/landscape_v2，不删除旧存档。修改生成规则必须提升生成版本；新增/重排状态会导致现有存档拒绝加载。

验证入口：test/world/gdscript/test_landscape.gd（自然群系、负坐标区段拼接、森林、种子、新状态保存及拒绝旧元数据），test/native_world/gdscript/test_native_world.gd（现有恢复契约）。视觉与长时间性能验收另行进行。


## 验证证据

[历史接入检查](../../test/world/reports/generation_integration_historical.md)，当前测试入口见 [世界测试](../../test/world/README.md)。
