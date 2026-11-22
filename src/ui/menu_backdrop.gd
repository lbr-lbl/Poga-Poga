class_name MenuBackdrop
extends Control
## 菜单背景：一台老式游戏机的内屏（v0.10）。
##
## - CRT 外壳 + 内屏扫描线 + 暗角 + 荧光闪烁；
## - 夜色森林剪影 + 缓慢漂移的雾 + 飘落的叶子；
## - 不画任何“奇怪的图案”，保持安静，让标题成为唯一焦点。

const BEZEL := 22.0
const SCANLINE_ALPHA := 0.13
const SCANLINE_STEP := 3.0

var _time: float = 0.0
var _leaves: Array[Dictionary] = []


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)
    _build_leaves()
    set_process(true)


func _build_leaves() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261120
    _leaves.clear()
    for i: int in range(14):
        _leaves.append({
            "x": rng.randf_range(0.05, 0.95),
            "y": rng.randf_range(-0.1, 1.0),
            "speed": rng.randf_range(0.008, 0.022),
            "sway": rng.randf_range(0.4, 1.2),
            "phase": rng.randf_range(0.0, TAU),
            "size": rng.randf_range(5.0, 11.0),
        })


func _process(delta: float) -> void:
    _time += delta
    for leaf: Dictionary in _leaves:
        leaf["y"] = float(leaf["y"]) + float(leaf["speed"]) * delta
        if float(leaf["y"]) > 1.08:
            leaf["y"] = -0.08
    queue_redraw()


func _draw() -> void:
    var view := get_viewport_rect().size
    var screen := Rect2(Vector2(BEZEL, BEZEL), view - Vector2(BEZEL, BEZEL) * 2.0)
    draw_rect(Rect2(Vector2.ZERO, view), Color("020202"))
    draw_rect(screen, Color("060707"))
    draw_rect(screen, Color(0.34, 0.34, 0.34, 0.5), false, 2.0)

    _draw_forest(screen)
    _draw_leaves(screen)

    # 扫描线
    var y := screen.position.y
    while y < screen.end.y:
        draw_line(Vector2(screen.position.x, y), Vector2(screen.end.x, y), Color(0.0, 0.0, 0.0, SCANLINE_ALPHA), 1.0)
        y += SCANLINE_STEP

    # 暗角
    var band := 34.0
    var steps := 14
    for i: int in range(steps):
        var alpha := 0.055 * (1.0 - float(i) / float(steps))
        var inset := float(i) * band
        var rect := Rect2(screen.position.x + inset, screen.position.y + inset, screen.size.x - inset * 2.0, band)
        draw_rect(rect, Color(0.0, 0.0, 0.0, alpha))
        draw_rect(Rect2(rect.position.x, screen.end.y - inset - band, rect.size.x, band), Color(0.0, 0.0, 0.0, alpha))
        draw_rect(Rect2(screen.position.x + inset, screen.position.y + inset, band, screen.size.y - inset * 2.0), Color(0.0, 0.0, 0.0, alpha))
        draw_rect(Rect2(screen.end.x - inset - band, screen.position.y + inset, band, screen.size.y - inset * 2.0), Color(0.0, 0.0, 0.0, alpha))




