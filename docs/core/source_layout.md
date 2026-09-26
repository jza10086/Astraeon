# 源码目录与装配

```text
Astraeon/
├─ game/
│  ├─ core/main.tscn                     # 应用入口与装配
│  ├─ data/block/
│  │  ├─ gdscript/                      # Resource 类型
│  │  └─ resources/                     # 静态配置、编辑示例
│  ├─ data/fluid/                       # 流体类型与静态水定义
│  ├─ world/
│  │  ├─ gdscript/native_world.gd        # 当前世界编排
│  │  ├─ gdscript/world_content.gd      # 从正式定义构建共享 ID 与外观库
│  │  └─ native/                        # .gdignore，仅项目 C++
│  │     ├─ generation/
│  │     ├─ persistence/
│  │     └─ streaming/
│  ├─ entities/
│  │  ├─ common/gdscript/               # 共享移动与动画组件
│  │  └─ player/
│  │     ├─ gdscript/                   # 输入、相机
│  │     ├─ scenes/player.tscn
│  │     └─ assets/basic_voxel.glb
│  ├─ shading/                          # 光影组件、原生派生光场及主世界装配
│  ├─ gameplay/
│  │  ├─ interaction/                   # 挖掘/放置职责
│  │  ├─ inventory/
│  │  ├─ crafting/
│  │  └─ survival/
│  └─ ui/
├─ native/
│  ├─ voxel_tools/                      # 上游代码及必要接入补丁
│  ├─ deps/godot-cpp/
│  └─ dependency_lock.json
├─ addons/zylann.voxel/                 # 扩展描述与部署二进制
├─ test/                               # 新统一测试目录，见下文
├─ tools/                              # 生产构建与开发工具
├─ docs/                               # 架构、接口、开发规范
└─ tmp/                                # 忽略的临时输出
```

## 同模块语言分层

功能模块一般采用 gdscript/、native/、scenes/、resources/、assets/、shaders/，按实际需要建立。大模块可先按功能分层，例如 entities/player/gdscript。C++ 继续负责体素热路径，GDScript 负责编排、界面和测试驱动。

所有项目自编原生类的源文件位于 game/<module>/native。构建工具同步到 tmp/native-build/voxel_tools/astraeon/<module>，生成显式源文件清单，并与上游编译为同一扩展。该 tmp 路径仅为构建输出，不是可编辑源码。未列入清单的旧文件不能参与编译。使用上游源码根目录 include 路径，避免依赖旧 astraeon 目录深度。

Voxel Tools 的注册、调度或圆形加载等上游接入补丁仍在 native/voxel_tools 中。依赖不复制进 game；DLL 不提交。构建指纹分别记录上游源码与项目模块源码。移动代码不改变现有存档格式，也不新增旧路径适配。

## 统一测试目录

新目录 test/ 与 game/ 同级。今后所有测试代码、测试场景、样板/演示、基准、夹具、测试专属资源/资产、测试运行器和需版本化的报告都放在 test/<测试项名称>/。可按需要细分 gdscript/、native/、scenes/、fixtures/、resources/、assets/、runners/、reports/。

光影样板、光影专属测试、运行器和历史报告已迁入 test/shading/，运行组件位于 game/shading/，不保留 astraeon_lighting 目录别名。原 tests 内容已迁入 test/native_world/gdscript 与 test/entities/gdscript，专用运行器位于 test/native_world/runners；原目录已删除。历史测量中的路径仅作为原始证据。

临时结果、测试存档、日志与编译二进制仍写 tmp，不提交到 test。迁移需保留 UID、更新所有调用并验证，禁止保留旧路径兼容副本或别名。


全项目规则见 [AGENTS](../../AGENTS.md)。模块依赖见 [整体概览](../../total_development.md)。
