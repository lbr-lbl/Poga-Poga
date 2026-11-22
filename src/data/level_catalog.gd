class_name LevelCatalog
extends RefCounted
## 关卡目录（数据驱动）。
##
## 顺序即解锁顺序：
##   1 RING   教学：加速 / 滑行 / 转向 / 自动融合
##   2 HILL   坡度与耐力
##   3 FALLEN 障碍物与树叶碰撞
##   4 FINALE 最终赛段：长赛道 + 连续起伏 + 障碍 + 9 只对手（3 圈）

const COUNT := 4

static var _cache: Array[LevelDef] = []


static func all() -> Array[LevelDef]:
    if _cache.is_empty():
        _cache = [_build_ring(), _build_hill(), _build_debris(), _build_finale()]
    return _cache


static func get_level(index: int) -> LevelDef:
    var levels := all()
    return levels[clampi(index, 0, levels.size() - 1)]


## 圆角多边形控制点：角点在外半径，两侧控制点内收形成圆角。
static func _ring_points(radius: float, corner_spread_deg: float, edge_pull: float, corner_angles: Array[float]) -> PackedVector2Array:
    var points := PackedVector2Array()
    var spread := deg_to_rad(corner_spread_deg)
    for angle_deg: float in corner_angles:
        var angle := deg_to_rad(angle_deg)
        for offset: float in [-spread, 0.0, spread]:
            var r := radius if is_zero_approx(offset) else radius * edge_pull
            points.append(Vector2(cos(angle + offset), sin(angle + offset)) * r)
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
    level.difficulty = 0.9
    level.ai_speed_scale = 0.88
    level.ai_patience_scale = 1.0
    level.ai_brake_skill = 0.50
    level.ai_mistake_rate = 0.08
    level.ai_fuse_bias = 0.80
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
    level.difficulty = 1.1
    level.ai_speed_scale = 0.92
    level.ai_patience_scale = 1.05
    level.ai_brake_skill = 0.60
    level.ai_mistake_rate = 0.06
    level.ai_fuse_bias = 0.90
    level.add_slope(0.15, 0.35, -0.55)
    level.add_slope(0.56, 0.78, 0.55)
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
    level.difficulty = 1.3
    level.ai_speed_scale = 0.96
    level.ai_patience_scale = 1.0
    level.ai_brake_skill = 0.65
    level.ai_mistake_rate = 0.05
    level.ai_fuse_bias = 0.95
    level.add_debris(0.10, -0.32, 30.0, &"branch")
    level.add_debris(0.26, 0.40, 24.0, &"leaf")
    level.add_debris(0.44, -0.46, 22.0, &"pebble")
    level.add_debris(0.60, 0.18, 28.0, &"branch")
    level.add_debris(0.76, -0.12, 24.0, &"leaf")
    level.add_debris(0.90, 0.42, 30.0, &"branch")
    return level


static func _wavy_points(base_radius: float, harmonics: Array[Vector3], count: int = 96) -> PackedVector2Array:
    # 用几组不同频率的正弦叠加出一条“有性格”的闭合赛道：
    # 低频给大弯/长弧，高频给小 S 弯与收窄的弯心。
    var points := PackedVector2Array()
    for i: int in range(count):
        var angle := TAU * float(i) / float(count)
        var radius := base_radius
        for harmonic: Vector3 in harmonics:
            radius *= 1.0 + harmonic.x * sin(harmonic.y * angle + harmonic.z)
        points.append(Vector2(cos(angle), sin(angle)) * radius)
    return points


static func _peanut_points(base_radius: float, lobes: float, asymmetry: float, ripple: float) -> PackedVector2Array:
    # “花生”形闭合赛道：两个大回环 + 中间收窄的颈部 + 三段高频起伏，
    # 比单一三角形有更多类型的弯（大发卡、S 弯、收窄弯心）。
    var points := PackedVector2Array()
    var count := 128
    for i: int in range(count):
        var angle := TAU * float(i) / float(count)
        var radius := base_radius * (1.0 + lobes * cos(2.0 * angle) + asymmetry * cos(3.0 * angle + 0.6) + ripple * cos(7.0 * angle + 0.2))
        # 两处局部内凹：形成“减速弯/S 弯”的节奏，而不是均匀绕圈
        var chicane := 1.0 - 0.09 * exp(-pow((angle - 1.75) / 0.16, 2.0)) - 0.07 * exp(-pow((angle - 5.05) / 0.13, 2.0))
        radius *= chicane
        var point := Vector2(cos(angle), sin(angle)) * radius
        # 轻微拉伸 + 错切：让两侧回环大小不同，避免过于对称
        point = Vector2(point.x * 1.10 + point.y * 0.06, point.y * 0.95)
        points.append(point)
    return points


static func _build_finale() -> LevelDef:
    var level := LevelDef.new()
    level.id = &"finale"
    level.display_name = "FINALE"
    level.subtitle = "LEVEL 4"
    level.total_laps = 1
    level.track_width = 270.0
    # 大地图：3 个大弧 + 高频小 S 弯 + 收窄弯心，不再是干绕三角/方形
    level.control_points = _peanut_points(1700.0, 0.34, 0.10, 0.03)
    level.ai_count = 9
    level.difficulty = 2.0
    level.ai_speed_scale = 1.0
    level.ai_patience_scale = 1.25
    level.ai_brake_skill = 0.85
    level.ai_mistake_rate = 0.03
    level.ai_fuse_bias = 1.1
    # 山地 + 起伏组合：长上坡、短陡坡、连续小起伏
    level.add_slope(0.03, 0.10, -0.55)
    level.add_slope(0.14, 0.22, -0.95)
    level.add_slope(0.27, 0.35, 0.75)
    level.add_slope(0.39, 0.47, -0.85)
    level.add_slope(0.52, 0.60, 0.65)
    level.add_slope(0.65, 0.73, -0.70)
    level.add_slope(0.78, 0.86, 0.80)
    level.add_slope(0.90, 0.96, -0.60)
    # 四段景观：林间 → 旷野 → 岩地 → 高地，让长赛段有层次
    level.add_terrain(0.00, 0.24, &"forest")
    level.add_terrain(0.24, 0.49, &"plain")
    level.add_terrain(0.49, 0.73, &"rock")
    level.add_terrain(0.73, 1.00, &"highland")
    # 障碍分布：直道、弯心、坡顶都有
    level.add_debris(0.08, 0.30, 24.0, &"pebble")
    level.add_debris(0.20, -0.40, 30.0, &"branch")
    level.add_debris(0.34, 0.18, 22.0, &"leaf")
    level.add_debris(0.47, -0.28, 28.0, &"branch")
    level.add_debris(0.60, 0.36, 24.0, &"pebble")
    level.add_debris(0.74, -0.20, 26.0, &"leaf")
    level.add_debris(0.88, 0.24, 24.0, &"branch")
    return level
