# MakeUp Ultra Fast 光影模块初步分析

日期：2026-09-13。状态：源码参考与设计建议，尚未实现光影模块；没有启动新的性能测试。圆形区块加载保持不变。

## 参考版本

官方仓库：https://github.com/javiergcim/MakeUpUltraFast

版本9.5e；提交 `68d2cc033c285f2c424d73e5202d765c57095e7f`（2026-09-12），查询时256 stars。已下载完整源码和LICENSE到 `tmp/makeup-review/MakeUpUltraFast-68d2cc033c285f2c424d73e5202d765c57095e7f/`；该目录为临时研究材料，不进入运行依赖。固定来源与ZIP哈希见 [来源记录](makeup_ultra_fast_source.json)。

许可证为LGPL-3.0。README中的欢迎修改和署名说明不替代LICENSE。当前仅参考结构和算法；若后续直接移植代码，应保留作者与许可声明，并按实际采用方式处理LGPL相应义务，不能只当作MIT代码加一行署名。

## 源码结构与发现

| 源码位置 | 用途 | 可借鉴点 |
|---|---|---|
| shaders/shaders.properties | 预设、菜单、CPU侧表达式与program启用条件 | 预设由同一组独立选项组成；shadowless档保留其他效果 |
| shaders/lib/config.glsl | 编译期开关、质量级别、常量 | 开关控制代码和采样；质量与视觉强度分开 |
| shaders/common/ | 不透明材质、透明材质和各合成阶段的公共入口 | 入口按渲染职责分离，避免每个维度复制效果代码 |
| shaders/lib/ | AO、水、阴影、云、光束、Bloom、抗锯齿等函数 | 算法尽量写成可复用函数 |
| shaders/src/ | 插入main函数内部的共享代码片段 | 可参考职责划分；Godot新代码优先明确函数参数，避免隐式依赖太多局部变量 |
| shaders/world0、world-1、world1 | Minecraft维度入口与宏 | Astraeon不用继承这些维度与引擎兼容层 |

核对的是实际源码，不只读取功能列表：

- `shaders.properties`显式用SHADOW_CASTING关闭shadow程序；其他效果通过#if/#ifdef排除计算。关闭功能不代表所有公共全屏阶段都会消失。
- `composite1_fragment.glsl`按BLOOM/DOF启用相应采样和mipmap，两个效果同处一个阶段。模块独立不等于每个模块增加一个全屏pass。
- `bloom.glsl`在较低mipmap层采样。默认BLOOM_SAMPLES=3，但每次循环四次纹理采样，因此是12次采样，不是3次。mipmap生成也有成本。
- `ao.glsl`默认AOSTEPS=5，每步正反两个深度采样；AO强度只改变视觉，降低强度并不减少采样次数。
- 反射分关闭、快速翻转图像近似、屏幕空间步进三档。低档不是准确的平面反射；不能照搬其伪影作为质量目标。
- VOL_LIGHT=1使用基于屏幕深度的光束；VOL_LIGHT=2依赖阴影贴图进行体积计算。性能需看场景与实现，不能仅按名字判断哪档一定更快。
- TAA、降噪、运动模糊共享历史/重投影信息。关闭AA后低采样效果可能更显噪，需要明确退化方式。
- 曝光通过低分辨率mipmap和历史值平滑计算；部分日夜参数在uniform表达式或顶点阶段预计算，避免每个像素重复求值。
- 缓冲格式按用途选择；例如没有DOF时主颜色和历史使用R11F_G11F_B10F，有DOF时使用RGBA16F。Godot应遵从自己的缓冲约定，不能直接更改引擎内部格式。
- 开发说明的部分缓冲描述已落后于代码：例如Bloom实际准备在colortex0并由composite1读取，不能机械照抄文档中的旧缓冲编号。
- `src/light_vertex.glsl`使用Minecraft提供的lmcoord.x方块光、lmcoord.y天空光。MakeUp没有替Astraeon实现光传播，也不是完整的动态GI系统。

## 建议模块

开销为实现前的相对估计，不是本机测试数据；不能据此承诺FPS。下表默认策略仍待视觉样板确认。

| 模块 | 独立选项 | 性能策略及建议 |
|---|---|---|
| 天空与日夜色彩 | 天空增强、昼夜动态分别开关；太阳/环境光色彩 | 先做，低成本优先；关闭动态时冻结时间，关闭天空增强时保留基础天空 |
| 曝光与色彩 | 自动曝光、调色、锐化、色觉辅助分别开关 | 自动关闭时使用固定曝光；保留正确HDR到显示输出，不把整个输出转换关掉；合并兼容的轻量运算 |
| 太阳/月亮阴影 | 开关、距离、分辨率、过滤质量 | 先做；阴影距离独立于256体素地形视距，关闭时跳过自身阴影绘制 |
| AO | 顶点AO与屏幕空间AO分别开关/调强度 | 顶点AO作为低成本默认，SSAO后加；避免叠加过暗。现有顶点AO写入颜色，运行时独立调整可能需调整材质数据，不应每帧重建网格 |
| 距离雾与水下雾 | 两者分别开关、浓度/颜色 | 先做距离雾，匹配天空与圆形远景；不是体积雾，不强制依赖光束 |
| 植被风动与透光 | 风动、背光透亮分别开关 | 顶点动画，按距离衰减；阴影阶段必须使用一致变形 |
| 水面 | 波纹、吸收/深浅、折射、反射分别开关 | 基础水先做；反射先天空回退再评估SSR。仅水面存在/可见且需要时申请额外资源 |
| 材质高光 | 开关、粗糙度/强度 | 先使用Godot材质，局部材质启用；湿润等效果后续另议，不必把所有方块都变成镜面 |
| Bloom | 开关、强度、质量 | 先尝试内置Glow，使用低分辨率链；初始均衡档可弱开，保留关闭选项 |
| 抗锯齿与时域稳定 | 关闭/FXAA/TAA等互斥档位，锐化独立 | 优先引擎实现；保持像素贴图辨识度；新增/移除区块、植被和水面的历史失效需验证 |
| 云 | 关闭/便宜二维云/体积云；质量与速度 | 先二维云；体积云后置，低分辨率、有限步数，反射中使用更低质量 |
| 光束与体积雾 | 关闭/屏幕空间光束/真正体积散射 | 后置；两种模式是不同算法，阴影关闭时体积模式应禁用或明确回退，不能暗中重开阴影 |
| 彩色透射阴影 | 独立开关 | 后置且默认关；Minecraft自有shadowcolor缓冲，Godot没有可直接一一对应的现成移植路径 |
| 镜头效果 | 景深、运动模糊、色差各自独立开关 | 默认全关，适合摄影/偏好选项；不应作为基础画面好看的前提 |

