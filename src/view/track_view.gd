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
	if prestart_mode:
		_draw_prestart_field()
		return
	if _leaf_zone_kind.is_empty():
		_build_leaf_zones()
	_draw_ground()
	_draw_canopies()
	_draw_road()
	_draw_slope_zones()
	_draw_start_line()
	_draw_debris()
	_draw_leaves()
	_draw_terrain_props()


func _draw_prestart_field() -> void:
	# 空场地：一整片深灰地面 + 前方起跑门
	draw_rect(Rect2(Vector2(-3200.0, -3200.0), Vector2(6400.0, 6400.0)), Color(0.30, 0.30, 0.30))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i: int in range(420):
		var point := Vector2(rng.randf_range(-2600.0, 2600.0), rng.randf_range(-2600.0, 2600.0))
		draw_rect(Rect2(point, Vector2(5.0, 5.0)), Color(0.26, 0.26, 0.26))
	# 和游戏内完全一样的黑白格起跑线
	_draw_start_line()
	# 空地装饰：稀疏的叶片、草丛、小石块，避免场地太素
	_draw_field_decor()


func _draw_field_decor() -> void:
	var center := track.point_at(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	# 地面上的深色斑块，让空地不单调
	for i: int in range(14):
		var patch_pos := center + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(180.0, 1200.0)
		draw_circle(patch_pos, rng.randf_range(28.0, 70.0), Color(0.255, 0.255, 0.255, 0.55))
	for i: int in range(420):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(240.0, 1050.0)
		var pos := center + Vector2.from_angle(angle) * distance
		if distance < 300.0:
			# 起跑线附近只放小草丛/碎石，保持中间空地
			draw_line(pos, pos + Vector2(2.0, -8.0), Color(0.42, 0.42, 0.42, 0.55), 1.4)
			continue
		if i % 3 == 0:
			var size := rng.randf_range(18.0, 38.0)
			_draw_leaf({
				"position": pos,
				"size": size,
				"angle": rng.randf_range(0.0, TAU),
				"width_ratio": 0.34,
				"collide": false,
			}, Color(0.62, 0.62, 0.62, 0.55), Color(0.22, 0.22, 0.22, 0.95), 1.4)
		elif i % 5 == 1:
			# 小石块
			var stone := PackedVector2Array([
				pos + Vector2(-6.0, 0.0), pos + Vector2(-2.0, -5.0),
				pos + Vector2(5.0, -3.0), pos + Vector2(7.0, 3.0), pos + Vector2(0.0, 6.0),
			])
			draw_colored_polygon(stone, Color(0.18, 0.18, 0.18, 0.9))
			stone.append(stone[0])
			draw_polyline(stone, Color(0.55, 0.55, 0.55, 0.45), 1.0)
		else:
			# 草丛
			for k: int in range(3):
				var offset := Vector2(float(k - 1) * 4.0, 0.0)
				draw_line(pos + offset, pos + offset + Vector2(2.0, -8.0), Color(0.34, 0.34, 0.34, 0.55), 1.5)


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
		_draw_slope_strip(zone)
		_draw_slope_hatching(zone)
		_draw_slope_arrows(zone)
		_draw_slope_gate(zone.from_ratio * track.length, zone.slope)


## 坡道用“沿路渐变的明暗条带”表现，不再是横线：
## 上坡铺一层很淡的亮色（像被光照到的高地），下坡铺一层淡暗色（阴影），两端淡出。
func _draw_slope_strip(zone: LevelDef.SlopeZone) -> void:
	var start_s: float = zone.from_ratio * track.length
	var end_s: float = zone.to_ratio * track.length
	var steps: int = 48
	var intensity: float = clampf(absf(zone.slope) * 2.4, 0.65, 1.0)
	var color := Color(0.0, 0.0, 0.0, 0.44 * intensity) if zone.slope < 0.0 else Color(1.0, 1.0, 1.0, 0.52 * intensity)
	var points := PackedVector2Array()
	for k: int in range(steps + 1):
		var t := float(k) / float(steps)
		var s := lerpf(start_s, end_s, t)
		var idx := track.index_at(s)
		points.append(track.samples[idx] + track.normals[idx] * track.half_width)
	for k: int in range(steps, -1, -1):
		var t := float(k) / float(steps)
		var s := lerpf(start_s, end_s, t)
		var idx := track.index_at(s)
		points.append(track.samples[idx] - track.normals[idx] * track.half_width)
	draw_colored_polygon(points, color)


func _draw_slope_hatching(zone: LevelDef.SlopeZone) -> void:
	var start_s: float = zone.from_ratio * track.length
	var end_s: float = zone.to_ratio * track.length
	var uphill := zone.slope < 0.0
	var color := Color(0.02, 0.02, 0.02, 0.24) if uphill else Color(0.02, 0.02, 0.02, 0.18)
	var s := start_s + 24.0
	while s < end_s - 24.0:
		var idx := track.index_at(s)
		var center := track.samples[idx]
		var tangent := track.tangents[idx]
		var normal := track.normals[idx]
		for offset: float in [-0.55, 0.0, 0.55]:
			var base := center + normal * track.half_width * offset
			var tip_a := base - tangent * 9.0 + normal * 12.0 * (1.0 if uphill else -1.0)
			var tip_b := base + tangent * 9.0 - normal * 12.0 * (1.0 if uphill else -1.0)
			draw_line(tip_a, tip_b, color, 2.0)
		s += 52.0


## 坡道入口/出口小旗：在两侧路肩画一个小三角，方便提前看到坡道开始。
func _draw_slope_gate(s: float, slope: float) -> void:
	var idx := track.index_at(s)
	var center := track.samples[idx]
	var normal := track.normals[idx]
	var color := Color(0.95, 0.95, 0.95, 0.8) if slope < 0.0 else Color(0.10, 0.10, 0.10, 0.8)
	for side: float in [-1.0, 1.0]:
		var base := center + normal * track.half_width * side
		var p1 := base - normal * 10.0 * side
		var p2 := base + normal * 2.0 * side
		var p3 := base + normal * 2.0 * side - track.tangents[idx] * 14.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color)


