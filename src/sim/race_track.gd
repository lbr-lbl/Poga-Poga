class_name RaceTrack
extends RefCounted
## 赛道几何：中心线闭合曲线、横向定位、检查点、坡度、障碍物、路旁叶片。
##
## 设计要点：
## - 中心线用 Catmull-Rom（Bezier 手柄换算）闭合插值，再按固定步长烘焙成采样点；
## - 所有“进度/横向偏移”都通过最近点搜索 + 线段投影得到，比赛逻辑不依赖物理引擎；
## - 赛道两旁的“树叶轮廓”同时是碰撞边界：贴边行驶会撞到叶子（速度/耐力/稳定惩罚）。
##   只有靠近路面的叶片参与碰撞（collide=true），外侧密林叶片只做视觉。

const EDGE_SAMPLES := 3

var level: LevelDef
var curve: Curve2D
var length: float = 0.0
var width: float = 260.0
var half_width: float = 130.0
var step: float = 1.0

var samples: PackedVector2Array
var tangents: PackedVector2Array
var normals: PackedVector2Array
var curvature: PackedFloat32Array
var left_edge: PackedVector2Array
var right_edge: PackedVector2Array

var checkpoints: PackedFloat32Array
var debris: Array[Dictionary] = []

## 叶片：{ position, size, angle, width_ratio, collide, radius }
var leaves: Array[Dictionary] = []
## 碰撞叶片的 s 分桶：bucket(int) -> Array[int]（leaves 下标）
var leaf_buckets: Dictionary = {}

var start_position: Vector2
var start_angle: float
var start_tangent: Vector2


func _init(level_def: LevelDef) -> void:
    level = level_def
    width = level_def.track_width
    half_width = width * 0.5
    _build_curve()
    _bake()
    _build_edges()
    _build_curvature()
    _build_checkpoints()
    _build_debris()
    _build_leaves()
    start_position = point_at(0.0)
    start_tangent = tangent_at(0.0)
    start_angle = start_tangent.angle()


# ------------------------------------------------------------------ 构建

func _build_curve() -> void:
    curve = Curve2D.new()
    curve.bake_interval = 4.0
    var points := level.control_points
    var n := points.size()
    for i: int in range(n):
        var prev: Vector2 = points[(i - 1 + n) % n]
        var next: Vector2 = points[(i + 1) % n]
        var tangent := (next - prev) / 6.0
        curve.add_point(points[i], -tangent, tangent)
    # 闭合：把首点再追加一次，使最后一节连回起点
    var first_prev: Vector2 = points[n - 1]
    var first_next: Vector2 = points[1]
    var first_tangent := (first_next - first_prev) / 6.0
    curve.add_point(points[0], -first_tangent, first_tangent)


func _bake() -> void:
    length = curve.get_baked_length()
    step = length / float(Tuning.TRACK_SAMPLE_COUNT)
    samples.resize(Tuning.TRACK_SAMPLE_COUNT)
    tangents.resize(Tuning.TRACK_SAMPLE_COUNT)
    normals.resize(Tuning.TRACK_SAMPLE_COUNT)
    for i: int in range(Tuning.TRACK_SAMPLE_COUNT):
        samples[i] = curve.sample_baked(float(i) * step)
    for i: int in range(Tuning.TRACK_SAMPLE_COUNT):
        var prev := samples[wrapi(i - 1, 0, Tuning.TRACK_SAMPLE_COUNT)]
        var next := samples[wrapi(i + 1, 0, Tuning.TRACK_SAMPLE_COUNT)]
        var t := (next - prev)
        if t.length_squared() < 0.000001:
            t = Vector2.RIGHT
        tangents[i] = t.normalized()
        normals[i] = tangents[i].orthogonal()


func _build_edges() -> void:
    left_edge.resize(Tuning.TRACK_SAMPLE_COUNT)
    right_edge.resize(Tuning.TRACK_SAMPLE_COUNT)
    for i: int in range(Tuning.TRACK_SAMPLE_COUNT):
        left_edge[i] = samples[i] + normals[i] * half_width
        right_edge[i] = samples[i] - normals[i] * half_width


