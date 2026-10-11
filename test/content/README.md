# 内容包功能验证

使用当前 Godot 4.7 和匹配的原生扩展，输出写入 `tmp/content/`，世界数据使用测试专属目录。遵循根目录 AGENTS 的编辑器与进程规则；编辑器打开时不另行冷导入。

先通过编辑器 Content Packages 面板构建原版包；制作测试夹具时运行 `build_examples.gd` 和 `build_shading_pack.gd`。以下脚本均位于 `test/content/gdscript/`，使用 `godot --path . --script res://test/content/gdscript/<脚本>`；仅标注 headless 的脚本可加 `--headless`。启动前按项目流程记录测试进程身份。

| 脚本 | 环境 | 检查 |
| --- | --- | --- |
| test_block_target.gd | 图形 | main 射线选取、边框显隐、距离/水体/暂停、开关截图 |
| test_breaking.gd | 图形 | 两组十阶段裂纹、原生缓存、共享与取消、实际 Shader 截图 |
| test_mining_progress.gd | 图形 | main 生存进度、换目标/取消、完成编辑掉落和保存 |
| test_codec.gd | headless | 二进制校验、确定性、构建缓存、分辨率、纯色与载荷延迟读取 |
| test_runtime.gd | 图形 | 稳定 ID、缓存引用、固定驻留、回收和重加载 |
| test_orientations.gd | headless | 24 个原生朝向、六面 UV、旋转/镜像和共享材质 |
| test_validation.gd | headless | 错误包、依赖、容量、逻辑契约和旧世界拒绝 |
| test_old_world_entry.gd | 图形 | 旧格式提示、显式创建、新世界可玩、保留旧字节与选择持久化 |
| test_main_entry.gd | 图形 | 实际主菜单进入 Main、设置传递、默认原版内容与缓存接入 |
| test_mod_loop.gd | 图形 | 正式世界目录选择、放置、挖掘、保存、重进与 ID 稳定 |
| test_render.gd | 图形 | content_sample 与 shading_sample 收敛后的截图 |
| test_scripts.gd | headless | 脚本加载检查，不替代编辑器导入或图形验收 |

成功须同时核对退出状态、脚本完成标记、失败计数与错误日志，不能只看退出码。`reference_block_builder.gd` 仅用于制作回归和历史路径对照，生产运行不引用它。

`test_scale.gd`、`test_compare.gd`、`test_movement.gd` 为性能测试入口。**2026-09-27 按用户指令暂停后续性能测试；移动/折返测试尚未运行。** 功能检查不会自动运行这些脚本。早期测量保留为阶段证据，不作为最终性能验收。

SDK：`python tools/content/build_sdk.py` 生成 `tmp/content/sdk/`。已验证示例资源重载、编译及包运行；SDK 独立工程的冷导入因进程查询拒绝访问未完成。

阶段结果见 [2026-09-27 报告](reports/2026-09-27_content_packages/README.md)。

裂纹与主世界长按挖掘见 [2026-09-27 裂纹报告](reports/2026-09-27_breaking/README.md)。

工具挖掘与损伤保留：`test_mining_progress.gd`（图形）、`test_mining_data.gd`（headless）。[2026-09-27 报告](reports/2026-09-27_mining.md)包含 0.05 秒结算、标签/速度和恢复延迟的当前验证。