## 路两侧画小三角箭头指示坡度方向：上坡朝行进方向，下坡朝反方向。
func _draw_slope_arrows(zone: LevelDef.SlopeZone) -> void:
	var start_s: float = zone.from_ratio * track.length
	var end_s: float = zone.to_ratio * track.length
	var color := Color(0.04, 0.04, 0.04, 0.55)
	var s := start_s + 30.0
	while s < end_s - 30.0:
		for side: float in [-1.0, 1.0]:
			var idx := track.index_at(s)
			var center := track.samples[idx] + track.normals[idx] * (track.half_width - 24.0) * side
			var tangent := track.tangents[idx]
			var normal := track.normals[idx]
			var direction := tangent if zone.slope < 0.0 else -tangent
			var tip := center + direction * 8.0
			var back := center - direction * 7.0
			var p1 := back + normal * 7.0
			var p2 := back - normal * 7.0
			draw_colored_polygon(PackedVector2Array([p1, p2, tip]), color)
		s += 96.0


## 地形分区装饰：林间 → 旷野 → 岩地 → 高地。
## 只画路肩附近的小道具，让 12km 长赛段沿途有“换了地方”的感觉。
func _draw_terrain_props() -> void:
	if track.level.terrain.is_empty():
		return
	for zone: LevelDef.TerrainZone in track.level.terrain:
		var start_s: float = zone.from_ratio * track.length
		var end_s: float = zone.to_ratio * track.length
		_draw_terrain_shoulder(zone)
		# 分区交界的小石柱
		for boundary: float in [start_s]:
			var b_idx := track.index_at(boundary)
			for side: float in [-1.0, 1.0]:
				var post := track.samples[b_idx] + track.normals[b_idx] * (track.half_width + 10.0) * side
				draw_rect(Rect2(post - Vector2(3.0, 8.0), Vector2(6.0, 16.0)), Color(0.55, 0.55, 0.55, 0.8))
				draw_rect(Rect2(post - Vector2(3.0, 8.0), Vector2(6.0, 4.0)), Color(0.9, 0.9, 0.9, 0.9))
		var s := start_s + 40.0
		while s < end_s - 40.0:
			var idx := track.index_at(s)
			for side: float in [-1.0, 1.0]:
				var base := track.samples[idx] + track.normals[idx] * (track.half_width + 14.0) * side
				_draw_terrain_prop(zone.kind, base, track.tangents[idx], track.normals[idx], s)
			s += 96.0


