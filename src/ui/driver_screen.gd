class_name DriverScreen
extends Control
## 车手界面：等级 / 经验 / 属性加点。
##
## - 洗点：返还全部已用加点，**不回退车手等级与经验**；
## - 重置车手等级：清空等级/经验/加点（需要二次确认，避免误触）；
## - Esc 返回主菜单。

signal back_pressed()

const RESET_CONFIRM_TIME := 3.0

var _level_label: Label
var _xp_bar: UiKit.PixBar
var _xp_label: Label
var _points_label: Label
var _stat_value_labels: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _respec_button: Button
var _reset_level_button: Button
var _confirm_timer: float = 0.0


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build()
    refresh()
    for key: String in GameState.STAT_KEYS:
        if _upgrade_buttons.has(key):
            (_upgrade_buttons[key] as Button).grab_focus()
            break


func _process(delta: float) -> void:
    if _confirm_timer > 0.0:
        _confirm_timer -= delta
        if _confirm_timer <= 0.0:
            _reset_level_button.text = "重置Poga等级（清空等级/经验/加点）"


func refresh() -> void:
    _level_label.text = "Lv.%d" % GameState.level
    _level_label.add_theme_color_override("font_color", Tuning.COLOR_ACCENT)
    if GameState.level >= GameState.LEVEL_MAX:
        _xp_bar.set_value(1.0)
        _xp_label.text = "已达最高等级"
    else:
        _xp_bar.set_value(GameState.xp_progress())
        _xp_label.text = "经验 %d / %d" % [GameState.xp, GameState.xp_to_next()]
    _points_label.text = "可用加点 %d    已用 %d / 总计 %d" % [
        GameState.available_points(), GameState.points_spent(), GameState.total_points_earned(),
    ]
    for key: String in GameState.STAT_KEYS:
        var level := GameState.stat_level(key)
        (_stat_value_labels[key] as Label).text = "%d/5" % level
        (_upgrade_buttons[key] as Button).disabled = not GameState.can_upgrade(key)
    _respec_button.disabled = GameState.points_spent() <= 0


func _build() -> void:
    add_child(MenuBackdrop.new())

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 60)
    margin.add_theme_constant_override("margin_right", 60)
    margin.add_theme_constant_override("margin_top", 40)
    margin.add_theme_constant_override("margin_bottom", 24)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 18)
    column.add_child(header)
    var title := UiKit.label("Poga", 60, Tuning.COLOR_ACCENT)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    var status := VBoxContainer.new()
    status.custom_minimum_size = Vector2(360.0, 0.0)
    status.add_theme_constant_override("separation", 6)
    header.add_child(status)
    _level_label = UiKit.label("Lv.0", 40, Tuning.COLOR_ACCENT)
    status.add_child(_level_label)
    _xp_bar = UiKit.bar(16.0)
    _xp_bar.custom_minimum_size = Vector2(0.0, 16.0)
    status.add_child(_xp_bar)
    _xp_label = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    status.add_child(_xp_label)

    column.add_child(UiKit.separator())

    var content := HBoxContainer.new()
    content.add_theme_constant_override("separation", 18)
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(content)

    var panel := UiKit.panel(Tuning.COLOR_PANEL, UiKit.PANEL_BORDER_DIM, 18.0)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_child(panel)
    var panel_column := VBoxContainer.new()
    panel_column.add_theme_constant_override("separation", 12)
    panel.add_child(panel_column)

    _points_label = UiKit.label("", UiKit.SIZE_BODY, Tuning.COLOR_ACCENT)
    panel_column.add_child(_points_label)
    panel_column.add_child(UiKit.separator())

    for key: String in GameState.STAT_KEYS:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        panel_column.add_child(row)
        var name_label := UiKit.label(GameState.STAT_NAMES[key], UiKit.SIZE_BODY, Tuning.COLOR_TEXT)
        name_label.custom_minimum_size = Vector2(72.0, 0.0)
        row.add_child(name_label)
        var desc := UiKit.label(_stat_description(key), UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
        desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(desc)
        var value_label := UiKit.label("0/5", UiKit.SIZE_BODY, Tuning.COLOR_ACCENT)
        value_label.custom_minimum_size = Vector2(64.0, 0.0)
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        row.add_child(value_label)
        _stat_value_labels[key] = value_label
        var upgrade := UiKit.button("+", UiKit.SIZE_BODY, 4.0, "ui_confirm")
        upgrade.custom_minimum_size = Vector2(48.0, 40.0)
        upgrade.pressed.connect(_on_upgrade_pressed.bind(key))
        row.add_child(upgrade)
        _upgrade_buttons[key] = upgrade

    panel_column.add_child(UiKit.separator())
    panel_column.add_child(UiKit.label("洗点只返还加点，不影响Poga等级与经验。", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))
    _respec_button = UiKit.button("洗点（返还全部加点）", UiKit.SIZE_BODY, 10.0, "ui_click")
    _respec_button.custom_minimum_size = Vector2(0.0, 46.0)
    _respec_button.pressed.connect(_on_respec_pressed)
    panel_column.add_child(_respec_button)

    _reset_level_button = UiKit.button("重置Poga等级（清空等级/经验/加点）", UiKit.SIZE_SMALL, 8.0, "ui_back")
    _reset_level_button.custom_minimum_size = Vector2(0.0, 42.0)
    _reset_level_button.pressed.connect(_on_reset_level_pressed)
    panel_column.add_child(_reset_level_button)

    var back := UiKit.button("返回主菜单  Esc", UiKit.SIZE_BODY, 10.0, "ui_back")
    back.custom_minimum_size = Vector2(0.0, 50.0)
    back.pressed.connect(func() -> void: back_pressed.emit())
    column.add_child(back)


func _stat_description(key: String) -> String:
    match key:
        "stamina":
            return "耐力上限 / 恢复速度"
        "speed":
            return "加速度 / 极速"
        "stability":
            return "抓地 / 抗散团"
        _:
            return ""


func _on_upgrade_pressed(key: String) -> void:
    GameState.upgrade(key)
    refresh()


func _on_respec_pressed() -> void:
    GameState.reset_alloc()
    refresh()


func _on_reset_level_pressed() -> void:
    # 二次确认：第一次点击只进入确认状态，3 秒内再点才真正重置
    if _confirm_timer <= 0.0:
        _confirm_timer = RESET_CONFIRM_TIME
        _reset_level_button.text = "你真的确定吗🤔"
        UiSfx.play("ui_click", -8.0)
        return
    _confirm_timer = 0.0
    _reset_level_button.text = "重置Poga等级（清空等级/经验/加点）"
    GameState.reset_level()
    refresh()
