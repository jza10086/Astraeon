extends SceneTree
const Meter: Script = preload("res://game/ui/gdscript/frame_time_label.gd")
var failures: int = 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        push_error(message)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var meter: Meter = Meter.new()
    var now: int = 1000000
    for index: int in range(100):
        var ms: float = 105.0 if index == 99 else 5.0
        now += int(ms*1000.0)
        meter.push_sample(ms,now)
    var stats: Dictionary = meter.summarize()
    check(is_equal_approx(stats.fps,1000.0/6.0),"FPS uses total wall time")
    check(is_equal_approx(stats.low_fps,1000.0/105.0),"1% Low catches single hitch")
    check(stats.p99_ms == 5.0 and stats.max_ms == 105.0,"P99 differs from maximum")
    check(stats.over_16 == 1 and stats.over_33 == 1,"Threshold counts")
    check(not stats.ready,"Insufficient duration is marked warming")
    meter.push_sample(5.0,now+11000000)
    check(meter.summarize().samples == 1,"Old frames expire")
    meter.reset_samples()
    check(meter.summarize().is_empty(),"Focus/disabled reset empties history")
    for index: int in range(Meter.CAPACITY+200):
        meter.push_sample(0.1,1000000+index*100)
    check(meter.summarize().samples == Meter.CAPACITY,"Ring capacity stays bounded")
    check(is_equal_approx(meter.summarize().low_fps,10000.0),"Wrapped ring statistics")
    meter.reset_samples()
    meter.position = Vector2(24,24)
    meter.sampling_enabled = true
    meter.context_text = "HUD 验证 · 将注入一次 80 ms 停顿"
    root.add_child(meter)
    root.grab_focus()
    Engine.max_fps = 200
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    await create_timer(2.5).timeout
    OS.delay_msec(80)
    await create_timer(0.5).timeout
    stats = meter.summarize()
    check(not stats.is_empty() and stats.get("max_ms",0.0) >= 75.0,"Actual wall clock captures injected hitch")
    check(stats.get("ready",false),"Live sample becomes ready")
    print("FRAME_TIME_STATS ",stats)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://tmp/frame-time-hud.png")
    meter.sampling_enabled = false
    await process_frame
    await process_frame
    check(meter.summarize().is_empty(),"Disabling sampling resets history")
    meter.queue_free()
    print("FRAME_TIME_LABEL failures=%d" % failures)
    quit(0 if failures == 0 else 1)