func _draw_terrain_shoulder(zone: LevelDef.TerrainZone) -> void:
	var color: Color
	match zone.kind:
		&"plain":
			color = Color(0.62, 0.62, 0.62, 0.30)
		&"rock":
			color = Color(0.12, 0.12, 0.12, 0.55)
		&"highland":
			color = Color(0.85, 0.85, 0.85, 0.22)
		_:
			color = Color(0.06, 0.06, 0.06, 0.45)
	var start_s: float = zone.from_ratio * track.length
	var end_s: float = zone.to_ratio * track.length
	var steps := 48
	for side: float in [-1.0, 1.0]:
		var points := PackedVector2Array()
		for k: int in range(steps + 1):
			var s := lerpf(start_s, end_s, float(k) / float(steps))
			var idx := track.index_at(s)
			points.append(track.samples[idx] + track.normals[idx] * track.half_width * side)
		for k: int in range(steps, -1, -1):
			var s := lerpf(start_s, end_s, float(k) / float(steps))
			var idx := track.index_at(s)
			points.append(track.samples[idx] + track.normals[idx] * (track.half_width + 16.0) * side)
		draw_colored_polygon(points, color)


func _draw_terrain_prop(kind: StringName, base: Vector2, tangent: Vector2, normal: Vector2, s: float) -> void:
	match kind:
		&"plain":
			# 旷野：低矮草丛
			for k: int in range(3):
				var offset := normal * (float(k) - 1.0) * 5.0
				draw_line(base + offset, base + offset - tangent * 9.0 + normal * 4.0, Color(0.45, 0.45, 0.45, 0.55), 1.5)
		&"rock":
			# 岩地：路肩石块（深色填充 + 浅色描边）
			var size := 8.0 + fmod(s, 7.0)
			var points := PackedVector2Array([
				base - tangent * size + normal * 2.0,
				base + normal * size,
				base + tangent * size,
				base - normal * size * 0.6,
			])
			draw_colored_polygon(points, Color(0.16, 0.16, 0.16, 0.95))
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, Color(0.7, 0.7, 0.7, 0.55), 1.5)
		&"highland":
			# 高地：浅色雾气与细枝
			draw_line(base - normal * 6.0, base + normal * 6.0, Color(0.9, 0.9, 0.9, 0.10), 10.0)
			draw_line(base, base - tangent * 12.0, Color(0.55, 0.55, 0.55, 0.45), 1.5)
		_:
			# 林间：小蘑菇/低矮叶丛
			draw_circle(base, 3.0, Color(0.55, 0.55, 0.55, 0.55))
			draw_line(base, base - tangent * 7.0 + normal * 2.0, Color(0.4, 0.4, 0.4, 0.5), 1.2)


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
	# 外侧叶片先画（暗），贴边叶片后画（亮轮廓），形成层次；颜色按地形分区微调
	var index := 0
	for leaf: Dictionary in track.leaves:
		var kind: StringName = _leaf_zone_kind[index] if index < _leaf_zone_kind.size() else &"forest"
		index += 1
		if leaf["collide"]:
			continue
		_draw_leaf(leaf, _zone_outline(Color(0.35, 0.35, 0.35, 0.55), kind), Tuning.COLOR_LEAF_FILL, 1.5)
	index = 0
	for leaf: Dictionary in track.leaves:
		var kind: StringName = _leaf_zone_kind[index] if index < _leaf_zone_kind.size() else &"forest"
		index += 1
		if not leaf["collide"]:
			continue
		_draw_leaf(leaf, _zone_outline(Color(0.78, 0.78, 0.78), kind), Tuning.COLOR_LEAF_FILL, 1.8)


var _leaf_zone_kind: Array[StringName] = []
## 序章：只画空地和起跑门，不加载赛道/树叶
var prestart_mode: bool = false


func _build_leaf_zones() -> void:
	_leaf_zone_kind.clear()
	if track.level.terrain.is_empty():
		for i: int in range(track.leaves.size()):
			_leaf_zone_kind.append(&"forest")
		return
	for leaf: Dictionary in track.leaves:
		var ratio: float = fposmod(float(track.nearest(leaf["position"], -1)["s"]) / track.length, 1.0)
		var kind: StringName = &"forest"
		for zone: LevelDef.TerrainZone in track.level.terrain:
			if ratio >= zone.from_ratio and ratio < zone.to_ratio:
				kind = zone.kind
				break
		_leaf_zone_kind.append(kind)


func _zone_outline(base: Color, kind: StringName) -> Color:
	match kind:
		&"plain":
			return Color(0.55, 0.55, 0.55, base.a * 0.6)
		&"rock":
			return Color(0.70, 0.70, 0.70, base.a * 0.9)
		&"highland":
			return Color(0.92, 0.92, 0.92, base.a * 0.8)
		_:
			return base


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