另有一个世界系统基础：天空光/方块光传播与增量更新。它应与视觉特效设置分开管理，确保关闭后期、阴影或AO后，屋内、洞穴和火把的基础明暗逻辑仍正确。当前项目尚未具备这部分，不应把MakeUp的输入当成现成功能。

## Godot落地方式与边界

建议采用“现有渲染能力优先，必要时局部自定义”的组合：

1. Godot内置：方向光和阴影、Environment曝光/调色/雾/SSAO/Glow、Viewport抗锯齿。
2. 专用材质与Sky shader：方块光采样、水、植被、天空和二维云。
3. 少量CompositorEffect：只有内置能力无法满足时再做自定义光束、特殊降噪等。它提供渲染阶段回调，但不是完整的OptiFine/Iris可替换管线。

Godot Compositor的POST_TRANSPARENT回调在内置后期之前，不是MakeUp的最终屏幕输出阶段；不要直接把final.glsl放进去后再叠加一套Godot色调映射。其代码运行于渲染线程，需要按引擎规则管理资源与线程访问。

MakeUp依赖GLSL 120、Minecraft lightmap、方块ID、gbufferProjection、colortex/depthtex/shadowtex等输入。Godot的深度约定、坐标空间、透明顺序和缓冲绑定不同，不能直接安装或简单改后缀使用。Godot SSR只反射深度中存在的不透明几何；水、玻璃和屏幕外内容需要明确回退。

不将SDFGI/VoxelGI作为第一阶段默认依赖，先完成该风格的直接光、基础光传播和轻量效果。

## 真正有效的模块开关

- 统一配置保存enabled、quality、视觉参数；画质预设只是填写这些配置，用户仍能逐项覆盖。
- 关闭效果后跳过模块自身绘制/compute与独占更新；其缓冲在没有其他消费者时才释放。共享深度/历史不能被错误释放，也不能为关闭的效果继续单独生成。
- 简单调色、锐化等在阶段兼容时可合并。不要为了模块化建立十几个全分辨率来回拷贝的pass。
- 采样数、分辨率、距离决定主要计算量；强度接近零不等于便宜。质量档位应调整真正的工作量。
- 抗锯齿/降噪依赖明确：关闭TAA后可用确定性采样、空间滤波或接受更高噪声；不静默重开TAA。
- 历史缓冲在传送、分辨率改变、相机切换时重置；区块编辑与加载造成的局部遮挡变化应拒绝无效历史，防止残影。
- 控制shader变体数量，预热实际画质组合，避免游戏过程中开关引发编译卡顿。
- 120FPS总帧预算8.33ms；目前部分场景已经超标，不能承诺叠加光影仍保持120FPS。后续看模块增量GPU时间、CPU提交、P95/P99和内存，不凭“Ultra Fast”名称估算。

## 推荐推进顺序

第一阶段：天空/日夜色彩、方向光阴影、曝光调色、距离雾、现有AO、抗锯齿。做昼间、日落、阴影下、屋内四个固定视点的视觉样板。

第二阶段：体素基础光照、水面、植被、高光、可选SSAO和Bloom。

第三阶段：体积云、光束/体积雾、彩色阴影与摄影效果。每个模块具备独立开关和明确定义的回退。性能验证另行授权后进行，本轮只做源码研究。

## 源码与文档入口

- [README.md](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/README.md)
- [ForDevelopers.EN.md](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/ForDevelopers.EN.md)
- [LICENSE](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/LICENSE)
- [shaders/shaders.properties](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/shaders.properties)
- [shaders/lib/config.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/lib/config.glsl)
- [shaders/src/light_vertex.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/src/light_vertex.glsl)
- [shaders/lib/bloom.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/lib/bloom.glsl)
- [shaders/lib/ao.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/lib/ao.glsl)
- [shaders/lib/water.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/lib/water.glsl)
- [shaders/common/composite_fragment.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/common/composite_fragment.glsl)
- [shaders/common/composite1_fragment.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/common/composite1_fragment.glsl)
- [shaders/common/composite2_fragment.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/common/composite2_fragment.glsl)
- [shaders/common/final_fragment.glsl](https://github.com/javiergcim/MakeUpUltraFast/blob/68d2cc033c285f2c424d73e5202d765c57095e7f/shaders/common/final_fragment.glsl)

- [Godot Compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html)
- [Godot CompositorEffect](https://docs.godotengine.org/en/stable/classes/class_compositoreffect.html)
- [Godot环境与后期](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html)
