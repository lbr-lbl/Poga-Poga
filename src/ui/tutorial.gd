class_name Tutorial
extends Control
## 前三关的操作引导（v0.13）。
##
## - **聚焦慢动作**：每个提示出现时短暂减速（第一关 0.22×，其它关 0.45×），
##   同时镜头轻微拉近、屏幕边缘压暗并在玩家周围留出清晰区域；
##   提示读完后立即恢复正常速度，让玩家自己完成动作；
## - **第一关序章**：比赛开始前先学移动，开到起跑线才发车；
## - 每一步等玩家做出对应动作或超时后进入下一步；
## - 无头自动测试不创建本节点。

const FOCUS_TIME := 1.7
const FOCUS_SCALE_RACE := 0.45
const STEP_MIN_SHOW := 0.12
const STEP_MAX_SHOW := 5.0
const PRESTART_MAX_SHOW := 20.0
const CAMERA_FOCUS_BIAS := 1.34

var race: Race
var level_index: int = 0
var prestart: bool = false

var _steps: Array[Dictionary] = []
var _index: int = 0
var _step_time: float = 0.0
var _focus_timer: float = 0.0
var _done: bool = false
var _panel: PanelContainer
var _text_label: Label
var _progress_label: Label
var _eye_hits_start: int = 0
var _debris_hits_start: int = 0
var _leaf_hits_start: int = 0
var _restore_scale: float = 1.0


func setup(p_race: Race, p_level_index: int, p_prestart: bool = false) -> void:
    race = p_race
    level_index = p_level_index
    prestart = p_prestart


func _ready() -> void:
    size = get_viewport_rect().size
    position = Vector2.ZERO
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _steps = _build_steps()
    if _steps.is_empty():
        queue_free()
        return
    if race != null:
        _eye_hits_start = race.stats_eye_collisions
        _debris_hits_start = race.stats_debris_collisions
        _leaf_hits_start = race.stats_leaf_collisions
    _build_ui()
    _restore_scale = 1.0
    _show_current()


func _exit_tree() -> void:
    Engine.time_scale = 1.0
    if race != null:
        race.camera_zoom_bias = 1.0


func _process(delta: float) -> void:
    if _done or race == null:
        return
    _step_time += delta
    if _focus_timer > 0.0:
        _focus_timer -= delta
        queue_redraw()
        if _focus_timer <= 0.0:
            _end_focus()
    if _step_time < STEP_MIN_SHOW:
        return
    var step: Dictionary = _steps[_index]
    var limit := PRESTART_MAX_SHOW if prestart and _index >= _steps.size() - 1 else STEP_MAX_SHOW
    if _condition_met(str(step.get("cond", ""))) or _step_time >= limit:
        _advance()


func _start_focus() -> void:
    if prestart:
        _focus_timer = 0.0
        Engine.time_scale = 1.0
        if race != null:
            race.camera_zoom_bias = 1.0
        queue_redraw()
        return
    _focus_timer = FOCUS_TIME
    Engine.time_scale = FOCUS_SCALE_RACE
    if race != null:
        race.camera_zoom_bias = CAMERA_FOCUS_BIAS
    queue_redraw()


func _end_focus() -> void:
    _focus_timer = 0.0
    Engine.time_scale = 1.0
    if race != null:
        race.camera_zoom_bias = 1.0
    queue_redraw()


func _advance() -> void:
    _index += 1
    _step_time = 0.0
    if _index >= _steps.size():
        finish_now()
        return
    _show_current()


## 提前结束（起跑线已到 / 比赛结束）。
func finish_now() -> void:
    if _done:
        return
    _done = true
    _focus_timer = 0.0
    Engine.time_scale = 1.0
    if race != null:
        race.camera_zoom_bias = 1.0
    var tween := create_tween()
    tween.tween_property(_panel, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.3)
    tween.tween_callback(queue_free)


func _draw() -> void:
    if prestart or _focus_timer <= 0.0 or race == null or race.player == null:
        return
    var progress := clampf(_focus_timer / FOCUS_TIME, 0.0, 1.0)
    # 上下黑边：明显的“聚焦取景”
    var bar_height := 90.0 * (0.35 + 0.65 * progress)
    draw_rect(Rect2(0.0, 0.0, size.x, bar_height), Color(0.0, 0.0, 0.0, 0.88))
    draw_rect(Rect2(0.0, size.y - bar_height, size.x, bar_height), Color(0.0, 0.0, 0.0, 0.88))
    # 玩家周围保留清晰区，四周强压暗
    var canvas := get_viewport().get_canvas_transform()
    var center: Vector2 = canvas * race.player.position
    var hole := 200.0
    for i: int in range(14):
        var radius := hole + float(i) * 40.0
        var alpha := 0.025 + float(i) * 0.013
        draw_arc(center, radius, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, alpha), 40.0, true)
    draw_arc(center, hole, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.16), 2.0, true)
    # 四角角标
    var corner := 46.0
    for pivot: Vector2 in [Vector2(0.0, 0.0), Vector2(size.x, 0.0), Vector2(0.0, size.y), Vector2(size.x, size.y)]:
        var dir_x := 1.0 if pivot.x < size.x * 0.5 else -1.0
        var dir_y := 1.0 if pivot.y < size.y * 0.5 else -1.0
        draw_line(pivot, pivot + Vector2(corner * dir_x, 0.0), Color(1.0, 1.0, 1.0, 0.26), 2.0)
        draw_line(pivot, pivot + Vector2(0.0, corner * dir_y), Color(1.0, 1.0, 1.0, 0.26), 2.0)


