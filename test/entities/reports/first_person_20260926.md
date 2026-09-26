# 基础第一人称验证

日期：2026-09-26。适用实现：player_controller.gd 的 first_person / set_first_person 与 V 切换；默认眼高 1.62 m，隐藏自身模型，共用原相机。

环境：Godot 4.7.stable.official.5b4e0cb0f，D3D12 / Forward+，1280×720 图形窗口，固定 60 Hz 模拟。通过已连接 ASTRAEON 编辑器完整扫描导入并等待空闲；编辑器错误列表为空。

命令（依次执行两个脚本）：

```powershell
& 'F:\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --path F:\GodotProjects\Astraeon --fixed-fps 60 --resolution 1280x720 --script res://test/entities/gdscript/test_player.gd --log-file F:\GodotProjects\Astraeon\tmp\first_person_entity_test.log
& 'F:\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --path F:\GodotProjects\Astraeon --fixed-fps 60 --resolution 1280x720 --script res://test/entities/gdscript/test_world_player.gd --log-file F:\GodotProjects\Astraeon\tmp\first_person_world_test.log
```

- 实体：ENTITY_TEST checks=68 failures=0，退出码 0。覆盖默认第一人称、模型隐藏、眼高、单相机引用、上下俯仰限制、真实 V 键往返切换、鼠标释放禁止切换、贴墙眼位，以及已有移动/慢走/快跑/跳跃/碰撞。
- 世界：FIRST_PERSON_WORLD_TEST failures=0，退出码 0。隔离世界目录 tmp/first_person_entity_world；验证眼位、模型隐藏、8 米地形射线、实际挖掘、移动、跳跃、落地及保存队列。测试恢复被挖方块，不接触正式存档。
- 最终日志无 SCRIPT ERROR、ERROR:、Parser Error 或 WARNING:。首次实体运行发现测试同帧复用输入对象导致两项失败，改为独立事件副本后通过；生产代码未因此放宽检查。
- 已检查 tmp/first_person_world_idle.png，确认第一人称世界画面没有自身模型；其他截图为同前缀 world_walk/run/jump.png。进程身份及退出码在 tmp/first_person_entity_process.json、first_person_world_process.json。

固定时间步验证功能，不作为实时帧率测量；人工手感、极端地形近裁剪及多分辨率验收未完成。未增加手臂、身体、持物、镜头晃动或视角偏好保存。
