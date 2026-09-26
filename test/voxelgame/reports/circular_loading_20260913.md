# 圆形加载历史实现与复现

日期：2026-09-13。历史基准环境与命令，不作为当前生产构建或性能结论。

## 实现与复现

基于Voxel Tools 1.7.0，源码75d3c6d996ed2331c80edcd8c3ebc947afc0f041；本地补丁为 tools/voxel_patches/horizontal_circle.patch。

使用 `python tools/build_voxel_circular.py --install` 重建并安装本机Windows编辑器扩展。只给基准启用 `horizontal_circular_loading`，默认关闭，不改变上游示例。圆形模式限定数据/网格均为16体素，必须在添加观察者之前配置。

运行 `python tools/run_voxel_suite.py --run --driver d3d12` 执行256体素矩阵，计时上限30分钟；编译准备单独计时。实际渲染1920×1080，窗口1280×720。历史盒形结果保留，不能覆盖或当成当前圆形结果。

当前本地构建只覆盖Windows x86_64编辑器DLL；导出用的template_debug/template_release仍为上游发行文件。后续需要导出圆形加载版本时，应先对相应模板构建应用同一补丁。原DLL按SHA-256命名备份在tmp/voxel-circular-build下。

针对性验证入口：`godot --headless --path benchmarks/voxelgame/project --script res://astraeon_benchmark/test_circular_loading.gd`（使用项目指定Godot 4.7）。实际原生数据集合与独立的圆盘加邻居集合逐段比较；覆盖负坐标、垂直移动、远距传送、上下边界、半径改变、碰撞标志切换及观察者移除。该检查不代替图形性能矩阵。
