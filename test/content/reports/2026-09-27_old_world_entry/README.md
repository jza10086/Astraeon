# 旧存档启动提示与显式新建世界

2026-09-27，Godot 4.7，原生扩展保持 4a1d7b833543，无 DLL 重建。

正式 Main 读取世界选择配置；遇到已有 .avr 且缺少注册表时，保留拒绝旧格式的规则，显示「创建新世界（保留旧存档）」与「返回主菜单」。只有用户点击创建才写入同级新目录，并保存 settings.cfg 的 world 节（format=1、active_slot）。其他配置节保留。

功能命令：`./tmp/content/run.ps1 -Script res://test/content/gdscript/test_old_world_entry.gd -Name old_world_entry -Graphical -TimeoutSeconds 115`。

结果：**13 checks，0 failures，退出0**。隔离 tmp 夹具模拟旧目录，点击正式界面按钮后新世界进入可玩状态；原 .avr SHA-256 不变，旧目录未添加注册表，新目录具有注册表，下次解析选择相同目录，其他设置值未覆盖。拒绝路径穿越及不支持的配置版本。夹具只触发原生旧格式拒绝检查，不读取或转换旧世界内容。

未触碰用户存档或替用户点击创建；未运行性能测试。日志有既有系统证书、MCP 注册和 shader cache 写入警告，没有 SCRIPT ERROR 或测试失败标记。[日志](old_world_entry.log)。
