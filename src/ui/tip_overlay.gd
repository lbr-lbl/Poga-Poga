class_name TipOverlay
extends Control
## 情境提示（v0.14）：
##
## - 每次进入关卡都重新计数：每种提示在本次比赛里第一次遇到时出现；
## - 坡度提示在**即将进入坡道**时触发；低耐力/障碍/贴边/纵列/融合/眼睛也各自在第一次触发；
## - 每条提示显示约 1 秒，同时短促慢动作 + 强聚焦（上下黑边 + 四周压暗 + 镜头拉近）；
## - 无头自动测试不创建本节点。

const SHOW_TIME := 1.0
const FOCUS_TIME := 0.6
const FOCUS_SCALE := 0.32
const FOCUS_ZOOM := 1.34
const TIP_COOLDOWN := 1.6
const DETACHED_TIME := 6.0

const TIP_SLOPE_UP := 0
const TIP_SLOPE_DOWN := 1
const TIP_LOW_STAMINA := 2
const TIP_DEBRIS := 3
const TIP_LEAF := 4
const TIP_COLUMN := 5
const TIP_FUSE := 6
const TIP_EYE := 7

var race: Race

var _panel: PanelContainer
var _label: Label
var _timer: float = 0.0
var _focus: float = 0.0
var _cooldown: float = 0.0
var _detached_time: float = 0.0
var _restore_scale: float = 1.0
var _seen_mask: int = 0


func setup(p_race: Race) -> void:
    race = p_race


func _ready() -> void:
    size = get_viewport_rect().size
    position = Vector2.ZERO
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build()
    set_process(true)


func _exit_tree() -> void:
    Engine.time_scale = 1.0
    if race != null:
        race.camera_zoom_bias = 1.0


func _build() -> void:
    _panel = UiKit.panel(Color(0.02, 0.02, 0.02, 0.92), Tuning.COLOR_TEXT_DIM, 16.0)
    _panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _panel.custom_minimum_size = Vector2(820.0, 76.0)
    _panel.position = Vector2(-410.0, 96.0)
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel.visible = false
    add_child(_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 2)
    _panel.add_child(column)
    column.add_child(UiKit.label("小提示", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))
    _label = UiKit.label("", UiKit.SIZE_BODY, Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
    _label.autowrap_mode = TextServer.AUTOWRAP_OFF
    column.add_child(_label)


func _process(delta: float) -> void:
    if race == null or race.player == null:
        return
    if race.state != Race.State.RACING:
        return
    if _timer > 0.0:
        _timer -= delta
        if _focus > 0.0:
            _focus -= delta
            if _focus <= 0.0:
                _end_focus()
        if _timer <= 0.0:
            _hide()
        queue_redraw()
        return
    if _cooldown > 0.0:
        _cooldown -= delta
        return
    # 记录“离开融合团”的持续时间
    if race.player.pack == null:
        _detached_time += delta
    else:
        _detached_time = 0.0
    _check_tips()


func _check_tips() -> void:
    var player: Racer = race.player
    if player == null or race.race_time < 0.6:
        return
    var slope := race.approaching_slope()
    if slope < 0 and not _seen(TIP_SLOPE_UP):
        _show(TIP_SLOPE_UP, "前方上坡：路面会变暗，注意耐力")
        return
    if slope > 0 and not _seen(TIP_SLOPE_DOWN):
        _show(TIP_SLOPE_DOWN, "前方下坡：路面会变亮，转向会变钝")
        return
    if race.debris_ahead() and not _seen(TIP_DEBRIS):
        _show(TIP_DEBRIS, "前方有障碍：提前绕开，撞上会掉速")
        return
    if player.stamina < 0.30 and not _seen(TIP_LOW_STAMINA):
        _show(TIP_LOW_STAMINA, "耐力低于 30%：明显掉速，滑行一下再加速")
        return
    if player.center_dist > race.track.half_width * 0.72 and not _seen(TIP_LEAF):
        _show(TIP_LEAF, "贴近路边树叶会碰撞，会被弹回路面")
        return
    if _detached_time > DETACHED_TIME and not _seen(TIP_COLUMN):
        _show(TIP_COLUMN, "离开融合团太久了：靠近其它小伙伴形成纵列更省力")
        return
    if player.pack != null and not _seen(TIP_FUSE):
        _show(TIP_FUSE, "已自动融合：团内会共享一部分速度增益")
        return
    if race.stats_eye_collisions > 0 and not _seen(TIP_EYE):
        _show(TIP_EYE, "眼睛撞在一起会掉速，撞得深还会散团")
        return


## 调试/截图用：直接弹一条提示。
func debug_show(text: String) -> void:
    _show(TIP_LOW_STAMINA, text)


func is_showing() -> bool:
    return _timer > 0.0


func _seen(tip_id: int) -> bool:
    return (_seen_mask & (1 << tip_id)) != 0


func _show(tip_id: int, text: String) -> void:
    _seen_mask |= 1 << tip_id
    _label.text = text
    _panel.visible = true
    _timer = SHOW_TIME
    _focus = FOCUS_TIME
    _cooldown = TIP_COOLDOWN
    _restore_scale = 1.0
    Engine.time_scale = FOCUS_SCALE
    if race != null:
        race.camera_zoom_bias = FOCUS_ZOOM
    queue_redraw()


func _hide() -> void:
    _timer = 0.0
    _panel.visible = false
    _end_focus()
    queue_redraw()


func _end_focus() -> void:
    _focus = 0.0
    Engine.time_scale = 1.0
    if race != null:
        race.camera_zoom_bias = 1.0


func _draw() -> void:
    if _focus <= 0.0 or race == null or race.player == null:
        return
    var progress := clampf(_focus / FOCUS_TIME, 0.0, 1.0)
    # 上下黑边：明显的“聚焦”表现
    var bar_height := 84.0 * (0.35 + 0.65 * progress)
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
    draw_arc(center, hole, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.18), 2.0, true)
    # 四角角标，进一步强化“聚焦取景”
    var corner := 46.0
    for pivot: Vector2 in [Vector2(0.0, 0.0), Vector2(size.x, 0.0), Vector2(0.0, size.y), Vector2(size.x, size.y)]:
        var dir_x := 1.0 if pivot.x < size.x * 0.5 else -1.0
        var dir_y := 1.0 if pivot.y < size.y * 0.5 else -1.0
        draw_line(pivot, pivot + Vector2(corner * dir_x, 0.0), Color(1.0, 1.0, 1.0, 0.28), 2.0)
        draw_line(pivot, pivot + Vector2(0.0, corner * dir_y), Color(1.0, 1.0, 1.0, 0.28), 2.0)
