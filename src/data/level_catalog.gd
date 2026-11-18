class_name LevelCatalog
extends RefCounted
## Demo 三关数据。
##
## 赛道形状由“圆角多边形”生成：角点附近多点取大半径圆弧，边中点向内收，
## 经 Catmull-Rom 插值后得到“林间小道 + 3 个缓弯”的手感，避免手写几十个控制点。
## 赛道宽度按鼻涕虫尺度收窄（约 230~244），让融合团几乎占满路宽。

const COUNT := 3

static var _cache: Array[LevelDef] = []


static func all() -> Array[LevelDef]:
	if _cache.is_empty():
		_cache = [_build_ring(), _build_hill(), _build_debris()]
	return _cache


static func get_level(index: int) -> LevelDef:
	var levels := all()
	return levels[clampi(index, 0, levels.size() - 1)]


## 生成圆角三角形环道。
## corner_spread_deg：角点圆弧采样跨度；edge_pull：边中点向内收缩比例（越小越像三角形）。
static func _ring_points(radius: float, corner_spread_deg: float, edge_pull: float, corner_angles: Array[float]) -> PackedVector2Array:
	var points := PackedVector2Array()
	var n := corner_angles.size()
	for i: int in range(n):
		var center_angle: float = corner_angles[i]
		for k: int in range(-1, 2):
			var a := deg_to_rad(center_angle + corner_spread_deg * float(k))
			points.append(Vector2(cos(a), sin(a)) * radius)
		var next_angle: float = corner_angles[(i + 1) % n]
		var mid_angle := center_angle + fposmod(next_angle - center_angle, 360.0) * 0.5
		var m := deg_to_rad(mid_angle)
		points.append(Vector2(cos(m), sin(m)) * radius * edge_pull)
	return points


static func _build_ring() -> LevelDef:
	var level := LevelDef.new()
	level.id = &"ring"
	level.display_name = "RING"
	level.subtitle = "LEVEL 1"
	level.total_laps = 1
	level.track_width = 232.0
	level.control_points = _ring_points(700.0, 30.0, 0.86, [90.0, 210.0, 330.0])
	level.ai_count = 5
	level.difficulty = 1.0
	level.ai_speed_scale = 0.88
	level.ai_patience_scale = 1.0
	level.ai_brake_skill = 0.36
	level.ai_mistake_rate = 0.18
	level.ai_fuse_bias = 0.7
	return level


static func _build_hill() -> LevelDef:
	var level := LevelDef.new()
	level.id = &"hill"
	level.display_name = "HILL"
	level.subtitle = "LEVEL 2"
	level.total_laps = 2
	level.track_width = 244.0
	level.control_points = _ring_points(790.0, 26.0, 0.90, [90.0, 210.0, 330.0])
	level.ai_count = 5
	level.difficulty = 1.35
	level.ai_speed_scale = 0.92
	level.ai_patience_scale = 1.15
	level.ai_brake_skill = 0.6
	level.ai_mistake_rate = 0.07
	level.ai_fuse_bias = 0.9
	# 上坡：s 15% ~ 35%，下坡：58% ~ 78%
	level.add_slope(0.15, 0.35, -1.0)
	level.add_slope(0.56, 0.78, 1.0)
	return level


static func _build_debris() -> LevelDef:
	var level := LevelDef.new()
	level.id = &"debris"
	level.display_name = "FALLEN"
	level.subtitle = "LEVEL 3"
	level.total_laps = 3
	level.track_width = 258.0
	level.control_points = _ring_points(740.0, 30.0, 0.86, [90.0, 210.0, 330.0])
	level.ai_count = 5
	level.difficulty = 1.7
	level.ai_speed_scale = 0.96
	level.ai_patience_scale = 1.3
	level.ai_brake_skill = 0.78
	level.ai_mistake_rate = 0.035
	level.ai_fuse_bias = 1.05
	level.add_debris(0.12, -0.32, 18.0, &"branch")
	level.add_debris(0.20, 0.38, 15.0, &"leaf")
	level.add_debris(0.33, -0.50, 18.0, &"branch")
	level.add_debris(0.52, -0.18, 22.0, &"leaf")
	level.add_debris(0.61, 0.52, 16.0, &"branch")
	level.add_debris(0.81, 0.26, 18.0, &"leaf")
	level.add_debris(0.90, -0.10, 16.0, &"branch")
	return level