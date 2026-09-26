# 来源与许可
- 开发工具：Godot MCP Toolkit 1.0.0；来源 https://github.com/NPGameDev/godot-mcp-toolkit ，从本机 GodotParty/addons/godot_mcp_toolkit 复制；MIT，详见插件 LICENSE 与 ATTRIBUTIONS.md。
- 配套技能：godot-mcp-toolkit、mcp-extension-creator 随上述插件提供，项目内副本位于 .agents/skills/，已按 Astraeon 的类型、依赖和验证规则调整；原版保留于插件 CompanionSkills/。
- 开发技能：godot-project-tooling，从本机个人技能目录复制；保留原脚本与本机工具链配置。
- 默认图标：Godot 项目创建时生成的 icon.svg。
- 当前启动场景使用 Voxel Tools 原生体素地形与项目方块配色；玩家模型来源见下方 Basic Voxel 条目。

- 体素示例：Zylann/voxelgame https://github.com/Zylann/voxelgame ，固定提交 4cf747a；代码许可见 benchmarks/voxelgame/LICENSE.md，保留各目录素材和字体许可。
- 体素依赖：Voxel Tools 1.7 GDExtension https://github.com/Zylann/godot_voxel/releases/tag/v1.7x ，MIT；许可保留于基准工程 addons/zylann.voxel/LICENSE.md。

- 圆形加载本地构建：Voxel Tools源码75d3c6d996ed2331c80edcd8c3ebc947afc0f041，加项目 tools/voxel_patches/horizontal_circle.patch；godot-cpp b4ce22a76b56bb5f734a5161d6105eb4b8d1021d（MIT，https://github.com/godotengine/godot-cpp）；SCons 4.10.1仅为本地构建工具。补丁默认关闭，仅基准启用。

- P0 光照样板：复用上述 Voxel Tools mesher；方块配色和天空均为项目自编程序化占位素材。仅参考 MakeUp Ultra Fast 9.5e 的光强/颜色分离思路，未复制 GLSL；固定来源与许可研究见 makeup_ultra_fast_analysis.md。

- P1/P2 水面、草/树叶裁剪图案、风动和二维云为项目自编程序化材质，未引入新第三方美术或复制 MakeUp GLSL。AO/阴影/雾/抗锯齿/Glow 复用现有 Godot 与 Voxel Tools 能力。

- 光影更新：简化体积云参考 MakeUp Ultra Fast 9.5e（固定提交 68d2cc033c285f2c424d73e5202d765c57095e7f）的二维高度场体积采样路线，采用项目自编 Godot shader 与 Godot FastNoiseLite/NoiseTexture2D 生成纹理；未复制其 GLSL 或纹理。水面厚度吸收、遮挡感知补光与调试控件均为项目自编。

- 2026-09-15 环境光表面插值、方块云合并网格与二值底面云影为项目自编；覆盖图由 Godot FastNoiseLite 生成，未引入第三方云素材。

- Basic Voxel 标准素体：来自用户本地 F:/AstraBlender/Projects/basic_voxel/exports/godot/basic_voxel.glb，原样复制六动作版，SHA-256 为 383a153f18ee1132af0a55f8e076eafd3caa591475aa19f748e92f59e85028d6。制作参数见该目录 README 与 docs/resource_specifications.md；未附独立再分发许可，不另行声明授权。

- 主工程原生后端：固定 Voxel Tools 与 godot-cpp 源码保留在 native/voxel_tools/ 和 native/deps/godot-cpp/，保留各自 MIT 与第三方许可证。部署插件保留 addons/zylann.voxel/LICENSE.md。项目修改见 docs/world/native_voxel_backend.md。

- 历史 HK416 V8（已从游戏资源移除）的移动动作参考 CMU Graphics Lab Motion Capture Database，Subject 16 Trial 35 与 Subject 09 Trial 01。来源：https://mocap.cs.cmu.edu/ 。保留以下历史致谢，不将其未经核实地归为 Basic Voxel 的来源：

The data used in this project was obtained from mocap.cs.cmu.edu.
The database was created with funding from NSF EIA-0196217.

- Water and light shafts: MakeUp Ultra Fast algorithm reference (Javier Garduño, upstream LGPL-3.0); independently adapted GPU implementation. See [implementation notes](shading/water_light_shafts.md).
