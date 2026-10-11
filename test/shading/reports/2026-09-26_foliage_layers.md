# 树叶层次方案验证

日期：2026-09-26。状态：实现及功能验证完成，视觉偏好和性能分档待人工评估。

## 环境与范围

Godot 4.7.stable.official.5b4e0cb0f；图形检查 D3D12 / Forward+，RTX 3060 Laptop GPU，1920×1080。
生产网格继续使用当前 Voxel Tools C++；本次未修改或重新编译 DLL。
树叶原有棋盘纹理保留。没有更改逻辑透光、世界存档格式或用户存档。

## 方案与数量

下表为 1×1×N 树叶排列的原生网格四边形数（包括不同朝向），不是绘制耗时：

| 方案 | 一层 | 两层 | 四层 |
| --- | ---: | ---: | ---: |
| 外壳剔面 | 6 | 10 | 18 |
| 内部层叠 | 6 | 12 | 24 |
| 内部层叠＋纹理错位 | 6 | 12 | 24 |

外壳保留原双面显示，层叠采用背面剔除；相邻两个反向面的正面分别面向两侧，避免共面双面重复着色。方案 2 使用整数世界坐标哈希和 16×16 图块内平移，负坐标同样固定，不按帧随机。

## 验证结果

- 初次原生网格回归 35 checks / 0 failures。
- 实际图形回归 54 checks / 0 failures，退出 0；包括上述 35 项与 19 项 UI 切换、光照版本不变、样板 shader、截图检查。
- 随后增加生产 world_shading / VoxelTerrain 依赖切换检查，最终原生及配置回归 40 checks / 0 failures，退出 0。这 5 项是额外的主世界装配调用检查，不是主世界流式大地图图形或性能测试。
- 模式切换序列 0 → 1 → 2 → 1 → 0 → 2；1/2 切换不更换 mesher。0/1 切换创建新库和 mesher，现有原生 set_mesher 重置任务依赖；未改权威体素。
- 覆盖叶/石交界、负/正 section 接缝、1/2/4 层面数、单/双面 shader、配置保存重载及默认值、共享模板不变。
- 同一位置截图可见两层和四层的遮挡与浓度差异，错位模式改变孔洞组合；斜视及风动截图已检查。
- 经已确认项目路径的 MCP 刷新并等待扫描结束，再启动普通 shading_sample 检查；内部层叠与错位模式均可运行，运行日志未出现 SCRIPT ERROR、ERROR 或 shader 错误。最终留在树叶观察点、错位模式，仅运行时切换，未保存该选择。

## 工具和环境异常

首次工具链 RunScript 默认轮转 user://logs 时发生写入失败，随后原生崩溃，测试未开始；不能算测试失败或通过的代码证据。后续独立进程显式使用项目 tmp/foliage 内的日志。

沙箱独立进程日志仍有系统根证书读取失败、MCP 用户目录注册写入警告；图形进程另有 shader 磁盘缓存保存失败。这些调用与材质编译失败不同，功能断言及截图完成，但不把这两份日志描述成“全日志无错误”。后续普通编辑器 MCP 启动的图形样板无上述运行错误。

## 命令与证据

测试脚本：test/shading/gdscript/test_foliage_layers.gd。先通过已打开编辑器导入，不额外启动编辑器。

```powershell
& 'F:/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe' --headless --path F:/GodotProjects/Astraeon --log-file F:/GodotProjects/Astraeon/tmp/foliage/headless_final.log --script res://test/shading/gdscript/test_foliage_layers.gd
& 'F:/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe' --path F:/GodotProjects/Astraeon --log-file F:/GodotProjects/Astraeon/tmp/foliage/visual.log --resolution 1920x1080 --script res://test/shading/gdscript/test_foliage_layers.gd -- --visual
```

光影样板左侧：观察点“树叶 1 / 2 / 4 层”；设置“环境 → 植被 → 树叶层次方案”。

[外壳](2026-09-26_foliage_layers/mode_0.png) · [内部层叠](2026-09-26_foliage_layers/mode_1.png) · [纹理错位](2026-09-26_foliage_layers/mode_2.png) · [斜视/风动](2026-09-26_foliage_layers/oblique.png)

源文件 SHA256：
- foliage_rendering.gd: 4BA82DFCB110A3EFDB79EB879543A49A38F7FFC98AA8DD129A1394753C896BE8
- plant_surface.gdshaderinc: 2598D4270D8AD4C3F6794579491A905A42EFBF31723C4AD5B67CAC06C401892D
- test_foliage_layers.gd（追加主世界检查后）: FCE39F8F523E182A455B5A570BF4F8A8F7397986F07D89917B6ED2A6694E8F60

## 已知限制

没有执行性能基准。截图 FPS 包含初始化、切换、限帧和截图影响，不能作为三个方案的性能对照。
密集内部叶面会增加透明裁剪、阴影和反射开销；未实现距离 LOD。
规则棋盘仍有莫尔纹；纹理错位需要可平铺素材，不能完全消除规则测试图案。
光照依旧按原有逻辑遮挡传播，内部树叶可偏暗；此次不修改逻辑透光或叠加额外补光。
