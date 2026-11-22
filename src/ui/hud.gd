class_name Hud
extends CanvasLayer

signal pause_pressed
## 比赛内 HUD：排名、圈数、总时间、双层耐力条、倒计时。
##
## 按策划要求：不显示融合提示、不显示玩家头顶标识；只保留信息条。
## 层级：CanvasLayer(layer=2)，位于像素化层之上，因此 UI 始终清晰。

const MARGIN := 26.0

var race: Race
var _rank_label: Label
var _lap_label: Label
var _time_label: Label
var _countdown_label: Label
var _finish_label: Label
var _bar: StaminaBar
var _slope_label: Label
var _scatter_hint: Label
var _control_guide: Label


class StaminaBar:
    extends Control
    ## 耐力槽：折线腰型。上限跌破 30% 时右侧会碎裂消失，并播放一次碎片飞散动画。

    var stamina: float = 1.0
    var cap: float = 1.0
    var pulse: float = 0.0

    var _display: float = 1.0
    var _last_display: float = 1.0
    var _recover_flash: float = 0.0
    var _empty_flash: float = 0.0
    var _broken: bool = false
    var _shatter_t: float = 0.0
    var _shards: Array[Dictionary] = []


    func _ready() -> void:
        set_process(true)


    func trigger_break() -> void:
        if not _broken:
            _broken = true
            _spawn_shards()
        _shatter_t = 1.1


    func _process(delta: float) -> void:
        var critical := cap < Tuning.STAMINA_CAP_CRITICAL
        if critical and not _broken:
            _broken = true
            _shatter_t = 1.0
            _spawn_shards()
        elif not critical and _broken:
            _broken = false
            _shards.clear()
            _shatter_t = 0.0
        if _shatter_t > 0.0:
            _shatter_t = maxf(0.0, _shatter_t - delta)
        for shard: Dictionary in _shards:
            shard["vel"] = (shard["vel"] as Vector2) + Vector2(0.0, 520.0 * delta)
            shard["pos"] = (shard["pos"] as Vector2) + (shard["vel"] as Vector2) * delta
            shard["rot"] = float(shard["rot"]) + float(shard["spin"]) * delta
            shard["life"] = float(shard["life"]) - delta
        _shards = _shards.filter(func(s: Dictionary) -> bool: return float(s["life"]) > 0.0)

        var target := clampf(stamina, 0.0, 1.0)
        _last_display = _display
        _display = lerpf(_display, target, 1.0 - exp(-delta * 16.0))
        if _display > _last_display + 0.0005:
            _recover_flash = minf(1.0, _recover_flash + delta * 3.0)
        else:
            _recover_flash = maxf(0.0, _recover_flash - delta * 2.0)
        if target <= 0.001:
            _empty_flash = minf(1.0, _empty_flash + delta * 4.0)
        else:
            _empty_flash = maxf(0.0, _empty_flash - delta * 1.5)
        queue_redraw()


    func _waist_t() -> float:
        return clampf(0.30 / maxf(cap, 0.001), 0.12, 0.88)


    func _profile() -> Array[Vector2]:
        var waist := _waist_t()
        return [
            Vector2(0.0, 0.95),
            Vector2(waist * 0.55, 0.62),
            Vector2(waist, 0.38),
            Vector2(waist + (1.0 - waist) * 0.45, 0.72),
            Vector2(1.0, 1.0),
        ]


    func _height_at(t: float) -> float:
        var profile := _profile()
        var clamped := clampf(t, 0.0, 1.0)
        for i: int in range(profile.size() - 1):
            var a: Vector2 = profile[i]
            var b: Vector2 = profile[i + 1]
            if clamped >= a.x and clamped <= b.x:
                var ratio := (clamped - a.x) / maxf(b.x - a.x, 0.0001)
                return size.y * 0.5 * lerpf(a.y, b.y, ratio)
        return size.y * 0.5


    func _top_points(mark_x: float, slot_len: float, t_end: float) -> PackedVector2Array:
        var profile := _profile()
        var points := PackedVector2Array()
        for point: Vector2 in profile:
            if point.x > t_end:
                break
            points.append(Vector2(mark_x + slot_len * point.x, size.y * 0.5 - size.y * 0.5 * point.y))
        if t_end > 0.001:
            points.append(Vector2(mark_x + slot_len * t_end, size.y * 0.5 - _height_at(t_end)))
        return points


    func _bottom_points(mark_x: float, slot_len: float, t_end: float) -> PackedVector2Array:
        var top := _top_points(mark_x, slot_len, t_end)
        var bottom := PackedVector2Array()
        for i: int in range(top.size() - 1, -1, -1):
            bottom.append(Vector2(top[i].x, size.y - top[i].y))
        return bottom


    func _outline(mark_x: float, slot_len: float, t_end: float = 1.0) -> PackedVector2Array:
        var top := _top_points(mark_x, slot_len, t_end)
        var bottom := _bottom_points(mark_x, slot_len, t_end)
        var points := PackedVector2Array()
        for point: Vector2 in top:
            points.append(point)
        for point: Vector2 in bottom:
            points.append(point)
        points.append(top[0])
        return points


    func _fill_polygon(mark_x: float, slot_len: float, fill_ratio: float) -> PackedVector2Array:
        var top := _top_points(mark_x, slot_len, fill_ratio)
        var bottom := _bottom_points(mark_x, slot_len, fill_ratio)
        var points := PackedVector2Array()
        for point: Vector2 in top:
            points.append(point)
        for point: Vector2 in bottom:
            points.append(point)
        return points


    func _spawn_shards() -> void:
        _shards.clear()
        var slot_len := size.x * clampf(cap, 0.0, 1.0)
        var split := (size.x - slot_len) * 0.5 + slot_len * 0.55
        for i: int in range(11):
            _shards.append({
                "pos": Vector2(split + randf_range(-4.0, 14.0), size.y * randf_range(0.1, 0.9)),
                "vel": Vector2(randf_range(18.0, 95.0), randf_range(-150.0, -40.0)),
                "rot": randf_range(0.0, TAU),
                "spin": randf_range(-9.0, 9.0),
                "size": randf_range(2.0, 6.5),
                "life": randf_range(0.55, 1.1),
                "max_life": 1.1,
            })


    func _draw() -> void:
        var slot_len := size.x * clampf(cap, 0.0, 1.0)
        if _broken:
            # 破碎后保留一段可读的残槽，避免上限很低时整条槽小到看不见
            slot_len = maxf(slot_len, 260.0)
        if slot_len < 10.0:
            return
        var mark_x := (size.x - slot_len) * 0.5
        if _display <= 0.004:
            mark_x += sin(pulse * 33.0) * 1.6 * _empty_flash
        if _broken:
            _draw_broken(mark_x, slot_len)
            return

        var outline := _outline(mark_x, slot_len)
        draw_colored_polygon(outline, Color(0.075, 0.075, 0.075, 0.97))
        var fill_ratio := clampf(_display / maxf(cap, 0.001), 0.0, 1.0)
        if fill_ratio > 0.004:
            var fill_color := Tuning.COLOR_BAR_FILL
            if _display < 0.30:
                fill_color = fill_color.lerp(Color(0.46, 0.46, 0.46, 1.0), 0.35 + 0.35 * sin(pulse * 9.0))
            if _display <= 0.004:
                fill_color = Color(0.86, 0.86, 0.86, 0.92)
            draw_colored_polygon(_fill_polygon(mark_x, slot_len, fill_ratio), fill_color)
            var edge_x := mark_x + slot_len * fill_ratio
            var edge_half := _height_at(fill_ratio)
            draw_line(Vector2(edge_x, size.y * 0.5 - edge_half), Vector2(edge_x, size.y * 0.5 + edge_half),
                Color(1.0, 1.0, 1.0, 0.75 + 0.2 * sin(pulse * 8.0)), 2.0)
            if _recover_flash > 0.05:
                for k: int in range(3):
                    var offset := fmod(pulse * 1.4 + float(k) * 0.37, 1.0)
                    var t := clampf(fill_ratio - offset * 0.18, 0.0, 1.0)
                    var dot_x := mark_x + slot_len * t
                    var dot_y := size.y * 0.5 - _height_at(t) - 2.0 - offset * 4.0
                    draw_circle(Vector2(dot_x, dot_y), 1.6, Color(1.0, 1.0, 1.0, _recover_flash * 0.5))
        var line_color := Color(0.64, 0.64, 0.64, 0.95)
        if _display < 0.30:
            line_color = line_color.lerp(Color(0.94, 0.94, 0.94, 1.0), 0.35 + 0.35 * sin(pulse * 9.0))
        draw_polyline(outline, line_color, 2.2)


    ## 破碎状态：左侧保留一小段槽体，右侧只剩裂口和飞散的碎片。
    func _draw_broken(mark_x: float, slot_len: float) -> void:
        var left_len := slot_len * 0.55
        var split := mark_x + left_len
        var outline := _outline(mark_x, left_len, 0.55)
        draw_colored_polygon(outline, Color(0.075, 0.075, 0.075, 0.98))
        var fill_ratio := clampf(_display / maxf(cap, 0.001), 0.0, 0.55) / 0.55
        if fill_ratio > 0.004:
            draw_colored_polygon(_fill_polygon(mark_x, left_len, fill_ratio), Tuning.COLOR_BAR_FILL)
        var line_color := Color(0.72, 0.72, 0.72, 0.9)
        draw_polyline(outline, line_color, 2.0)

        # 锯齿裂口 + 分叉裂缝
        var teeth := 8
        var edge := PackedVector2Array()
        edge.append(Vector2(split, 0.0))
        for i: int in range(teeth + 1):
            var y := size.y * float(i) / float(teeth)
            edge.append(Vector2(split + (7.0 if i % 2 == 0 else -5.0), y))
        draw_polyline(edge, Color(0.9, 0.9, 0.9, 0.7), 2.0, true)
        draw_line(Vector2(split - 12.0, size.y * 0.32), Vector2(split + 2.0, size.y * 0.25), Color(0.85, 0.85, 0.85, 0.35), 1.4)
        draw_line(Vector2(split - 9.0, size.y * 0.70), Vector2(split + 3.0, size.y * 0.78), Color(0.85, 0.85, 0.85, 0.35), 1.4)

        # 飞散/落下的碎片
        for shard: Dictionary in _shards:
            var pos: Vector2 = shard["pos"]
            var rot: float = shard["rot"]
            var size_s: float = shard["size"]
            var life: float = float(shard["life"]) / float(shard["max_life"])
            var dir := Vector2(cos(rot), sin(rot))
            var perp := dir.orthogonal()
            var points := PackedVector2Array([
                pos - dir * size_s - perp * size_s * 0.5,
                pos + dir * size_s - perp * size_s * 0.4,
                pos + dir * size_s * 0.8 + perp * size_s * 0.5,
                pos - dir * size_s * 0.7 + perp * size_s * 0.4,
            ])
            draw_colored_polygon(points, Color(0.72, 0.72, 0.72, 0.55 + 0.4 * life))
            points.append(points[0])
            draw_polyline(points, Color(0.98, 0.98, 0.98, 0.5 * life), 1.0)
        # 槽体下方残留的小碎屑
        for i: int in range(4):
            var x := split + 16.0 + float(i) * 10.0
            var y := size.y - 3.0 - float(i % 2) * 2.0
            draw_rect(Rect2(Vector2(x, y), Vector2(5.0, 2.0)), Color(0.5, 0.5, 0.5, 0.5))


