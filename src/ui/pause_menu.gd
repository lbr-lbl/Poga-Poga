class_name PauseMenu
extends Control
## 游戏内暂停菜单：继续 / 重试 / 返回主菜单。
##
## 由 Main 在按 Esc 时挂到 UI 层并把 `get_tree().paused` 设为 true；
## 自身 process_mode = WHEN_PAUSED，所以暂停时仍能响应输入。

signal resume_pressed()
signal retry_pressed()
signal menu_pressed()

var _first_button: Button


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    _build()
    _first_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("back"):
        resume_pressed.emit()
        get_viewport().set_input_as_handled()


func _build() -> void:
    var shade := ColorRect.new()
    shade.color = Color(0.0, 0.0, 0.0, 0.62)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(shade)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var panel := UiKit.panel(Tuning.COLOR_PANEL, UiKit.PANEL_BORDER, 22.0)
    panel.custom_minimum_size = Vector2(520.0, 0.0)
    center.add_child(panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    panel.add_child(column)

    column.add_child(UiKit.label("时间暂停", 70, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
    column.add_child(UiKit.separator())
    column.add_child(UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

    _first_button = UiKit.button("继续吧", UiKit.SIZE_BODY, 12.0, "ui_confirm")
    _first_button.custom_minimum_size = Vector2(0.0, 50.0)
    _first_button.pressed.connect(func() -> void: resume_pressed.emit())
    column.add_child(_first_button)

    var retry := UiKit.button("再来！", UiKit.SIZE_BODY, 12.0, "ui_click")
    retry.custom_minimum_size = Vector2(0.0, 50.0)
    retry.pressed.connect(func() -> void: retry_pressed.emit())
    column.add_child(retry)

    var menu := UiKit.button("不玩啦", UiKit.SIZE_BODY, 12.0, "ui_back")
    menu.custom_minimum_size = Vector2(0.0, 50.0)
    menu.pressed.connect(func() -> void: menu_pressed.emit())
    column.add_child(menu)

    column.add_child(UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
