class_name TrackMiniMap
extends Control
## 选关界面左下角的小地图：显示整条赛道轮廓、起点与坡度区段。

var _points := PackedVector2Array()
var _start := Vector2.ZERO
var _slopes: Array = []
var _scale: float = 1.0
var _offset := Vector2.ZERO


func setup(level_index: int) -> void:
    var level: LevelDef = LevelCatalog.get_level(level_index)
    var track := RaceTrack.new(level)
    _points = track.samples.duplicate()
    _start = track.point_at(0.0)
    _slopes = level.slopes.duplicate()
    _fit()
    queue_redraw()


func _fit() -> void:
    if _points.is_empty():
        return
    var bounds := Rect2(_points[0], Vector2.ZERO)
    for point: Vector2 in _points:
        bounds = bounds.expand(point)
    var usable := size
    if usable.x <= 1.0 or usable.y <= 1.0:
        usable = Vector2(460.0, 170.0)
    var pad := 10.0
    _scale = minf((usable.x - pad * 2.0) / maxf(bounds.size.x, 1.0), (usable.y - pad * 2.0) / maxf(bounds.size.y, 1.0))
    _offset = usable * 0.5 - bounds.get_center() * _scale


func _draw() -> void:
    if _points.is_empty():
        return
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.03, 0.85))
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.22, 0.22, 0.8), false, 1.0)
    var screen := PackedVector2Array()
    for point: Vector2 in _points:
        screen.append(point * _scale + _offset)
    screen.append(screen[0])
    draw_polyline(screen, Color(0.10, 0.10, 0.10, 0.95), 8.0, true)
    draw_polyline(screen, Color(0.72, 0.72, 0.72, 0.9), 3.0, true)
    # 起终点
    draw_circle(_start * _scale + _offset, 4.0, Color(1.0, 1.0, 1.0, 0.95))
    # 坡度区段：上坡深点、下坡亮点
    for zone: LevelDef.SlopeZone in _slopes:
        var mid_s: float = (zone.from_ratio + zone.to_ratio) * 0.5 * float(_points.size())
        var index := clampi(int(mid_s), 0, _points.size() - 1)
        var pos := _points[index] * _scale + _offset
        var color := Color(0.12, 0.12, 0.12, 0.9) if zone.slope < 0.0 else Color(0.95, 0.95, 0.95, 0.9)
        draw_circle(pos, 2.5, color)