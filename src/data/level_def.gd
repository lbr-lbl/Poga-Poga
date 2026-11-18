class_name LevelDef
extends Resource
## 关卡定义（数据驱动）。
##
## 关卡由 LevelCatalog 在代码中构造（MVP 阶段避免手写大段 .tres），
## 但结构保持为 Resource，方便后续改成编辑器内美术/策划编辑的资源文件。
##
## 坐标约定：赛道为一条闭合 Catmull-Rom 曲线，s 从起点线（s=0）沿行进方向递增；
## 横向偏移 lateral 以行进方向右手侧为正。

class SlopeZone:
	extends RefCounted
	var from_ratio: float
	var to_ratio: float
	## -1.0 = 上坡（减速 + 高耗耐），+1.0 = 下坡（加速但转向难）。
	var slope: float

	func _init(p_from: float, p_to: float, p_slope: float) -> void:
		from_ratio = p_from
		to_ratio = p_to
		slope = p_slope


class Debris:
	extends RefCounted
	var s_ratio: float
	## -1..1，相对路面半宽的横向位置。
	var lateral: float
	var radius: float
	## branch / leaf / pebble，仅影响表现。
	var kind: StringName

	func _init(p_s: float, p_lateral: float, p_radius: float, p_kind: StringName = &"branch") -> void:
		s_ratio = p_s
		lateral = p_lateral
		radius = p_radius
		kind = p_kind


@export var id: StringName = &"ring"
@export var display_name: String = "RING"
@export var subtitle: String = ""
@export var total_laps: int = 1
@export var track_width: float = 260.0
@export var control_points: PackedVector2Array = PackedVector2Array()

## AI 数量（不含玩家）。
@export var ai_count: int = 5
## 难度系数（1.0 为基准），同时影响 AI 速度与奖励。
@export var difficulty: float = 1.0
## AI 基础速度倍率（相对玩家基准）。
@export var ai_speed_scale: float = 0.94
@export var ai_patience_scale: float = 1.0
@export var ai_brake_skill: float = 0.45
@export var ai_mistake_rate: float = 0.10
@export var ai_fuse_bias: float = 0.75

var slopes: Array[SlopeZone] = []
var debris: Array[Debris] = []


func add_slope(p_from: float, p_to: float, p_slope: float) -> void:
	slopes.append(SlopeZone.new(p_from, p_to, p_slope))


func add_debris(p_s: float, p_lateral: float, p_radius: float, p_kind: StringName = &"branch") -> void:
	debris.append(Debris.new(p_s, p_lateral, p_radius, p_kind))


func has_obstacles() -> bool:
	return not debris.is_empty()


func has_slopes() -> bool:
	return not slopes.is_empty()