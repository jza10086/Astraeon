# 2026-09-27 专用内容编辑器验证

Godot 4.7.stable.official.5b4e0cb0f；Windows x64；渲染检查 D3D12 / Forward+，RTX 3060 Laptop GPU。使用当前 cb85eae308da editor/debug 扩展；本次未构建 DLL、未运行性能基准。

## 结果

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| `./test/content_editor/run.ps1 -Mode Session` | 75 项 / 0 失败 | 原版及示例包使用临时工作副本，源文件哈希保持不变 |
| `./test/content_editor/run.ps1 -Mode Render` | 74 项 / 0 失败 | 实际 Control / 原生材质渲染；截图已另行查看 |
| 连接中的 ASTRAEON 主工作区 | 已加载，可预览与导出 | 确认连接路径为此 checkout；未关闭编辑器或用户场景 |
| 原版 `.aebpack` 编辑器导出 | 成功，15,799 字节，7 个唯一载荷 | 输出文件与 receipt 更新；原版制作内容未改 |
| `python tools/content/verify_deployment.py` | 33 个源指纹通过 | 不代表正式游戏 release 导出验收 |
| SDK 生成 | 61 个输入文件，41 个直接资源引用无缺失 | 使用当前资源类型 / 编辑器 / shaders / DLL；没有另启 SDK 冷导入 |

Session 覆盖私有复制、撤销 / 重做、保存清脏、六面覆盖 / UV / 朝向 / 状态、关联物品单文件归属、保存重载导出、外部文件冲突与明确覆盖、新建三类型资源、复制新 ID、移出保留文件、图片引用保护、缺失图片和跨盘路径。原版两组裂纹随完整资源往返；渲染检查另看最终混合结果。

Render 覆盖草方块、裁剪树叶、发光石、两组十阶段裂纹、物品图标、浅深水池；原生反射标记隔离；关联物品双向跳转；隐藏预览不更新、暂停波纹；折叠设置保存 / 重载；不支持配置拒绝且原文件保留；未保存切换取消 / 放弃。新页与导出使用同一编译记录。

尺寸为 1920×1080、2560×1440、3840×2160、3440×1440，以及模拟停靠后 830×640 工作区；检查列表、滚动属性、预览、工具栏和结果区域边界。额外 24px 字号（150%）检查及右下角颜色弹窗，加入滚动容器以保证小窗口下能访问全部颜色控件。实际编辑器当前缩放已截图；其他系统 DPI / 重启后的编辑器全局缩放尚需人工检查，不将字体模拟等同所有 DPI 验收。

## 截图

| 内容 | 证据 |
| --- | --- |
| 实际 Godot 主工作区 | [live.png](live.png) |
| 裁剪树叶 | [leaves_1080.png](leaves_1080.png) |
| 水体 | [water_1080.png](water_1080.png) |
| 物品 | [item_1080.png](item_1080.png) |
| 常规裂纹 / 木质裂纹 | [cracks_common.png](cracks_common.png)、[cracks_wood.png](cracks_wood.png) |
| 自发光 | [emission.png](emission.png) |
| 1440p / 4K / 超宽 | [layout_2560.png](layout_2560.png)、[layout_3840.png](layout_3840.png)、[layout_3440.png](layout_3440.png) |
| 窄工作区 / 颜色弹窗 | [layout_830.png](layout_830.png)、[color_popup.png](color_popup.png) |

## 诊断与已知边界

独立测试日志记录 Windows 根证书读取错误，以及第三方 MCP 注册器写 AppData 被沙箱拒绝的警告。它们与内容编辑器断言分开记录；没有以退出码单独判通过，也未提升权限或重试写入用户目录。最终测试没有 SCRIPT ERROR 或着色器错误。最终连接编辑器检查没有新增错误。

开发过程中修正了预览相机误带反射专用层、主工作区高度未扩展、Resource 在编辑器中作为 placeholder 无法执行方法、旧编译器缓存及放大颜色弹窗裁切。前期失败不计入以上最终通过结果。按明确文件列表刷新同一编辑器的工具依赖，没有清理生成缓存。

预览为固定环境基本检查，未启动正式世界或传播光，不代表完整昼夜 / 天气 / 水下或 SSR / 平面反射结果。源码保存按文件原子替换，不是整个包工程跨文件原子事务。大型图片的编译仍在编辑器主线程，250ms 是防抖时间，不是编译耗时保证。本轮未实际关闭用户编辑器测试退出对话框，也未执行 SDK 独立冷导入或正式游戏发布导出。

完整日志：[session.log](session.log)、[render.log](render.log)。代码指纹：[fingerprints.json](fingerprints.json)。操作说明：[专用内容编辑器](../../../../docs/tooling/content_editor.md)。
