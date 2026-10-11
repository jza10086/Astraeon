# 存档选择界面

日期：2026-09-27。Godot 4.7 stable，现有 Astraeon 编辑器，D3D12 Forward+。

种子字段加入前：隔离目录 CRUD 与页面交互 `WORLD_SELECT_CHECK checks=25 failures=0`；标题→创建→可玩原生世界→保存回标题→读取同一世界 `WORLD_SELECT_FLOW checks=6 failures=0`。检查删除取消、默认保留焦点、同名／非法路径拒绝、递归删除仅影响目标、其他设置保留；未删除用户存档。列表与创建表单截图已人工检查。

随后用户要求增加世界种子，并明确“不用反复测试”。种子改动只完成 world_selection.gd、world_select.gd、native_world.gd 的脚本检查（valid=true）和定向编辑器刷新；没有重跑整套运行测试，不把前述通过记录归为种子功能验证。流程测试源已补充固定负种子断言，留供后续需要时运行。

创建页支持整数种子或空白随机；参数保存到对应世界目录 world.cfg，format=1；读取世界时使用该参数文件并由原生区段头再次校验。错误格式不转换。
