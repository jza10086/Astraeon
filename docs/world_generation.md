# 首版地图生成（生成版本 2）

生产算法位于 game/world/native/generation/astraeon_native_generator.cpp，继续由 Voxel Tools 在线程中按需生成。Y 范围 [-64,192)，水面 Y=32，不支持 LOD。首版仅包含平原、森林、河流、海洋；没有沙漠、山地、洞穴、矿物或水流模拟。

## 分布与分层

四组种子派生的 OpenSimplex2S/FBm 噪声分别控制大陆、河道、森林和地表起伏。陆地为约 42 格的低起伏地表，海床约 20 格；河流沿河道噪声的零等值线切入陆地，河床最低约 27 格，并与海洋共用水位。当前是等高水面的河网原型，没有真实流域、坡降或水文模拟。水下表层使用泥土，露出水面的地表使用草，地下暂时全部使用泥土，以匹配当前批准的数据目录。

森林采用 8 格世界网格，种子散列决定树的位置与高度；三轴木头中生成直立 axis_y，树冠使用树叶。区段生成查询外扩 2 格的树锚点，只写入自身范围，正负坐标和区段顺序不影响结果。出生点附近留出树木空隙。测试布局 biome_layout=1 沿 X 以 1024 格重复展示平原、森林、河流、海洋；默认 0 使用自然分布。

## 数据与渲染接入

主场景显式引用 game/data/block/resources/block_catalog.tres 与 game/data/fluid/resources/astraeon_water.tres。AstraeonWorldContent 在启动时校验并排序方块/状态 key，保留 astraeon_air/default 为 0，末尾追加水；共享状态表同时用于 C++ 生成角色解析、VoxelBlockyLibrary 模型索引及存档校验。生成器必须先 configure_content，一次配置后禁止重新配置。生成热路径没有逐体素 GDScript 调用。

shading 的 BlockLibraryBuilder 在启动时将当前纯色不透明方块编译为共享六面色图集和 ORM 图集，使用状态旋转及 authoring_orientation 解析世界面，因此草顶底和木头三轴均来自数据。当前不支持的贴图、透明模式与发光表面明确拒绝；没有逐方块 Material 或 Node。水使用 WaterAppearance 的固定厚度统一水色、透明度、粗糙度和高光参数，无固体碰撞。波纹、深度吸收、SSR、平面反射与水下效果未接入此地图。

## 保存与启动

区域格式版本和生成版本均为 2；头部 128 字节，包含种子、布局、状态数和有序状态 key 的 SHA-256。双记录 CRC 与持久化恢复保持有效。旧版本或状态表不匹配明确拒绝，不迁移、不回退。默认新世界目录 user://worlds/landscape_v2，不删除旧存档。修改生成规则必须提升生成版本；新增/重排状态会导致现有存档拒绝加载。

验证入口：test/world/gdscript/test_landscape.gd（自然群系、负坐标区段拼接、森林、种子、新状态保存及拒绝旧元数据），tests/native_world/test_native_world.gd（现有恢复契约）。视觉与长时间性能验收另行进行。

## 本次自动验证

Godot 4.7 stable：地图与数据接入 22 项、既有保存恢复契约 18 项均通过；默认自然布局真实主场景出生碰撞就绪并正常保存退出，测试布局流式短烟测通过。editor 与 template_release 原生扩展均已编译安装。已打开编辑器仍使用旧 DLL，需要重启以加载新增原生 API。
