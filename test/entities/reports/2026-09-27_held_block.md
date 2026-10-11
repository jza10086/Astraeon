# 右手持方块验证

日期：2026-09-27。Godot 4.7 stable，D3D12 / RTX 3060 Laptop。使用当前 Basic Voxel 八动作 GLB；没有修改模型文件。

- `test/entities/gdscript/test_held_block.gd`：21 checks / 0 failures。真实内容包、库存选中槽、0.28 m Grip_R 挂点、右臂过滤、跑跳与握持叠加、第三人称、空槽切换、数量耗尽、工具不使用方块动作。
- `test/entities/gdscript/test_first_person_body.gd`：26 checks / 0 failures。手动推进运动播放器后的身体与移动跳跃回归。
- `test/entities/gdscript/test_world_held_block.gd`：5 checks / 0 failures。临时主世界启动、库存驱动显示、空槽释放、世界保存与退出。

三次最终进程退出码均为 0，日志无 SCRIPT ERROR / ERROR。命令：Godot `--path <checkout> --fixed-fps 60 --resolution 1920x1080 --script <上述脚本> --log-file <checkout>/tmp/<测试名>.log`。通过现有编辑器刷新并等待导入空闲，没有启动第二个编辑器或冷导入。临时世界与日志均在 tmp 下。

已检查渲染：[第一人称平视](2026-09-27_held_block/first_forward.png)、[第一人称低头](2026-09-27_held_block/first_down.png)、[第三人称](2026-09-27_held_block/third.png)、[主世界](2026-09-27_held_block/world.png)。原握持姿势位于身体前下方，因此第一人称低头可见、平视时在视野下方；尚无独立第一人称姿势或 IK。截图中的帧率不作为性能基准。

本次草方块为内容包六面常量颜色，未单独覆盖纹理异步失败注入或长期运行。持物简化材质未接入地形体素光、发光及水面特效；没有工具挥动、左手或双手切换。