func _build_ui() -> void:
    _panel = UiKit.panel(Color(0.02, 0.02, 0.02, 0.9), Tuning.COLOR_TEXT_DIM, 18.0)
    _panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    _panel.custom_minimum_size = Vector2(940.0, 104.0)
    _panel.position = Vector2(-470.0, -238.0)
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_panel)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel.add_child(column)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    column.add_child(header)
    _progress_label = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    _progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(_progress_label)

    _text_label = UiKit.label("", 30, Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
    _text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    _text_label.custom_minimum_size = Vector2(900.0, 0.0)
    column.add_child(_text_label)


func _show_current() -> void:
    var step: Dictionary = _steps[_index]
    _text_label.text = str(step.get("text", ""))
    var focus_text := "聚焦慢动作" if not prestart else "学习模式"
    _progress_label.text = "%s    引导 %d/%d" % [focus_text, _index + 1, _steps.size()]
    _start_focus()


func _condition_met(condition: String) -> bool:
    if race == null or race.player == null:
        return false
    var player: Racer = race.player
    match condition:
        "accelerate":
            return player.throttle_in > 0.25 or player.current_speed() > 25.0
        "steer":
            return absf(player.steer_in) > 0.30
        "brake":
            return player.throttle_in < -0.25
        "coast":
            return absf(player.throttle_in) < 0.05 and player.current_speed() < 90.0
        "fuse":
            return player.pack != null
        "eye":
            return race.stats_eye_collisions > _eye_hits_start
        "slope_up":
            return race.player_slope() < -0.25
        "low_stamina":
            return player.stamina < 0.45
        "debris":
            return race.stats_debris_collisions > _debris_hits_start
        "leaf":
            return race.stats_leaf_collisions > _leaf_hits_start
        _:
            return false


func _prestart_text(kind: String) -> String:
    if OS.has_feature("mobile"):
        var gyro := GyroProbe.available and bool(SettingsStore.load_settings().get("gyro", false))
        if gyro:
            match kind:
                "accelerate":
                    return "向 Poga 前方倾斜设备加速"
                "steer":
                    return "向左 / 右倾斜设备转向"
                "brake":
                    return "向反方向倾斜设备刹车"
                _:
                    return "放平设备滑行 —— 滑行会慢慢恢复耐力"
        match kind:
            "accelerate":
                return "同时按住屏幕左右两侧加速"
            "steer":
                return "按住屏幕左侧 / 右侧转向"
            "brake":
                return "从屏幕向下划并按住刹车，松手结束"
            _:
                return "松开屏幕滑行 —— 滑行会慢慢恢复耐力"
    if InputDevice.last == &"gamepad":
        match kind:
            "accelerate":
                return "按手柄 A 加速"
            "steer":
                return "用 D-Pad 左右转向"
            "brake":
                return "按手柄 B 刹车"
            _:
                return "松开手柄滑行 —— 滑行会慢慢恢复耐力"
    match kind:
        "accelerate":
            return "按住 W / ↑ 加速"
        "steer":
            return "用 A / D 或 ← / → 转向"
        "brake":
            return "按 S / 空格 刹车"
        _:
            return "松开按键滑行 —— 滑行会慢慢恢复耐力"


func _build_steps() -> Array[Dictionary]:
    if prestart:
        return [
            {"text": _prestart_text("accelerate"), "cond": "accelerate"},
            {"text": _prestart_text("steer"), "cond": "steer"},
            {"text": _prestart_text("brake"), "cond": "brake"},
            {"text": _prestart_text("coast"), "cond": "coast"},
            {"text": "很好，爬到前面的起跑线吧", "cond": ""},
        ]
    match level_index:
        1:
            return [
                {"text": "上坡：路面变暗、出现向上箭头；下坡：变亮、箭头反向", "cond": "slope_up"},
                {"text": "耐力低于 30% 会明显掉速，滑行一下再加速", "cond": "low_stamina"},
                {"text": "下坡速度更快，但转向变钝，提前转向哦", "cond": ""},
            ]
        2:
            return [
                {"text": "树枝、落叶、石子都会让你掉速 —— 提前绕开", "cond": "debris"},
                {"text": "贴边蹭到树叶同样算碰撞，会被弹回路面", "cond": "leaf"},
                {"text": "保持纵列能吃到更多融合增益，终点前再突围", "cond": ""},
            ]
        _:
            return [
                {"text": "靠近其他史莱姆可以合成条大区", "cond": "fuse"},
                {"text": "你们的眼睛撞在一起会掉速、甚至把整团撞散", "cond": "eye"},
                {"text": "目标：以第一名冲过终点线", "cond": ""},
            ]
