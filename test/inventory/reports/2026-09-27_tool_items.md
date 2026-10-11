# 首版工具物品验证

2026-09-27，Godot 4.7.stable.official.5b4e0cb0f；D3D12 Forward+ / RTX 3060 Laptop GPU。

- 新增工具：剑、铲、镐、斧，每格 1 件，非方块、无放置映射；原创 SVG 图标编译进内置包。
- editor/debug 原生内容校验构建成功，DLL SHA-256 af2ceaa1c11389a762371f10d36d5030a62a78baf7c71efdaffbd3519de9b54a。内置包编译成功，verify_deployment 检查 38 个源文件通过。
- TOOL_ITEMS_TEST：29 项通过，内容包/图标驻留、创造领取、单件上限、交换和存档往返。
- CREATIVE_TEST：56 项通过。旧测试夹具仍使用 states 标识，已同步为当前 world_id 契约后重跑通过。
- WORLD_INVENTORY_TEST：21 项通过，含四种工具拒绝放置且不改体素/不扣物品。
- 所有最终测试退出 0，无 SCRIPT ERROR / ERROR。使用独立进程加载新 DLL；没有关闭用户编辑器，当前编辑器重启后的原生验证、release 导出与人工手感验收未执行。没有实现攻击、工具效率或耐久。

[工具分类截图](2026-09-27_tool_items/tools.png)。最终日志在同名子目录，临时世界在 tmp。

本批依赖工作区正在进行的预编译内容包重构；未将其他模块的未提交重构打包提交。
