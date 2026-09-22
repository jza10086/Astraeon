# 实体测试

`gdscript/test_player.gd` 是既有角色测试，`gdscript/fixtures/character_playground.gd` 是固定碰撞夹具；迁移保留 UID。

当前测试仍假定旧固定地面场景，却引用正式主场景，因此不要直接作为原生地图的实体验收执行。后续需要实体模块接入独立测试场景。本次仅迁移目录和引用，没有修改测试行为。
