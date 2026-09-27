# 项目本地存储验证

日期：2026-09-27；Godot 4.7 stable / Windows D3D12。现有 ASTRAEON 编辑器完整刷新导入，独立图形测试退出后检查日志。

- `test_local_storage.gd`：11 checks, 0 failures，exit=0（PID 41572，2026-09-27T10:03:49Z）。验证项目根目录解析、设置/存档/人物/方块目录、主菜单设置入口、目录可读、内容包选择及共享配置保留。
- `character_import_smoke.gd`：9 checks, 0 failures，exit=0（PID 31576，2026-09-27T10:03:55Z）。输出人物目录为 F:/GodotProjects/Astraeon/external_data/characters。
- 最终日志 local_storage_final.log、local_character_import.log 无 SCRIPT ERROR / ERROR:。未重跑完整原生世界与性能测试，未验收导出包。
- 项目编写的 game、tools、addons/astraeon_content 以及 test 可执行源码检索没有 user://、get_user_data_dir 或 AppData 写入入口；历史报告保留原始路径。
- .gdignore 阻止两个数据目录参与编辑器导入；git check-ignore 确认设置、世界文件、GLB 和 .aebpack 内容均忽略，仅提交目录骨架。

## 数据复制

从旧 ASTRAEON 系统用户数据目录，将设置、worlds、characters、mods 原样复制到新目录，合计 603 个文件、501191315 字节。逐文件 SHA-256 验证副本，复制前后源文件哈希一致；不转换任何格式，不覆盖不同内容的目标，不删除原件。不存在的 mods/目录没有生成虚构数据。复制报告位于 tmp/local_storage_copy.json。

## 边界

业务文件不再读取旧路径，旧格式数据仍可被各模块拒绝。Godot/MCP 自身的全局偏好、驱动缓存、鉴权和注册文件未迁移，不能推断整个进程没有系统用户目录写入；具体说明见 docs/core/local_storage.md。应用文件日志路径已指定为 res://runtime_data/logs/godot.log。
