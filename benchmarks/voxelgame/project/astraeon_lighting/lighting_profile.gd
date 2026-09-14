class_name AstraeonLightingProfile
extends Resource
## Immutable defaults. The sample duplicates this Resource for runtime controls.
@export_range(0.0, 24.0) var hour: float = 12.0
@export var cycle_enabled: bool = false
@export_range(30.0, 3600.0) var day_seconds: float = 600.0
@export var sky_enhanced: bool = true
@export var direct_enabled: bool = true
@export var shadows_enabled: bool = true
@export_range(16.0, 256.0) var shadow_distance: float = 96.0
@export var block_color: Color = Color(1.0, 0.64, 0.32)
@export_range(0.0, 4.0) var block_energy: float = 1.3
@export_range(0.5, 3.0) var block_curve: float = 1.6
@export_range(0.1, 4.0) var exposure: float = 1.0
@export_range(256, 32768) var work_cells: int = 4096
@export_range(250, 8000) var work_usec: int = 2000