func _draw_forest(screen: Rect2) -> void:
    var horizon := screen.position.y + screen.size.y * 0.62
    # 远处的雾
    for i: int in range(3):
        var y := screen.position.y + screen.size.y * (0.30 + 0.16 * float(i))
        var alpha := 0.045
        draw_rect(Rect2(screen.position.x, y, screen.size.x, screen.size.y * 0.16), Color(0.7, 0.7, 0.7, alpha))
    # 背景树冠：两层剪影
    for layer: int in range(2):
        var base_y := screen.position.y + screen.size.y * (0.08 + 0.10 * float(layer))
        var shade := Color(0.055, 0.055, 0.055) if layer == 0 else Color(0.095, 0.095, 0.095)
        var outline := Color(0.20, 0.20, 0.20, 0.28) if layer == 0 else Color(0.30, 0.30, 0.30, 0.22)
        var x := screen.position.x - 60.0
        var i := 0
        while x < screen.end.x + 60.0:
            var cy := base_y + 26.0 * sin(float(i) * 0.8 + float(layer) * 1.7)
            for k: int in range(3):
                var lx := x + (float(k) - 1.0) * 38.0 + 12.0 * sin(float(i) * 1.3 + float(k))
                var ly := cy + 16.0 * sin(float(i) * 0.6 + float(k) * 2.1)
                var angle := sin(float(i) * 0.9 + float(k) * 1.4) * 1.2
                _draw_leaf_shape(Vector2(lx, ly), 30.0 + 10.0 * sin(float(i) + float(k)), angle * 0.4 + 0.35, shade, outline)
            x += 96.0
            i += 1
    # 地面：一条很暗的横向渐变
    draw_rect(Rect2(screen.position.x, horizon, screen.size.x, screen.end.y - horizon), Color(0.03, 0.03, 0.03))
    # 地面上的草叶/叶子轮廓（很暗，只给一点质感）
    var rng := RandomNumberGenerator.new()
    rng.seed = 7788
    for i: int in range(40):
        var gx := rng.randf_range(screen.position.x, screen.end.x)
        var gy := rng.randf_range(horizon, screen.end.y)
        var w := rng.randf_range(6.0, 16.0)
        draw_line(Vector2(gx, gy), Vector2(gx + w * 0.4, gy - w * 0.7), Color(0.16, 0.16, 0.16, 0.5), 1.0)


## 画一片和游戏内同风格的叶子（两段弧组成的透镜形）。
func _draw_leaf_shape(center: Vector2, size: float, angle: float, fill: Color, outline: Color) -> void:
    var direction := Vector2.from_angle(angle)
    var perpendicular := direction.orthogonal()
    var points := PackedVector2Array()
    var steps := 7
    for i: int in range(steps):
        var t := -1.0 + 2.0 * float(i) / float(steps - 1)
        var half := size * 0.30 * sqrt(maxf(0.0, 1.0 - t * t))
        points.append(center + direction * (t * size) - perpendicular * half)
    for i: int in range(steps - 2, 0, -1):
        var t := -1.0 + 2.0 * float(i) / float(steps - 1)
        var half := size * 0.30 * sqrt(maxf(0.0, 1.0 - t * t))
        points.append(center + direction * (t * size) + perpendicular * half)
    draw_colored_polygon(points, fill)
    points.append(points[0])
    draw_polyline(points, outline, 1.2, true)


func _draw_leaves(screen: Rect2) -> void:
    for leaf: Dictionary in _leaves:
        var x := screen.position.x + float(leaf["x"]) * screen.size.x + sin(_time * float(leaf["sway"]) + float(leaf["phase"])) * 18.0
        var y := screen.position.y + float(leaf["y"]) * screen.size.y
        if y < screen.position.y or y > screen.end.y:
            continue
        var s := float(leaf["size"])
        var angle := sin(_time * float(leaf["sway"]) + float(leaf["phase"])) * 0.9 + float(leaf["phase"])
        var points := PackedVector2Array()
        for k: int in range(7):
            var t := float(k) / 6.0
            var side := 1.0 if k < 4 else -1.0
            var width := sin(PI * t) * s * 0.6
            points.append(Vector2(cos(angle) * (t - 0.5) * s * 2.0 - sin(angle) * width * side,
                sin(angle) * (t - 0.5) * s * 2.0 + cos(angle) * width * side))
        points.append(Vector2(cos(angle) * (0.5 - 0.5) * s * 2.0, sin(angle) * (0.5 - 0.5) * s * 2.0))
        draw_polyline(points, Color(0.42, 0.42, 0.42, 0.26), 1.0, true)
