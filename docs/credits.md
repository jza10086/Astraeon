# 来源与许可
- 开发工具：Godot MCP Toolkit 1.0.0；来源 https://github.com/NPGameDev/godot-mcp-toolkit ，从本机 GodotParty/addons/godot_mcp_toolkit 复制；MIT，详见插件 LICENSE 与 ATTRIBUTIONS.md。
- 配套技能：godot-mcp-toolkit、mcp-extension-creator 随上述插件提供，项目内副本位于 .agents/skills/，已按 Astraeon 的类型、依赖和验证规则调整；原版保留于插件 CompanionSkills/。
- 开发技能：godot-project-tooling，从本机个人技能目录复制；保留原脚本与本机工具链配置。
- 默认图标：Godot 项目创建时生成的 icon.svg。
- 当前启动场景使用 Godot 内置几何体，无额外下载的游戏素材。

- 体素示例：Zylann/voxelgame https://github.com/Zylann/voxelgame ，固定提交 4cf747a；代码许可见 benchmarks/voxelgame/LICENSE.md，保留各目录素材和字体许可。
- 体素依赖：Voxel Tools 1.7 GDExtension https://github.com/Zylann/godot_voxel/releases/tag/v1.7x ，MIT；许可保留于基准工程 addons/zylann.voxel/LICENSE.md。

- 圆形加载本地构建：Voxel Tools源码75d3c6d996ed2331c80edcd8c3ebc947afc0f041，加项目 tools/voxel_patches/horizontal_circle.patch；godot-cpp b4ce22a76b56bb5f734a5161d6105eb4b8d1021d（MIT，https://github.com/godotengine/godot-cpp）；SCons 4.10.1仅为本地构建工具。补丁默认关闭，仅基准启用。

- P0 光照样板：复用上述 Voxel Tools mesher；方块配色和天空均为项目自编程序化占位素材。仅参考 MakeUp Ultra Fast 9.5e 的光强/颜色分离思路，未复制 GLSL；固定来源与许可研究见 makeup_ultra_fast_analysis.md。