func show_scatter_hint() -> void:
    if _scatter_hint != null:
        _scatter_hint.visible = true


func hide_scatter_hint() -> void:
    if _scatter_hint != null:
        _scatter_hint.visible = false


func show_control_guide(text: String) -> void:
    if _control_guide == null:
        return
    _control_guide.text = text
    _control_guide.visible = true
    _control_guide.modulate = Color(1.0, 1.0, 1.0, 1.0)
    var tween := create_tween()
    tween.tween_interval(6.0)
    tween.tween_property(_control_guide, "modulate:a", 0.0, 0.6)
    tween.tween_callback(func() -> void: _control_guide.visible = false)


func trigger_break() -> void:
    if _bar != null:
        _bar.trigger_break()


func setup(p_race: Race) -> void:
    race = p_race


func _ready() -> void:
    layer = 2
    _build()


func _build() -> void:
    var root := Control.new()
    root.name = "HudRoot"
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)

    if OS.has_feature("mobile"):
        var pause_button := UiKit.button("暂停", UiKit.SIZE_SMALL, 8.0, "ui_click")
        pause_button.focus_mode = Control.FOCUS_NONE
        pause_button.custom_minimum_size = Vector2(96.0, 46.0)
        pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
        pause_button.position = Vector2(-122.0, 18.0)
        pause_button.pressed.connect(func() -> void: pause_pressed.emit())
        root.add_child(pause_button)

    _rank_label = UiKit.label("排名 1/6", UiKit.SIZE_LARGE, Tuning.COLOR_TEXT)
    _rank_label.position = Vector2(MARGIN, MARGIN - 10.0)
    root.add_child(_rank_label)

    _lap_label = UiKit.label("圈 1/1", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    _lap_label.position = Vector2(MARGIN + 2.0, MARGIN + 44.0)
    root.add_child(_lap_label)

    _time_label = UiKit.label("00:00.00", 30, Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
    _time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _time_label.position = Vector2(-140.0, MARGIN)
    _time_label.size = Vector2(280.0, 48.0)
    root.add_child(_time_label)

    _countdown_label = UiKit.label("", 100, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
    _countdown_label.set_anchors_preset(Control.PRESET_CENTER)
    _countdown_label.position = Vector2(-200.0, -140.0)
    _countdown_label.size = Vector2(400.0, 220.0)
    _countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    root.add_child(_countdown_label)

    _finish_label = UiKit.label("", UiKit.SIZE_HERO, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
    _finish_label.set_anchors_preset(Control.PRESET_CENTER)
    _finish_label.position = Vector2(-260.0, -60.0)
    _finish_label.size = Vector2(520.0, 120.0)
    _finish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _finish_label.visible = false
    root.add_child(_finish_label)

    _bar = StaminaBar.new()
    _bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    _bar.position = Vector2(-280.0, -66.0)
    _bar.size = Vector2(560.0, 46.0)
    _bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(_bar)
    _scatter_hint = UiKit.label("按住移动键，把分裂的小史莱姆聚回来", UiKit.SIZE_BODY, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
    _scatter_hint.set_anchors_preset(Control.PRESET_CENTER)
    _scatter_hint.position = Vector2(-320.0, 150.0)
    _scatter_hint.visible = false
    root.add_child(_scatter_hint)

    _control_guide = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
    _control_guide.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _control_guide.position = Vector2(-660.0, 92.0)
    _control_guide.custom_minimum_size = Vector2(640.0, 0.0)
    _control_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _control_guide.visible = false
    root.add_child(_control_guide)

    _slope_label = UiKit.label("", 20, Tuning.COLOR_TEXT_DIM)
    _slope_label.position = Vector2(MARGIN + 2.0, MARGIN + 76.0)
    _slope_label.visible = false
    root.add_child(_slope_label)


func _process(_delta: float) -> void:
    if race == null or race.player == null:
        return
    var player := race.player
    _rank_label.text = "排名 %d/%d" % [race.player_rank(), race.racers.size()]
    var terrain := race.current_terrain_name()
    _lap_label.text = ("圈 %d/%d" % [race.current_lap(), race.level.total_laps]) + (("  ·  " + terrain) if terrain != "" else "")
    _time_label.text = GameState.format_time(race.race_time)
    _bar.stamina = player.stamina
    _bar.cap = player.stamina_cap
    _bar.pulse = race.race_time
    # 关键：Control 的 _draw 不会自己逐帧刷新，必须在数值变化后主动请求重绘
    # 耐力条自己 _process 里逐帧重绘并维护 peak
    var slope := race.player_slope()
    if absf(slope) > 0.06:
        _slope_label.visible = true
        if slope < 0.0:
            _slope_label.text = "▲ 上坡 %d%%" % int(round(absf(slope) * 8.0))
        else:
            _slope_label.text = "▼ 下坡 %d%%" % int(round(absf(slope) * 8.0))
    else:
        _slope_label.visible = false
    _update_countdown()
    _update_finish()


func _update_countdown() -> void:
    if race.state == Race.State.COUNTDOWN:
        _countdown_label.text = str(maxi(ceili(race.countdown - 0.2), 1))
        _countdown_label.visible = true
    elif race.state == Race.State.RACING and race.race_time < 0.75:
        _countdown_label.text = "GO"
        _countdown_label.visible = true
    else:
        _countdown_label.visible = false


func _update_finish() -> void:
    _finish_label.visible = race.state == Race.State.FINISHED
    if _finish_label.visible:
        _finish_label.text = "终点" if race.player.finished else "失败"
