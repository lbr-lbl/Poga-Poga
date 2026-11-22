class_name MainMenu
extends Control
## 主菜单：老式游戏机标题画面（attract mode）。
##
## - 刚进入时只有标题 + 闪烁的 PRESS ENTER，没有任何选项；
## - 按任意键/点击后选项才出现（PRESS ENTER 同时消失）；
## - 隐藏操作：连续点击标题 7 下解锁全部赛段。

signal start_pressed()
signal driver_pressed()
signal help_pressed()
signal quit_pressed()

const UNLOCK_CLICKS := 7
const UNLOCK_RESET_TIME := 2.5
const TITLE_FONT := 90

var _title: Label
var _prompt: Label
var _menu_box: VBoxContainer
var _buttons: Array[Button] = []
var _toast: Label
var _footer: Label
var _blink: float = 0.0
var _toast_timer: float = 0.0
var _title_clicks: int = 0
var _title_timer: float = 0.0
var _revealed: bool = false
var _input_lock: float = 0.22


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build()
    _prompt.visible = true
    _menu_box.visible = false
    _menu_box.modulate = Color(1.0, 1.0, 1.0, 0.0)
    _footer.visible = false


func _process(delta: float) -> void:
    _blink += delta
    if _input_lock > 0.0:
        _input_lock = maxf(0.0, _input_lock - delta)
    _prompt.modulate = Color(1.0, 1.0, 1.0, 0.55 + 0.45 * sin(_blink * 3.2))
    if _title_timer > 0.0:
        _title_timer -= delta
        if _title_timer <= 0.0:
            _title_clicks = 0
    if _toast_timer > 0.0:
        _toast_timer -= delta
        if _toast_timer <= 0.0:
            _toast.visible = false


func _input(event: InputEvent) -> void:
    if _revealed or _input_lock > 0.0:
        return
    # Esc 在标题画面不揭幕（避免误触），其它任意键/点击才进入菜单
    if event.is_action_pressed("back"):
        return
    if event is InputEventKey:
        if not (event as InputEventKey).pressed:
            return
    elif event is InputEventJoypadButton:
        if not (event as InputEventJoypadButton).pressed:
            return
    elif event is InputEventMouseButton:
        if not (event as InputEventMouseButton).pressed:
            return
    elif event is InputEventScreenTouch:
        if not (event as InputEventScreenTouch).pressed:
            return
    else:
        return
    if event.is_action_pressed("back"):
        return
    _reveal()
    get_viewport().set_input_as_handled()


## 供截图/调试使用：直接显示选项。
func reveal_now() -> void:
    _reveal()


func _reveal() -> void:
    if _revealed:
        return
    _revealed = true
    _prompt.visible = false
    _menu_box.visible = true
    _footer.visible = true
    UiSfx.play("ui_confirm", -8.0)
    var tween := create_tween()
    tween.tween_property(_menu_box, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.22)
    _buttons[0].grab_focus()


func _build() -> void:
    add_child(MenuBackdrop.new())

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 60)
    margin.add_theme_constant_override("margin_right", 60)
    margin.add_theme_constant_override("margin_top", 36)
    margin.add_theme_constant_override("margin_bottom", 24)
    add_child(margin)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    margin.add_child(column)

    var top := HBoxContainer.new()
    column.add_child(top)
    var player_tag := UiKit.label("1 PLAYER", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    player_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(player_tag)

    var spacer_top := Control.new()
    spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(spacer_top)

    # 标题：描边 + 阴影，做出街机 LOGO 的厚度
    _title = UiKit.label("POGA POGA", TITLE_FONT, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
    _title.custom_minimum_size = Vector2(0.0, 110.0)
    _title.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 1.0))
    _title.add_theme_constant_override("outline_size", 10)
    _title.add_theme_color_override("font_shadow_color", Color(0.12, 0.12, 0.12, 1.0))
    _title.add_theme_constant_override("shadow_offset_x", 5)
    _title.add_theme_constant_override("shadow_offset_y", 6)
    _title.mouse_filter = Control.MOUSE_FILTER_STOP
    _title.gui_input.connect(_on_title_input)
    column.add_child(_title)

    var spacer_prompt := Control.new()
    spacer_prompt.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(spacer_prompt)

    # 初始的 PRESS ANY KEY（只在没有选项时出现）
    _prompt = UiKit.label("轻触屏幕开始" if OS.has_feature("mobile") else "PRESS ANY KEY", UiKit.SIZE_BODY, Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
    _prompt.custom_minimum_size = Vector2(0.0, 48.0)
    column.add_child(_prompt)

    # 选项（揭示后才出现）
    _menu_box = VBoxContainer.new()
    _menu_box.add_theme_constant_override("separation", 10)
    _menu_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _menu_box.custom_minimum_size = Vector2(440.0, 0.0)
    column.add_child(_menu_box)

    var names: Array[String] = ["开始游戏", "设置", "Poga", "退出游戏"]
    var sounds: Array[String] = ["ui_confirm", "ui_click", "ui_click", "ui_back"]
    for index: int in range(names.size()):
        var button := UiKit.button(names[index], UiKit.SIZE_LARGE, 12.0, sounds[index])
        button.custom_minimum_size = Vector2(440.0, 56.0)
        button.alignment = HORIZONTAL_ALIGNMENT_CENTER
        button.focus_entered.connect(_refresh_focus)
        _menu_box.add_child(button)
        _buttons.append(button)
    _buttons[0].pressed.connect(_on_start_pressed)
    _buttons[1].pressed.connect(_on_help_pressed)
    _buttons[2].pressed.connect(_on_driver_pressed)
    _buttons[3].pressed.connect(_on_quit_pressed)

    _toast = UiKit.label("", UiKit.SIZE_BODY, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
    _toast.visible = false
    column.add_child(_toast)

    var spacer_bottom := Control.new()
    spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(spacer_bottom)
    _footer = UiKit.label("轻触选择 · 点按确认" if OS.has_feature("mobile") else "↑↓ 选择     Enter 确认     Esc 返回     M 音乐静音", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
    column.add_child(_footer)
    _refresh_focus()


func _refresh_focus() -> void:
    for button: Button in _buttons:
        UiKit.set_button_selected(button, button.has_focus(), 12.0)


func _on_start_pressed() -> void:
    start_pressed.emit()


func _on_help_pressed() -> void:
    help_pressed.emit()


func _on_driver_pressed() -> void:
    driver_pressed.emit()


func _on_quit_pressed() -> void:
    quit_pressed.emit()


func _on_title_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton):
        return
    var mouse: InputEventMouseButton = event
    if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
        return
    _title_clicks += 1
    _title_timer = UNLOCK_RESET_TIME
    if _title_clicks < UNLOCK_CLICKS:
        return
    _title_clicks = 0
    _title_timer = 0.0
    GameState.debug_unlock_all()
    UiSfx.play("ui_confirm", -4.0)
    _toast.text = "全部赛段已解锁"
    _toast.visible = true
    _toast_timer = 2.2
