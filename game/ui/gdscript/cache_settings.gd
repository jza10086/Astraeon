extends VBoxContainer
## Numeric cache policy controls. Presets only populate editable values.
var coordinator: Node
var preset: OptionButton
var body: VBoxContainer
var status: Label
var metrics_label: Label
var metric_clock: float = 0.0
var widgets: Dictionary[String, SpinBox] = {}
const LABELS: Dictionary[String,String] = {"visual_cpu_mib":"方块视觉 CPU / MiB","visual_gpu_mib":"方块视觉 GPU / MiB","visual_warm_seconds":"视觉温缓存 / s","visual_upload_usec":"视觉上传 / μs","visual_upload_bytes":"视觉上传 / byte","visual_jobs":"视觉读取并发","cpu_mib":"CPU 管理预算 / MiB","gpu_mib":"GPU 光照页预算 / MiB (1–128)","retain_m":"数据保留环 / m","mesh_seconds":"CPU 网格保留 / s","region_handles":"Region 句柄上限","commit_usec":"共用提交预算 / μs","upload_usec":"光照上传软预算 / μs","upload_bytes":"光照上传上限 / byte","slice_visits":"传播访问数 / 工作片","slice_usec":"传播软预算 / μs","prediction_seconds":"预测时间 / s","prediction_max_m":"最大预测偏移 / m"}
func configure(owner_coordinator: Node) -> void:
    coordinator = owner_coordinator
    var toggle: CheckButton = CheckButton.new()
    toggle.text = "地图与光照缓存设置"
    add_child(toggle)
    body = VBoxContainer.new()
    add_child(body)
    body.hide()
    toggle.toggled.connect(body.set_visible)
    preset = OptionButton.new()
    for text: String in ["节省","均衡","大缓存","自定义"]: preset.add_item(text)
    body.add_child(preset)
    for key: String in LABELS:
        var label: Label = Label.new()
        label.text = LABELS[key]
        body.add_child(label)
        var widget: SpinBox = SpinBox.new()
        widget.min_value = 0.0
        widget.max_value = 16777216.0
        widget.step = 0.05 if key in ["mesh_seconds","prediction_seconds","prediction_max_m"] else 1.0
        body.add_child(widget)
        widgets[key] = widget
        widget.value_changed.connect(func(value: float) -> void:
            coordinator.policy.values[key] = value
            preset.select(3))
    preset.item_selected.connect(func(index: int) -> void:
        if index < 3:
            coordinator.policy.select_preset(index)
            sync())
    var apply: Button = Button.new()
    apply.text = "暂停并应用缓存配置"
    apply.pressed.connect(func() -> void:
        var error: Error = await coordinator.apply_policy()
        status.text = "已应用" if error == OK else "配置未应用：" + error_string(error))
    body.add_child(apply)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(status)
    metrics_label = Label.new()
    metrics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(metrics_label)
    sync()
func _process(delta: float) -> void:
    if metrics_label == null or not metrics_label.is_visible_in_tree(): return
    metric_clock += delta
    if metric_clock < 0.5: return
    metric_clock = 0.0
    var m: Dictionary = coordinator.metrics
    var hits: int = int(m.get("map_hits",0))
    var misses: int = int(m.get("map_misses",0))
    metrics_label.text = "地图命中 %.1f%% · 淘汰 %d\n体素 / 光照 / 网格：%.1f / %.1f / %.1f MiB\n临时数据 %.1f MiB · GPU 光照 %.0f MiB\n读入/传播队列 %d · 光照上传等待 %d\n天气上传等待 %d · 本帧光照提交 %.3f ms\n光照批次年龄 %.1f ms\n最长单任务 %.3f ms（%s）" % [100.0*hits/maxi(1,hits+misses),int(m.get("map_evictions",0)),float(m.get("voxel_bytes",0))/1048576.0,float(m.get("light_bytes",0))/1048576.0,float(m.get("derived_bytes",0))/1048576.0,float(m.get("temporary_bytes",0))/1048576.0,float(m.get("gpu_bytes",0))/1048576.0,int(m.get("queue",0)),int(m.get("pending_light_uploads",0)),int(m.get("pending_weather_uploads",0)),float(m.get("upload_usec",0))/1000.0,float(m.get("light_latency_usec",0))/1000.0,float(m.get("single_task_peak_usec",0))/1000.0,str(m.get("single_task_peak_name","—"))]
    var visual: Dictionary = m.get("visuals", {})
    metrics_label.text += "\n视觉 CPU/GPU %.2f/%.2f MiB · 命中 %d · 读取 %d · 上传 %d\n视觉等待 %d · 超预算 %d · %s" % [float(visual.get("cpu_bytes",0))/1048576.0,float(visual.get("gpu_bytes",0))/1048576.0,int(visual.get("hits",0)),int(visual.get("reads",0)),int(visual.get("uploads",0)),int(visual.get("pending",0))+int(visual.get("queued",0)),int(visual.get("upload_overruns",0)),String(visual.get("pressure",""))]
    if not visual.get("failures", []).is_empty(): metrics_label.text += "\n视觉读取失败：" + str(visual.failures)
func sync() -> void:
    for key: String in widgets:
        widgets[key].set_value_no_signal(float(coordinator.policy.values[key]))
    preset.select(coordinator.policy.preset_index())
