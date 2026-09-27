# 标准素体与第一人称身体验证

日期：2026-09-27。Godot 4.7 stable，D3D12 / RTX 3060 Laptop。资源经当前项目已连接编辑器重新导入，独立测试进程不执行导入。

源：`F:/AstraBlender/Projects/basic_voxel/exports/godot/basic_voxel.glb`，2,466,136 字节，SHA-256 `b2db9553bebf48a143d37d2f80ad6594f34badb0c853a859aa695300e59e75d4`。项目副本逐字节相同。移除内置 Klukai、提取贴图及当前 external_data/characters 中的 Klukai；默认设置重置为 basic_voxel。

- `test/entities/gdscript/test_first_person_body.gd`：26 checks / 0 failures。21 骨骼、左右 Grip、8 动作及循环设置、肩部形态键、身体头部裁除、朝向跟随、运行与跳跃、接地、视角切换恢复完整网格。
- `test/ui/gdscript/character_import_smoke.gd`：9 checks / 0 failures。新标准 GLB 运行时导入、预览、保存、实例化和副本删除。
- `test/ui/gdscript/character_select_check.gd`：57 checks / 0 failures。单内置人物加临时导入副本的选择、当前标记、删除、滚动及四种分辨率布局。

三次最终进程退出码均为 0，日志无 SCRIPT ERROR / ERROR。运行命令为 Godot `--path <checkout> --fixed-fps 60 --resolution 1920x1080 --script <上述脚本> --log-file <checkout>/tmp/<名称>.log`。

已查看渲染截图：[第一人称低头](2026-09-27_first_person_body/down.png)、[平视](2026-09-27_first_person_body/forward.png)、[第三人称](2026-09-27_first_person_body/third.png)。眼高 1.62 m、水平前移 0.22 m，平视无遮挡，低头显示素体，第三人称完整头部恢复。测试采用碰撞试验场，未声称完成主世界长时间手动验收。第一人称仍是同一全身动画的初步展示，没有独立手臂、持物混合、身体 IK，也未为隐藏头部保留独立阴影。
