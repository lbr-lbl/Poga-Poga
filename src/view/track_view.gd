class_name TrackView
extends Node2D
## 赛道绘制：黑白林间小道 + 两旁树叶轮廓 + 远景树冠 + 起点线 + 坡道纹理 + 凋落物。
##
## 全部为静态绘制（只在进入关卡时画一次），避免每帧重建多边形。
## 树叶轮廓同时是碰撞边界（碰撞数据在 RaceTrack.leaves，由 Race 判定），
## 所以视觉上“看着像树丛”的地方，走过去就是碰撞。

var track: RaceTrack
var canopies: Array[Dictionary] = []


func _init(p_track: RaceTrack) -> void:
	track = p_track
	z_index = -10


func _ready() -> void:
	_build_canopies()
	queue_redraw()


func _build_canopies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251118
	var s := 0.0
	while s < track.length:
		for side: float in [-1.0, 1.0]:
			for _k: int in range(2):
				var lateral := track.half_width + rng.randf_range(120.0, 340.0)
				var idx := track.index_at(s + rng.randf_range(-40.0, 40.0))
				var position := track.samples[idx] + track.normals[idx] * (lateral * side)
				canopies.append({
					"position": position,
					"radius": rng.randf_range(46.0, 120.0),
					"shade": rng.randf(),
				})
		s += rng.randf_range(40.0, 70.0)


func _draw() -> void:
	_draw_ground()
	_draw_canopies()
	_draw_road()
	_draw_slope_zones()
	_draw_start_line()
	_draw_debris()
	_draw_leaves()


func _draw_ground() -> void:
	draw_rect(Rect2(Vector2(-3200.0, -3200.0), Vector2(6400.0, 6400.0)), Tuning.COLOR_FOREST)
	# 地表颗粒（低成本伪纹理，纯灰阶）
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i: int in range(900):
		var point := Vector2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))
		var shade := Tuning.COLOR_FOREST_ALT if i % 2 == 0 else Tuning.COLOR_FOREST
		draw_rect(Rect2(point, Vector2(6.0, 6.0)), shade)


func _draw_canopies() -> void:
	for canopy: Dictionary in canopies:
		var position: Vector2 = canopy["position"]
		var radius: float = canopy["radius"]
		var shade: float = canopy["shade"]
		var color := Color(0.05, 0.05, 0.05).lerp(Color(0.11, 0.11, 0.11), shade)
		for k: int in range(3):
			var offset := Vector2.from_angle(float(k) * 2.1 + shade * 6.0) * radius * 0.45
			draw_circle(position + offset, radius * (0.65 - 0.12 * float(k)), color)
		draw_circle(position, radius * 0.7, color)


func _draw_road() -> void:
	var polygon := PackedVector2Array()
	polygon.append_array(track.left_edge)
	for i: int in range(track.right_edge.size() - 1, -1, -1):
		polygon.append(track.right_edge[i])
	draw_colored_polygon(polygon, Tuning.COLOR_ROAD)

	# 路面斑驳：低对比的色块，避免大片纯色
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i: int in range(190):
		var s := rng.randf_range(0.0, track.length)
		var idx := track.index_at(s)
		var lateral := rng.randf_range(-track.half_width + 22.0, track.half_width - 22.0)
		var point := track.samples[idx] + track.normals[idx] * lateral
		var size := rng.randf_range(8.0, 30.0)
		draw_rect(Rect2(point - Vector2(size, size) * 0.5, Vector2(size, size * 0.6)),
			Color(0.0, 0.0, 0.0, 0.05) if i % 3 != 0 else Color(1.0, 1.0, 1.0, 0.08))

	# 中央踩踏痕迹：虚线
	var dash_length := 30.0
	var gap := 40.0
	var travelled := 0.0
	while travelled < track.length:
		var start_idx := track.index_at(travelled)
		var end_idx := track.index_at(travelled + dash_length)
		draw_line(track.samples[start_idx], track.samples[end_idx], Color(0.0, 0.0, 0.0, 0.07), 9.0, false)
		travelled += dash_length + gap

	# 路面内侧压痕
	var inner_left := _offset_edge(1.0, -13.0)
	var inner_right := _offset_edge(-1.0, -13.0)
	draw_polyline(inner_left, Tuning.COLOR_ROAD_DARK, 2.0, false)
	draw_polyline(inner_right, Tuning.COLOR_ROAD_DARK, 2.0, false)


