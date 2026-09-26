# Basic Voxel 接入验证

历史记录；本次文档整理未重跑。

## 2026-09-26 替换验证

Godot 4.7.stable.official.5b4e0cb0f，D3D12 / Forward+。通过已连接 ASTRAEON 编辑器完整扫描导入并等待空闲；定向刷新后编辑器错误列表为空。

- 图形实体回归：固定 60 Hz 模拟，52 项检查、0 失败，退出码 0。
- 原生世界集成：出生、移动、快跑、起跳、落地、保存队列通过，退出码 0。
- 已检查世界快跑和跳跃截图，确认标准素体在地形中显示并播放姿态。
- 首次变帧率图形运行有 3 个按帧时序断言失败；固定 60 Hz 后通过。固定时间步结果属于功能验证，不证明实时帧率或全部手感。

日志：tmp/basic_voxel_player_test.log（首次）、tmp/basic_voxel_player_fixed_test.log、tmp/basic_voxel_world_test.log。截图：tmp/basic_voxel_world_idle.png、basic_voxel_world_walk.png（普通跑步）、basic_voxel_world_run.png（快跑）、basic_voxel_world_jump.png。
