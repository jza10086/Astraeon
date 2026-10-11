# 2026-09-27 资源整合功能验证

状态：功能验证通过；未执行性能测试。Godot 4.7 stable，Windows x64。内容制作格式 2、内容 API 1、容器 1、编译器 aeb-content-1.4。本批无原生 DLL 修改。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 单文件方块保存、重载、二次修改，原版输入不变，绝对/相对图片路径等价，源图移除后载荷可读，损坏/缺失图片拒绝并保留包，旧制作格式拒绝 | 33 / 33 | authoring_acceptance.log |
| 16/32/64/128 像素，二进制确定性、缓存命中、损坏/截断拒绝 | 26 / 26 | authoring_codec.log |
| 包依赖/重复 ID/旧世界拒绝、视觉更新 ID 稳定 | 10 / 10 | authoring_validation.log |
| Main 原版+Mod 目录、按需纹理、放置、挖掘、保存、反序包重开 | 17 / 17 | authoring_mod_loop.log |
| game/test/tools/content/addon 脚本加载 | 182 / 182 | authoring_scripts_v2.log |
| 原版、示例 Mod、光影测试包构建 | exit 0 | 三份 build 日志 |
| 本地构建收据校验 | 33 项源依赖通过 | tools/content/verify_deployment.py |
| SDK 生成/Resource 外部依赖闭包 | 28 个文件；0 个缺失引用 | tools/content/build_sdk.py |
| 编辑器导出插件/面板脚本检查 | valid=true | MCP script_check；编辑器扫描完成后无新增 error |

原版编译产物 15,082 字节，7 个唯一视觉载荷；含 5 种普通方块、1 种水体和 9 种物品。整合前后的方块/物品运行时记录逐项相等（包括视觉哈希和状态）。只改变制作组织，不改变存档格式或已有内容 ID。

命令入口：匹配引擎的 --headless --path F:/GodotProjects/Astraeon --script res://test/content/gdscript/test_authoring.gd；codec、validation、scripts 同样运行对应脚本。mod_loop 使用图形运行（去掉 --headless）。每次启动记录 PID、启动时间、引擎、工程和用途，仅回收测试拥有的进程。临时工程、源图及测试世界位于 tmp/content/，未修改用户存档。

`mod_world.png` 是短时 Main 事务验证截图：可见编译的 Mod 手持纹理。拍摄发生在保存阶段、16m 测试范围和地图尚未完全稳定时；不是地形完整性、美术或帧率验收，不引用 HUD 帧率作为性能结果。

诊断：测试环境存在 Windows 根证书读取失败及第三方 MCP 注册目录写入拒绝。损坏 PNG 用例有预期的 ERR_FILE_CORRUPT 日志。上述与断言结果分开记录；没有忽略脚本/着色器错误。早期迁移中的资源标签顺序错误已修复，最终全脚本检查通过。

边界：没有执行规模/移动性能测试、独立 SDK 冷导入或完整 release 可执行文件导出。源图/制作资源导出排除策略已实现、静态检查通过；不将其描述为 release 安装包验收。专用资源编辑器 UI 仍为后续工作，当前通过 Godot Inspector + Content Packages 面板编辑/编译。
