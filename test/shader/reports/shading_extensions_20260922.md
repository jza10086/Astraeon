# 光影扩展验证 · 2026-09-22

当前状态：根工程导入、独立 GPU 编译和短时组合运行通过。核心逻辑 468 项、最终组合检查 513 项断言均通过，实际截图已检查；完整键鼠人工验收和正式性能基准仍独立进行。

| 检查 | 结果 | 证据 |
|---|---|---|
| Godot 版本／渲染器 | 4.7.stable.official.5b4e0cb0f / Forward+ / D3D12 / RTX 3060 Laptop | `tmp/shading-shader-probe.log` |
| 资源路径、显式类型扫描 | 通过 | `tmp/check_shading_paths.py` |
| 迁移后 Python 运行器语法／性能计划预览 | 通过；166 个历史工作负载用例；227 个配置字段，新增字段明确不评级 | 仅计划预览，没有执行性能测试 |
| 核心配置／UI／预算／湿润逻辑 | 468 项断言，0 失败 | `tmp/shading-logic.log` |
| 新增资源与控制器独立解析 | 通过 | `tmp/check-*.log` |
| 材质着色器与计算着色器 GPU 编译 | 通过，退出码 0，无脚本／着色器错误 | `tmp/shading-shader-probe.log`、`tmp/shading-shader-probe.png` |
| 完整样板导入、运行和效果组合 | 通过；最终 513 项断言、无脚本／渲染错误 | `tmp/shading-import.log`、`tmp/shading-extensions-final.log` |
| 1080p／1440p／4K／超宽完整面板截图 | 通过；图像尺寸和面板边界检查 | `tmp/shading-extensions-final/` |
| 正式 FPS 基准 | 未运行 | 本次范围不包含 |

普通沙箱 API 探针曾无法读取 Windows 根证书及写入 Godot MCP AppData 注册文件。批准的窄范围引擎执行已正常通过逻辑和 GPU 编译检查；不将早先平台权限错误计作已修复的项目脚本错误。

根工程导入使用图形设备，`camera_post.glsl` 导入产物已生成。导入退出码 0，无脚本／解析错误；退出时出现一次 `Scan thread aborted` 警告，后续完整场景运行正常。

首次组合运行揭示 D3D12 场景颜色纹理不具备 transfer-source 标志，直接 `texture_copy` 会失败。已改为独立 compute 采样复制，避免读写同一纹理；重跑后没有该错误。最终增加了可见日月方向的光束截图对照、SSAO 像素变化断言和真实相机横移，避免把无效观察角度当作效果通过。

最终截图覆盖默认、全部新效果关闭恢复、两种光束、彩色玻璃阴影、降雨湿润、手持光、自动曝光／景深／色差／运动处理、四种面板分辨率。截图中的瞬时 FPS 只是现有 HUD，不作为性能数据或与历史基准对比。

## 截图

- [彩色玻璃阴影与材质样块](screenshots/20260922/glass-and-metal.png)
- [地下手持光](screenshots/20260922/handheld-cave.png)
- [屏幕空间光束](screenshots/20260922/screen-rays-visible.png)
- [镜头效果组合](screenshots/20260922/camera-effects.png)
- [4K 面板](screenshots/20260922/extensions-layout-3840x2160.png)

仍需人工评估视觉参数：当前光束用强度 1.0 做可见差异验证，默认强度为 0.3；金属样块没有额外环境反射，暗面偏黑；彩色阴影仍仅最近一层；自动焦点不检测水、玻璃和人物，运动模糊不处理透明物体独立速度。功能测试不等同于艺术效果或性能验收。

实现接口依据 [Godot 4.7 CameraAttributesPractical](https://docs.godotengine.org/en/4.7/classes/class_cameraattributespractical.html)、[Compositor API](https://docs.godotengine.org/en/4.7/tutorials/rendering/compositor.html) 和 [Forward+ 渲染源码](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)；未改动引擎底层。
