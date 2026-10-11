# 主界面验证

通过已连接的 Godot 编辑器运行 `res://test/ui/scenes/main_menu_check.tscn`。
测试自建六种尺寸的 Window，执行后自动退出；配置仅写入 `res://tmp/main_menu_check_*.cfg`，不更改用户设置或世界存档。

覆盖 canvas 缩放与边界、按钮比例、设置开关及焦点恢复、取消不落盘、当前格式保存重读、不支持格式拒绝覆盖、退出确认默认取消。实际键盘输入与进入世界另作集成检查。

本次记录：[2026-09-26 主界面](reports/2026-09-26_main_menu.md)。

暂停菜单集成测试：运行 `res://test/ui/scenes/pause_menu_check.tscn`，自建 `tmp/pause_world_*` 隔离世界，验证 Esc / F6 / 背包互斥、暂停中输入隔离、保存后返回标题及窗口关闭状态恢复。执行后自动退出，不修改用户世界和配置。

存档列表：运行 `res://test/ui/scenes/world_select_check.tscn`，检查空列表、命名创建、选中读取、删除确认／取消、递归删除与兄弟目录保留、路径校验和配置保留。删除仅针对自建 tmp 测试目录。

完整存档流程：`res://test/ui/scenes/world_select_flow.tscn` 从标题页创建隔离世界，等待可玩，保存返回标题，再读取同一个世界。两者均通过编辑器运行，自动退出。

暂停测试追加 `-- --failure` 切换为保存失败注入：预期一次 `ERROR: Save failed or timed out:  Injected checkpoint failure`，断言世界停止、无重试/继续入口。当前证据见 [掉落物与失败规则回归](../dropped_items/reports/2026-09-27_dropped_items.md)。
