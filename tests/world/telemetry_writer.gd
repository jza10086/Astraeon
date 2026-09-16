class_name AstraeonTelemetryWriter
extends RefCounted
## Owns append-only telemetry files. A single batch is in flight; callers transfer array ownership.
var error: String = ""
var _frames_file: FileAccess
var _tasks_file: FileAccess
var _frames: Array[PackedFloat64Array] = []
var _records: Array[Dictionary] = []
var _task: int = -1

func configure(output: String) -> bool:
	_frames_file = FileAccess.open(output.path_join("frames.csv"), FileAccess.WRITE)
	_tasks_file = FileAccess.open(output.path_join("tasks.jsonl"), FileAccess.WRITE)
	if _frames_file == null or _tasks_file == null:
		error = "Cannot open telemetry files"
		return false
	_frames_file.store_line("elapsed_us,phase,frame_us,resident,dirty,in_flight,missing_data,missing_mesh,engine_static_bytes,process_s,physics_s,draw_calls")
	_frames_file.flush()
	return true

func idle() -> bool:
	if _task == -1:
		return true
	if not WorkerThreadPool.is_task_completed(_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_frames = []
	_records = []
	return true

func submit(frames: Array[PackedFloat64Array], records: Array[Dictionary]) -> void:
	assert(_task == -1)
	_frames = frames
	_records = records
	_task = WorkerThreadPool.add_task(_write_batch)

func _write_batch() -> void:
	for frame: PackedFloat64Array in _frames:
		var cells: PackedStringArray = PackedStringArray()
		for value: float in frame:
			cells.append(str(value))
		_frames_file.store_line(",".join(cells))
	for record: Dictionary in _records:
		_tasks_file.store_line(JSON.stringify(record))
	_frames_file.flush()
	_tasks_file.flush()
	if _frames_file.get_error() != OK or _tasks_file.get_error() != OK:
		error = "Telemetry write failed"

func finish(frames: Array[PackedFloat64Array], records: Array[Dictionary]) -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_frames = frames
	_records = records
	_write_batch()
	_frames_file.close()
	_tasks_file.close()
