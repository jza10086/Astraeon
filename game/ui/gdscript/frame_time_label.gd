extends Label
## Wall-clock frame intervals, not GPU timings. Fixed ring storage avoids per-frame sorting.
const WINDOW_USEC: int = 10000000
const CAPACITY: int = 32768
var sampling_enabled: bool = false
var context_text: String = ""
var _durations: PackedFloat64Array = PackedFloat64Array()
var _timestamps: PackedInt64Array = PackedInt64Array()
var _head: int = 0
var _count: int = 0
var _last_usec: int = 0
var _refresh_usec: int = 0

func _init() -> void:
    _durations.resize(CAPACITY)
    _timestamps.resize(CAPACITY)

func _process(_delta: float) -> void:
    if not sampling_enabled or not get_window().has_focus():
        if _last_usec != 0:
            reset_samples()
        text = "帧时间：等待场景就绪 / 窗口焦点"
        return
    var now: int = Time.get_ticks_usec()
    if _last_usec == 0:
        _last_usec = now
        text = "帧时间：采样中…"
        return
    push_sample((now-_last_usec)/1000.0,now)
    _last_usec = now
    if now-_refresh_usec < 250000: return
    _refresh_usec = now
    var stats: Dictionary = summarize()
    var low: String = "%.0f" % stats.low_fps if stats.ready else "采样中"
    text = "%.0f FPS | 1%% Low %s | 帧均 %.2f ms\nP99 %.2f ms | 最长 %.2f ms | >16.7/33.3 ms：%d/%d 帧\n最近 %.1f s · %d 帧 | %s" % [
        stats.fps,low,stats.mean_ms,stats.p99_ms,stats.max_ms,
        stats.over_16,stats.over_33,stats.seconds,stats.samples,context_text]

func reset_samples() -> void:
    _head = 0
    _count = 0
    _last_usec = 0
    _refresh_usec = 0

## now_usec is the interval end; injectable for deterministic statistics tests.
func push_sample(milliseconds: float, now_usec: int) -> void:
    if milliseconds <= 0.0: return
    while _count > 0 and _timestamps[_head] <= now_usec-WINDOW_USEC:
        _head = (_head+1)%CAPACITY
        _count -= 1
    if _count == CAPACITY:
        _head = (_head+1)%CAPACITY
        _count -= 1
    var slot: int = (_head+_count)%CAPACITY
    _durations[slot] = milliseconds
    _timestamps[slot] = now_usec
    _count += 1

## 1% Low = 1000 / mean(slowest ceil(N*0.01) frame intervals).
func summarize() -> Dictionary:
    if _count == 0: return {}
    var sorted: PackedFloat64Array = PackedFloat64Array()
    sorted.resize(_count)
    var total: float = 0.0
    var over_16: int = 0
    var over_33: int = 0
    for index: int in range(_count):
        var value: float = _durations[(_head+index)%CAPACITY]
        sorted[index] = value
        total += value
        if value > 1000.0/60.0: over_16 += 1
        if value > 1000.0/30.0: over_33 += 1
    sorted.sort()
    var tail_count: int = maxi(1,ceili(_count*0.01))
    var tail: float = 0.0
    for index: int in range(_count-tail_count,_count):
        tail += sorted[index]
    var end: int = _timestamps[(_head+_count-1)%CAPACITY]
    var begin: int = _timestamps[_head]-int(_durations[_head]*1000.0)
    var seconds: float = minf((end-begin)/1000000.0,WINDOW_USEC/1000000.0)
    return {
        "fps":1000.0*_count/total,"mean_ms":total/_count,
        "low_fps":1000.0*tail_count/tail,
        "p99_ms":sorted[maxi(0,ceili(_count*0.99)-1)],"max_ms":sorted[_count-1],
        "over_16":over_16,"over_33":over_33,"samples":_count,"seconds":seconds,
        "ready":seconds >= 2.0 and _count >= 100}
