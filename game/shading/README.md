# Shading：光影与渲染表现

正式模块名称统一为 shading，不新建 game/lighting 或 lighting 模块别名。职责包括天空/日夜、环境、阴影、水面、云和后处理。

后续按实际功能建立 gdscript/、native/、shaders/、resources/、scenes/、assets/，C++ 重计算与 GDScript 编排分目录。当前光影样板仍位于 benchmarks/voxelgame/project/astraeon_lighting，尚未迁入生产模块；测试样板迁移由对应 agent 负责，目标 test/shading/。历史文件名不在本次批量改名。
