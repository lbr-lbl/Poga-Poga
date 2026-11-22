class_name LevelSelect
extends Control
## 赛段选择：**点击赛段立即出发**（选关与开始游戏不再分离）。
##
## 右侧只保留“对手性格 / 操作指引 / 返回”，不再有单独的“开始比赛”按钮。

signal start_pressed(level_index: int)
signal back_pressed()

const LEVEL_BLURBS: Array[String] = [
    "宽环形赛道：熟悉加速 / 滑行 / 转向 / 自动融合",
    "上坡耗耐力，下坡转向变难",
    "树枝落叶小石子：碰撞掉耐力、易散团",
    "最终赛段：12.8km 长赛道 + 连续起伏 + 落石，9 只对手，1 圈定胜负",
]

var _selected: int = 0
var _level_buttons: Array[Button] = []
var _blurb: Label
var _minimap: TrackMiniMap
var _tier_buttons: Array[Button] = []
var _skip_button: Button
var _tier_info: Label


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _selected = clampi(GameState.selected_level, 0, GameState.unlocked_levels - 1)
    _build()
    refresh()
    _focus_default()


func _focus_default() -> void:
    for index: int in range(_level_buttons.size()):
        if not _level_buttons[index].disabled:
            _level_buttons[index].grab_focus()
            return


func refresh() -> void:
    for index: int in range(_level_buttons.size()):
        var level: LevelDef = LevelCatalog.get_level(index)
        var button := _level_buttons[index]
        var unlocked := index < GameState.unlocked_levels
        var text := "%s   %s   ·   %d 圈" % [level.subtitle, level.display_name, level.total_laps]
        if not unlocked:
            text += "   （未解锁）"
        else:
            var best_time: float = float(GameState.best_times[index])
            if best_time > 0.0:
                text += "     最佳 %s" % GameState.format_time(best_time)
        button.text = text
        button.disabled = not unlocked
        UiKit.set_button_selected(button, index == _selected, 10.0)

    for tier: int in range(_tier_buttons.size()):
        var button := _tier_buttons[tier]
        UiKit.set_button_selected(button, tier == GameState.selected_tier, 6.0)
    var coef := GameState.AI_TIER_XP_COEF[GameState.selected_tier]
    _tier_info.text = ""

    _skip_button.text = "需要操作指引：%s" % ("开" if GameState.guide_enabled else "关")
    UiKit.set_button_selected(_skip_button, GameState.guide_enabled, 10.0)
    _blurb.text = LEVEL_BLURBS[_selected]
    if _minimap != null:
        _minimap.setup(_selected)


func _build() -> void:
    add_child(MenuBackdrop.new())

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 60)
    margin.add_theme_constant_override("margin_right", 60)
    margin.add_theme_constant_override("margin_top", 44)
    margin.add_theme_constant_override("margin_bottom", 30)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)

    var header := HBoxContainer.new()
    column.add_child(header)
    var title := UiKit.label("选择地图", 60, Tuning.COLOR_ACCENT)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    header.add_child(UiKit.label("点击地图立即出发", UiKit.SIZE_BODY, Tuning.COLOR_TEXT_DIM))

    column.add_child(UiKit.separator())

    var content := HBoxContainer.new()
    content.add_theme_constant_override("separation", 22)
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(content)

    # 左侧：赛段列表（点击立即开始）
    var list_box := VBoxContainer.new()
    list_box.add_theme_constant_override("separation", 8)
    list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_child(list_box)
    for index: int in range(LevelCatalog.COUNT):
        var button := UiKit.button("", UiKit.SIZE_SMALL, 12.0, "ui_confirm")
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.custom_minimum_size = Vector2(0.0, 48.0)
        button.focus_entered.connect(_on_level_focused.bind(index))
        button.pressed.connect(_on_level_pressed.bind(index))
        list_box.add_child(button)
        _level_buttons.append(button)

    _blurb = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    _blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    list_box.add_child(_blurb)

    _minimap = TrackMiniMap.new()
    _minimap.custom_minimum_size = Vector2(0.0, 170.0)
    _minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list_box.add_child(_minimap)

    # 右侧：对手强度 / 跳过指引 / 返回
    var side := VBoxContainer.new()
    side.custom_minimum_size = Vector2(352.0, 0.0)
    side.add_theme_constant_override("separation", 10)
    content.add_child(side)

    var panel := UiKit.panel(Tuning.COLOR_PANEL, UiKit.PANEL_BORDER_DIM, 16.0)
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    side.add_child(panel)
    var panel_column := VBoxContainer.new()
    panel_column.add_theme_constant_override("separation", 10)
    panel.add_child(panel_column)
    panel_column.add_child(UiKit.label("对手性格", UiKit.SIZE_BODY, Tuning.COLOR_TEXT))
    var tier_row := HBoxContainer.new()
    tier_row.add_theme_constant_override("separation", 6)
    panel_column.add_child(tier_row)
    for tier: int in range(3):
        var button := UiKit.button(GameState.AI_TIER_NAMES[tier], UiKit.SIZE_SMALL, 6.0, "ui_click")
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.custom_minimum_size = Vector2(0.0, 38.0)
        button.pressed.connect(_on_tier_pressed.bind(tier))
        tier_row.add_child(button)
        _tier_buttons.append(button)
    _tier_info = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    _tier_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    panel_column.add_child(_tier_info)
    panel_column.add_child(UiKit.separator())

    _skip_button = UiKit.button("", UiKit.SIZE_SMALL, 10.0, "ui_click")
    _skip_button.custom_minimum_size = Vector2(0.0, 40.0)
    _skip_button.pressed.connect(_on_skip_pressed)
    panel_column.add_child(_skip_button)
    var skip_hint := UiKit.label("勾选后，前三关第一次遇到坡度/低耐力/障碍时会提示；第一关另有空地序章。", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    skip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    skip_hint.custom_minimum_size = Vector2(320.0, 0.0)
    panel_column.add_child(skip_hint)

    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel_column.add_child(spacer)
    var unlock_hint := UiKit.label("提示：连点主菜单标题 7 下可解锁全部赛段", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    unlock_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    unlock_hint.custom_minimum_size = Vector2(320.0, 0.0)
    panel_column.add_child(unlock_hint)

    var back := UiKit.button("返回主菜单  Esc", UiKit.SIZE_BODY, 12.0, "ui_back")
    back.custom_minimum_size = Vector2(0.0, 52.0)
    back.pressed.connect(func() -> void: back_pressed.emit())
    side.add_child(back)


func _on_level_focused(index: int) -> void:
    _selected = index
    refresh()


func _on_level_pressed(index: int) -> void:
    if index >= GameState.unlocked_levels:
        return
    _selected = index
    GameState.set_selected_level(index)
    # 选关即开始
    start_pressed.emit(index)


func _on_tier_pressed(tier: int) -> void:
    GameState.set_selected_tier(tier)
    refresh()


func _on_skip_pressed() -> void:
    GameState.set_guide_enabled(not GameState.guide_enabled)
    refresh()