func _build_curvature() -> void:
    curvature.resize(Tuning.TRACK_SAMPLE_COUNT)
    var span := 10
    var raw := PackedFloat32Array()
    raw.resize(Tuning.TRACK_SAMPLE_COUNT)
    for i: int in range(Tuning.TRACK_SAMPLE_COUNT):
        var a := tangents[wrapi(i - span, 0, Tuning.TRACK_SAMPLE_COUNT)].angle()
        var b := tangents[wrapi(i + span, 0, Tuning.TRACK_SAMPLE_COUNT)].angle()
        raw[i] = absf(angle_difference(a, b)) / (float(span) * 2.0 * step)
    for i: int in range(Tuning.TRACK_SAMPLE_COUNT):
        var acc := 0.0
        for k: int in range(-EDGE_SAMPLES, EDGE_SAMPLES + 1):
            acc += raw[wrapi(i + k, 0, Tuning.TRACK_SAMPLE_COUNT)]
        curvature[i] = acc / float(EDGE_SAMPLES * 2 + 1)


func _build_checkpoints() -> void:
    checkpoints.resize(Tuning.CHECKPOINT_RATIO.size())
    for i: int in range(Tuning.CHECKPOINT_RATIO.size()):
        checkpoints[i] = Tuning.CHECKPOINT_RATIO[i] * length


func _build_debris() -> void:
    debris.clear()
    for item: LevelDef.Debris in level.debris:
        var s := item.s_ratio * length
        var idx := index_at(s)
        var position := samples[idx] + normals[idx] * (item.lateral * (half_width - 24.0))
        debris.append({
            "position": position,
            "s": s,
            "radius": item.radius,
            "kind": item.kind,
            "angle": normals[idx].angle(),
        })


## 路旁叶片：贴边一圈参与碰撞，再往外一圈只做视觉，形成“被树叶包住的小道”。
func _build_leaves() -> void:
    leaves.clear()
    leaf_buckets.clear()
    var rng := RandomNumberGenerator.new()
    rng.seed = 9001 + int(level.id.hash())
    var s := 0.0
    while s < length:
        for side: float in [-1.0, 1.0]:
            # 贴边叶片（参与碰撞）
            var border_amount := rng.randi_range(1, 2)
            for _k: int in range(border_amount):
                var border_lateral := half_width + rng.randf_range(2.0, 18.0)
                var border_size := rng.randf_range(11.0, 21.0)
                var border_s := s + rng.randf_range(-9.0, 9.0)
                var border_idx := index_at(border_s)
                var border_pos := samples[border_idx] + normals[border_idx] * (border_lateral * side)
                var border_ang := tangents[border_idx].angle() + rng.randf_range(-1.2, 1.2)
                var radius := border_size * Tuning.LEAF_COLLIDER_SCALE
                leaves.append({
                    "position": border_pos,
                    "size": border_size,
                    "angle": border_ang,
                    "width_ratio": rng.randf_range(0.30, 0.48),
                    "collide": true,
                    "radius": radius,
                })
                var bucket := int(fposmod(border_s, length) / Tuning.LEAF_BUCKET_SIZE)
                if not leaf_buckets.has(bucket):
                    leaf_buckets[bucket] = []
                leaf_buckets[bucket].append(leaves.size() - 1)
            # 外侧密林叶片（只做视觉）
            var outer_amount := rng.randi_range(1, 2)
            for _k: int in range(outer_amount):
                var outer_lateral := half_width + rng.randf_range(22.0, 120.0)
                var outer_size := rng.randf_range(20.0, 44.0)
                var outer_s := s + rng.randf_range(-14.0, 14.0)
                var outer_idx := index_at(outer_s)
                var outer_pos := samples[outer_idx] + normals[outer_idx] * (outer_lateral * side)
                leaves.append({
                    "position": outer_pos,
                    "size": outer_size,
                    "angle": tangents[outer_idx].angle() + rng.randf_range(-1.5, 1.5),
                    "width_ratio": rng.randf_range(0.28, 0.44),
                    "collide": false,
                    "radius": 0.0,
                })
        s += rng.randf_range(18.0, 30.0)


# ------------------------------------------------------------------ 查询

func wrap_s(s: float) -> float:
    return fposmod(s, length)


func index_at(s: float) -> int:
    return wrapi(int(floor(s / step)), 0, Tuning.TRACK_SAMPLE_COUNT)


func point_at(s: float) -> Vector2:
    return curve.sample_baked(wrap_s(s))


func tangent_at(s: float) -> Vector2:
    return tangents[index_at(s)]


func normal_at(s: float) -> Vector2:
    return normals[index_at(s)]


func angle_at(s: float) -> float:
    return tangent_at(s).angle()


func curvature_at(s: float) -> float:
    return curvature[index_at(s)]