func _offset_edge(side: float, extra: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var offset := extra if side > 0.0 else -extra
	for i: int in range(track.samples.size()):
		points.append(track.samples[i] + track.normals[i] * (track.half_width * side + offset))
	points.append(points[0])
	return points


func _draw_slope_zones() -> void:
	if track.level.slopes.is_empty():
		return
	for zone: LevelDef.SlopeZone in track.level.slopes:
		var color := Color(1.0, 1.0, 1.0, 0.07)
		if zone.slope < 0.0:
			color = Color(0.0, 0.0, 0.0, 0.12)
		var step_ratio := 42.0 / track.length
		var ratio := zone.from_ratio
		while ratio < zone.to_ratio:
			var s := ratio * track.length
			var idx := track.index_at(s)
			var center := track.samples[idx]
			var normal := track.normals[idx]
			draw_line(center - normal * track.half_width, center + normal * track.half_width, color, 7.0, false)
			ratio += step_ratio


func _draw_start_line() -> void:
	var center := track.point_at(0.0)
	var tangent := track.tangent_at(0.0)
	var normal := tangent.orthogonal()
	var cells := 8
	var rows := 3
	var cell_width := track.width / float(cells)
	var cell_depth := 16.0
	var half_width_axis := normal * cell_width * 0.5
	var half_depth_axis := tangent * cell_depth * 0.5
	for row: int in range(rows):
		for col: int in range(cells):
			var color := Color("efefef") if (row + col) % 2 == 0 else Color("1a1a1a")
			var cell_center := center + normal * (-track.half_width + cell_width * (float(col) + 0.5))
			cell_center += tangent * (cell_depth * (float(row) - float(rows - 1) * 0.5))
			var quad := PackedVector2Array([
				cell_center - half_width_axis - half_depth_axis,
				cell_center + half_width_axis - half_depth_axis,
				cell_center + half_width_axis + half_depth_axis,
				cell_center - half_width_axis + half_depth_axis,
			])
			draw_colored_polygon(quad, color)


func _draw_debris() -> void:
	for item: Dictionary in track.debris:
		var position: Vector2 = item["position"]
		var radius: float = item["radius"]
		var kind: StringName = item["kind"]
		var angle: float = item["angle"]
		var visual := radius * 1.15
		# 警示环：让障碍物在浅色路面上也一眼可见（外深内浅双环）
		draw_arc(position, visual + 10.0, 0.0, TAU, 28, Color(0.05, 0.05, 0.05, 0.55), 3.0, false)
		draw_arc(position, visual + 7.0, 0.0, TAU, 28, Color(0.98, 0.98, 0.98, 0.65), 2.0, false)
		# 影子
		draw_circle(position + Vector2(4.0, 5.0), visual * 0.95, Color(0.0, 0.0, 0.0, 0.35))
		match kind:
			&"branch":
				var dir := Vector2.from_angle(angle + 0.6)
				var a := position - dir * visual
				var b := position + dir * visual
				# 浅色外描边 + 深色枝干，保证在灰路面上有对比
				draw_line(a, b, Color(0.95, 0.95, 0.95, 0.95), visual * 0.52, true)
				draw_line(a, b, Color(0.14, 0.14, 0.14), visual * 0.32, true)
				var side := dir.orthogonal()
				draw_line(position, position + dir * visual * 0.35 - side * visual * 0.6, Color(0.14, 0.14, 0.14), visual * 0.18, true)
			&"leaf":
				for k: int in range(5):
					var leaf := {
						"position": position + Vector2.from_angle(angle + float(k) * 1.25) * visual * 0.55,
						"size": visual * 0.62,
						"angle": angle + float(k) * 1.25,
						"width_ratio": 0.42,
					}
					_draw_leaf(leaf, Color(0.95, 0.95, 0.95, 0.9), Color(0.17, 0.17, 0.17), 1.8)
			_:
				draw_circle(position, visual * 0.95, Color(0.95, 0.95, 0.95, 0.95))
				draw_circle(position, visual * 0.72, Color(0.16, 0.16, 0.16))
				draw_circle(position - Vector2(visual * 0.22, visual * 0.22), visual * 0.26, Color(0.55, 0.55, 0.55))

func _draw_leaves() -> void:
	# 外侧叶片先画（暗），贴边叶片后画（亮轮廓），形成层次
	for leaf: Dictionary in track.leaves:
		if leaf["collide"]:
			continue
		_draw_leaf(leaf, Color(0.35, 0.35, 0.35, 0.55), Tuning.COLOR_LEAF_FILL, 1.5)
	for leaf: Dictionary in track.leaves:
		if not leaf["collide"]:
			continue
		_draw_leaf(leaf, Color(0.78, 0.78, 0.78), Tuning.COLOR_LEAF_FILL, 1.8)


func _draw_leaf(leaf: Dictionary, outline: Color, fill: Color, outline_width: float) -> void:
	var position: Vector2 = leaf["position"]
	var size: float = leaf["size"]
	var angle: float = leaf["angle"]
	var width_ratio: float = leaf["width_ratio"]
	var direction := Vector2.from_angle(angle)
	var perpendicular := direction.orthogonal()
	var steps := 6
	var points := PackedVector2Array()
	for i: int in range(steps):
		var t := -1.0 + 2.0 * float(i) / float(steps - 1)
		var half := size * width_ratio * sqrt(maxf(0.0, 1.0 - t * t))
		points.append(position + direction * (t * size) - perpendicular * half)
	for i: int in range(steps - 2, 0, -1):
		var t := -1.0 + 2.0 * float(i) / float(steps - 1)
		var half := size * width_ratio * sqrt(maxf(0.0, 1.0 - t * t))
		points.append(position + direction * (t * size) + perpendicular * half)
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, outline, outline_width, false)