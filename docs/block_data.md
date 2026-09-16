# 方块数据与可替换存储

状态：独立数据模块已完成三后端初筛，当前推荐 DIRECT16 作为活跃区块段基线；未接入主场景地形、挖掘、网格、碰撞或光照系统。测试证据见 [存储初筛结果](block_storage_results_20260916.md)。

## 数据边界

- `game/world/blocks/`：Resource 类型定义、显式状态定义、目录与运行时注册表。
- `storage/`：仅存储一个 16³ 区块段的状态 ID；不创建方块节点，不依赖 Voxel Tools。
- `block_section.gd`：坐标、注册状态范围校验、内容版本与后端转换。
- `default_block_catalog.tres`：空气、石头、发光方块、三轴原木，共 4 种方块、6 个状态。硬度等数值仅为示例。

定义 Resource 由编辑器编辑，不保存某个坐标的实例状态。当前字段为稳定 key、显示名、硬度、碰撞标志、0..15 遮光/发光值与显式状态列表。贴图、网格、掉落、物品和生物未实现，待对应功能接入时添加。

状态 Resource 包含局部 key 与 `Dictionary[StringName, StringName]` 属性，例如 `axis_y` 与 `axis=y`。状态属性当前仅为标签，不能单独覆盖方块硬度、光照等字段；渲染映射未实现。不自动枚举属性笛卡尔积。

注册表 `build()` 先完整校验，成功后复制运行时字段；后续修改原 Resource 不影响它。注册表只能构建成功一次，失败不发布部分数据。空气固定为 0，其余定义及状态按 key 排序。重复 key、空引用、无效标识、无效硬度、超范围光照和超过 65536 个状态均被拒绝。

稳定标识形如 `astraeon:log/axis_y`。key 的组成只允许小写英文字母、数字、下划线、横线和点；方块 key 必须恰好包含一个冒号，状态 key 不含冒号或斜线。空状态列表意味着 `default`。

**运行时 ID 不保证跨内容版本稳定。** `export_states()` 是同一注册表下的独立内存快照，不能直接当正式存档，也不能不经映射导入另一套注册表。存档版本、稳定 key 映射、特殊方块实例都留给后续模块。

## 三种后端

| 枚举 | 表示 | 每段原始载荷 | 主要取舍 |
| --- | --- | --- | --- |
| DIRECT32 | PackedInt32Array，4096 个 ID | 16384 字节 | 简单基线，逐格访问直接 |
| DIRECT16 | PackedByteArray，每格两个字节，用 encode/decode_u16 访问 | 8192 字节 | 较小，但多了编解码调用 |
| PALETTE | PackedInt32Array 调色板、ID 索引字典、PackedInt64Array 位索引 | 随状态数变化 | 纯色段无索引数组；写入可能扩容和重打包 |

三者统一支持 0..65535，比较的是相同容量契约。PALETTE 从 0 位纯色表示增长到 1..16 位；索引不跨 64 位字边界，每个字可能有尾部空位。它借鉴调色板思路，但不是 Minecraft 存档兼容实现。

删除后不自动移除失效调色板项，以避免普通写入触发全段扫描；显式 `compact()` 可以清理并恢复纯色表示。填充或导入会重建内容。调色板允许保留历史项，因此经历大量不同状态写入后可能比直接数组大。

`payload_bytes()` 仅计数组有效载荷，包括调色板整数表；**不含字典、对象、容量预留、分配器及进程总内存**。纯色段返回 4 字节也不意味着整个对象只占 4 字节。

Factory 创建时仍需显式选择；可使用 RECOMMENDED_ACTIVE_BACKEND（当前为 DIRECT16）。推荐来自本机简化初筛，不做自动切换。当前纯 GDScript 方案和独立基准工程的原生 VoxelBuffer 并非等价性能实现。

## API 与坐标