## 返回 lookahead 距离内最大的曲率，用于 AI 提前刹车。
func max_curvature_ahead(s: float, lookahead: float) -> float:
    var start := index_at(s)
    var count := maxi(2, int(lookahead / maxf(step, 0.001)))
    var best := 0.0
    var stride := maxi(1, count / 24)
    var i := 0
    while i < count:
        best = maxf(best, curvature[wrapi(start + i, 0, Tuning.TRACK_SAMPLE_COUNT)])
        i += stride
    return best


## 坡度：-1..1。使用平滑过渡，避免速度突变。
func slope_at(s: float) -> float:
    if level.slopes.is_empty():
        return 0.0
    var ratio := wrap_s(s) / length
    for zone: LevelDef.SlopeZone in level.slopes:
        if ratio < zone.from_ratio or ratio > zone.to_ratio:
            continue
        var mid := (zone.from_ratio + zone.to_ratio) * 0.5
        var half := maxf((zone.to_ratio - zone.from_ratio) * 0.5, 0.0001)
        var t := clampf(1.0 - absf(ratio - mid) / half, 0.0, 1.0)
        return zone.slope * smoothstep(0.0, 1.0, t)
    return 0.0


## 取某一个 s 附近（±1 个桶）的碰撞叶片下标。
func leaf_indices_near(s: float) -> Array:
    var bucket_count := maxi(1, int(ceil(length / Tuning.LEAF_BUCKET_SIZE)))
    var center := int(fposmod(s, length) / Tuning.LEAF_BUCKET_SIZE)
    var result: Array = []
    for offset: int in [-1, 0, 1]:
        var key := wrapi(center + offset, 0, bucket_count)
        if leaf_buckets.has(key):
            result.append_array(leaf_buckets[key])
    return result


## 最近点查询。hint 为上一帧采样索引，window 为搜索窗口（采样点数）。
## 返回：index/s/dist/lateral/point/tangent。
func nearest(point: Vector2, hint: int = -1, window: int = 44) -> Dictionary:
    var best_index := 0
    var best_d2 := INF
    if hint >= 0 and hint < Tuning.TRACK_SAMPLE_COUNT:
        for k: int in range(-window, window + 1):
            var idx := wrapi(hint + k, 0, Tuning.TRACK_SAMPLE_COUNT)
            var d2 := samples[idx].distance_squared_to(point)
            if d2 < best_d2:
                best_d2 = d2
                best_index = idx
        # 窗口内没找到合理点（被撞飞/抄近道）时做一次全量搜索
        if best_d2 > pow(width * 2.5, 2.0):
            return nearest(point, -1, window)
    else:
        for idx: int in range(Tuning.TRACK_SAMPLE_COUNT):
            var d2 := samples[idx].distance_squared_to(point)
            if d2 < best_d2:
                best_d2 = d2
                best_index = idx

    var best_point := samples[best_index]
    var best_s := float(best_index) * step
    var best_seg := best_index
    for offset: int in [-1, 0]:
        var i0 := wrapi(best_index + offset, 0, Tuning.TRACK_SAMPLE_COUNT)
        var i1 := wrapi(i0 + 1, 0, Tuning.TRACK_SAMPLE_COUNT)
        var a := samples[i0]
        var b := samples[i1]
        var ab := b - a
        var t := 0.0
        if ab.length_squared() > 0.000001:
            t = clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
        var proj := a + ab * t
        var d2 := proj.distance_squared_to(point)
        if d2 < best_d2:
            best_d2 = d2
            best_point = proj
            best_s = (float(i0) + t) * step
            best_seg = i0
    var tangent := tangents[best_seg]
    var normal := normals[best_seg]
    return {
        "index": best_index,
        "seg": best_seg,
        "s": fposmod(best_s, length),
        "dist": sqrt(maxf(best_d2, 0.0)),
        "lateral": (point - best_point).dot(normal),
        "point": best_point,
        "tangent": tangent,
    }


## 起点发车格：s 位于起点线之后（保证第一圈要跑完整圈才记圈）。
func start_slot(row: int, column: int, columns: int) -> Dictionary:
    var s := Tuning.START_GRID_OFFSET + float(row) * Tuning.START_GRID_SPACING
    var lateral := 0.0
    if columns > 1:
        lateral = (float(column) - float(columns - 1) * 0.5) * (width * 0.20)
    var idx := index_at(s)
    var position := samples[idx] + normals[idx] * lateral
    return {"position": position, "s": s, "angle": tangents[idx].angle()}


func progress_ratio(s: float) -> float:
    return wrap_s(s) / length
