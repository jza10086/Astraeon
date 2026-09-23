# 主世界光影接入验证（2026-09-23）

环境：Godot 4.7 stable，Forward+ / D3D12，RTX 3060 Laptop。使用真实 main.tscn、原生地形/存储/网格和正式人物；测试存档与设置位于 tmp/world-shading，不改用户存档。

| 检查 | 结果 |
| --- | --- |
| C++ editor / template_release | 编译与安装成功 |
| 原生派生光场及主世界组合 | 23 项通过，退出码 0 |
| 原光影样板共享着色器回归 | 283 项通过，退出码 0，19 张截图 |
| 运行日志 | 无 SCRIPT ERROR、ERROR 或着色器编译错误 |
| 主世界截图 | 日间、夜间、三种反射、水下、雨天、设置菜单，共 8 张 |
| 编辑器完整导入 | 未完成最终复验，见下文 |
| 正式性能基准 | 未执行，截图瞬时 FPS 不用于性能结论 |

已修复实测发现的两个接入问题：原 max_view_distance 将数据观察器的垂直范围截断，引起地表缺少天空光；生成器水位填充上界为半开区间，水面实际为 32，而非 33。修正后对相同主世界重新运行通过。

初次完整导入遇到编辑器 DLL 临时副本无法写入；随后检测到另一个 ASTRAEON 编辑器连接。该进程尚需关闭重启来重载最后编译的原生类。MCP 子客户端刷新又返回 AUTH_FAILED / no registry entry，未改动鉴权配置或绕过权限。独立游戏进程成功加载最终 DLL 并通过上述测试，但这不代替编辑器的最终全量导入验收。

[日间](screenshots/world_shading/day.png) / [夜间发光石](screenshots/world_shading/night.png) / [平面反射水面](screenshots/world_shading/water-2.png) / [F6 设置](screenshots/world_shading/settings.png)。

本轮截图为 1280×720 短时功能检查；没有重新做 1080p/1440p/4K/超宽屏人工 UI 验收。完整范围、接口与限制见 [主世界光影](../../../docs/world_shading.md)。