```gdscript
const FACTORY: Script = preload("res://game/world/blocks/storage/block_storage_factory.gd")

@export var catalog: AstraeonBlockCatalog

func create_section() -> AstraeonBlockSection:
    if catalog == null:
        push_error("Missing block catalog")
        return null
    var registry: AstraeonBlockRegistry = AstraeonBlockRegistry.new()
    var errors: PackedStringArray = registry.build(catalog.definitions)
    if not errors.is_empty():
        push_error(str(errors))
        return null
    var section: AstraeonBlockSection = AstraeonBlockSection.new()
    if not section.configure(Vector3i(-1, 0, 0), registry.state_count(), FACTORY.RECOMMENDED_ACTIVE_BACKEND):
        return null
    var stone_id: int = registry.find_state(&"astraeon:stone")
    if not section.set_state(Vector3i(15, 0, 0), stone_id):
        return null
    # 同一份数据转换为另一后端，内容 revision 不变。
    if not section.change_backend(FACTORY.Backend.PALETTE):
        return null
    return section
```

区块列仍为水平 16×16；段为 16×16×16。局部索引 `x + 16 * (y + 16 * z)`，X 最快，其次 Y，再次 Z。世界坐标右移 4 位得到段坐标（向负无穷取整），减去段原点得到 0..15 的局部坐标。负坐标契约见 [voxel_chunks.md](voxel_chunks.md)。

- 原始 Storage 写入失败返回 false，不修改数据；读取要求有效下标。
- Section 越界/未初始化读取返回 -1，写入还校验注册状态数量。
- 整段导入先检查全部 4096 项，失败不改变数据或 revision。
- 相同内容写入不增加 revision；整段内容改变只增加一次。
- 导出与转换产生独立副本，调用方不能通过快照修改原段。
- 当前单所有者模型；没有线程安全保证。后台任务需要独立快照，渲染层之后按 revision 判断结果是否过期。

## 正确性验证

使用项目引擎解析器：

```powershell
./.agents/skills/godot-project-tooling/scripts/invoke_godot.ps1 -Mode RunScript -ProjectPath . -ScriptPath res://tests/blocks/test_block_data.gd
```

覆盖：资源加载与注册、定义顺序、快照隔离、重复及无效定义、三后端随机编辑对照、跨后端转换、原子导入、上限 ID、全部局部坐标、负世界坐标、调色板逐级扩容、64 位符号位、清理及纯色恢复。

2026-09-16：Godot 4.7 stable；回归通过 52511 次断言式检查。该数字包含循环中的逐格校验，不代表 52511 个独立测试场景。微基准入口通过一轮烟测（9 行结果），不作为正式性能结论。未做玩法/视觉验收。

## 后续性能比较入口

已提供 `tests/blocks/benchmark_block_storage.gd`，只在显式运行时计时。通过项目工具链解析器取得引擎路径后：

```powershell
$blockEngine = ./.agents/skills/godot-project-tooling/scripts/resolve_godot.ps1 -ProjectPath . | ConvertFrom-Json
& $blockEngine.path --headless --path . --script res://tests/blocks/benchmark_block_storage.gd -- --rounds=7
```

输出一行 JSON 报告（引擎自身日志可能同时存在）。包含引擎版本、debug 标志、轮数、校验和与每轮原始结果。轮数限制为 1..100；第一轮热身不计入结果，后端次序轮换。

三个固定种子数据集：纯色、8 种分层状态、高多样性。计时项目：整段导入、32768 次顺序读取、8192 次随机读取、8192 次随机编辑、快照导出、整段填充。数据生成不计时；编辑耗时包含必要的调色板增长，所有后端使用同一轨迹。

这是 GDScript 数据微基准，不是最终地形性能结论。后续正式比较应另外记录同规模驻留段的真实内存、分配抖动、跨段邻居扫描、转换峰值、网格/碰撞/光照集成延迟，以及多次运行的中位数和尾部延迟。原生 VoxelBuffer 若进入比较，应使用相同数据集与语义。当前以 DIRECT16 为数据层推荐基线；最终地形集成尚未验收。
