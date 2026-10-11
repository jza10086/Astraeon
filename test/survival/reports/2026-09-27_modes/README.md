# 初版模式与状态验证

日期：2026-09-27。引擎：Godot 4.7.stable.official.5b4e0cb0f，D3D12 Forward+，RTX 3060 Laptop GPU。

## 当前结果

本轮最终运行共 268 项断言通过，0 项失败：

| 场景/套件 | 检查 | 失败 |
| --- | ---: | ---: |
| PLAYER_STATE_TEST | 27 | 0 |
| MODES_WORLD_TEST | 44 | 0 |
| CREATIVE_TEST | 56 | 0 |
| INVENTORY_TEST | 53 | 0 |
| TOOL_ITEMS_TEST | 29 | 0 |
| WORLD_SELECT_CHECK | 27 | 0 |
| PAUSE_MENU_CHECK | 18 | 0 |
| DROPPED_WORLD_TEST | 14 | 0 |

经配置 GODOT_MCP_PROJECT_PATH=F:/GodotProjects/Astraeon 的 MCP 客户端确认项目名 ASTRAEON，执行 editor_refresh（full）与 editor_wait_for_idle，再通过 game_start 运行测试；最终刷新后编辑器错误列表为空。未重启用户编辑器、未冷导入或重建 DLL。

新增场景可直接运行 `res://test/survival/scenes/player_state_test.tscn` 与 `res://test/survival/scenes/modes_world_test.tscn`。既有 SceneTree 库存/掉落套件通过 tmp/modes-regression 下临时 Node 驱动运行：测试主体不变，只将 SceneTree 的 root、帧信号、quit 绑定到当前 SceneTree，便于已连接编辑器启动。暂停和创建测试直接运行 test/ui/scenes 下原场景。

## 验证重点

模式共享背包、生命/饱食度上下限及模式无关接口、创造免费编辑 WAL、生存数量消耗与地面掉落、权限入口、持物持久化、双快照恢复、旧格式拒绝、暂停切换、飞行升降/加速/悬停/碰撞、输入清空和切回生存均已覆盖。

主世界测试末尾主动拒绝鼠标掉落事务，预期输出一次“鼠标掉落物事务写入失败”并停止世界；断言确认窗口仍打开、持物和原掉落池不变。该预期错误不作为无错误运行记录。其余最终回归没有 SCRIPT ERROR 或非预期 ERROR。

本轮修复了最终保存的完成时序：工作线程的 tracker 已完成时，主线程可能仍有一帧保存结果未释放。最终保存继续等待 streaming 计数归零后才 checkpoint，暂停保存及返回标题回归通过。

## 图形证据

在实际主世界检查了 HUD、模式背包和飞行碰撞。嵌入式窗口不能可靠按请求改变渲染尺寸，因此四分辨率证据由独立 SubViewport 实例化正式 InventoryHUD，匹配 canvas_items/expand 的逻辑尺寸并渲染；测试校验纹理真实像素尺寸、控件边界及不重叠。

- [1920×1080 HUD](hud_1920x1080.png)
- [2560×1440 HUD](hud_2560x1440.png)
- [3840×2160 HUD](hud_3840x2160.png)
- [3440×1440 HUD](hud_3440x1440.png)
- [生存背包](survival_bag.png)、[创造背包](creative_bag.png)

截图状态为接口测试后的 6/10，初始 10/10 由状态与主世界断言验证。截图已进行视觉检查；人工连续操控手感、长期压力和硬件断电不在本轮验收内。

## 过程与限制

早期独立 headless 运行遇到系统证书读取与 MCP 注册目录权限错误，未计为通过；改用已连接编辑器验证。早期保存时序、失败候选撤销及快照测试固定文件名问题均已修正，以上表格只统计最终成功运行。

掉落事务通过短期原生候选池和当前快照保持提交原子性，原池在失败时保留；该操作随现存掉落数量线性增长，未宣称大规模性能通过。睡眠标志为派生状态，候选恢复后由物理步重新判断。

[主世界结果](world_result.json)、[当前源码 SHA-256](source_fingerprints.json)。旧世界与库存格式仅拒绝，不迁移、不删除。
