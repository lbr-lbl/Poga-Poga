class_name Settlement
extends Control
## 结算界面：排名、总时长、每圈、经验升级，以及重试/下一关/返回。
##
## 数据行逐条淡入，数值统一靠右；文案保持短句、口语化的语气。

signal retry_pressed()
signal next_pressed()
signal menu_pressed()

var result: Dictionary = {}
var _next_button: Button
var _row_nodes: Array[Control] = []


func setup(p_result: Dictionary) -> void:
    result = p_result


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    _build()
    _animate_rows()


func _build() -> void:
    var background := ColorRect.new()
    background.color = Color(0.02, 0.02, 0.02, 0.92)
    background.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(background)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var panel := UiKit.panel()
    panel.custom_minimum_size = Vector2(680.0, 0.0)
    center.add_child(panel)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    panel.add_child(column)

    var won: bool = bool(result.get("won", false))
    var title := UiKit.label("拿下！" if won else "可惜", UiKit.SIZE_HERO if won else 60, Tuning.COLOR_ACCENT if won else Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
    column.add_child(title)

    var level_name := str(result.get("level_name", ""))
    var subtitle := str(result.get("level_subtitle", ""))
    var tier: int = clampi(int(result.get("ai_tier", 1)), 0, 2)
    var headline := UiKit.label(
        "%s   %s   排名 %d/%d   对手 %s" % [
            subtitle, level_name, int(result.get("rank", 1)), int(result.get("racer_count", 1)),
            GameState.AI_TIER_NAMES[tier],
        ],
        UiKit.SIZE_BODY,
        Tuning.COLOR_TEXT,
        HORIZONTAL_ALIGNMENT_CENTER
    )
    column.add_child(headline)
    column.add_child(UiKit.separator())

    var rows := VBoxContainer.new()
    rows.custom_minimum_size = Vector2(560.0, 0.0)
    rows.add_theme_constant_override("separation", 4)
    column.add_child(rows)
    _add_row(rows, "总用时", GameState.format_time(float(result.get("total_time", 0.0))))
    if not bool(result.get("player_finished", true)):
        _add_row(rows, "状态", "未完赛（被对手先过线）")
    _add_row(rows, "总圈数", str(int(result.get("total_laps", 1))))

    var lap_times: Array = result.get("lap_times", [])
    for i: int in range(lap_times.size()):
        _add_row(rows, "第 %d 圈" % (i + 1), GameState.format_time(float(lap_times[i])))

    column.add_child(UiKit.separator())

    # 经验 / 等级
    var xp_gained := int(result.get("xp", 0))
    var levels_gained := int(result.get("levels_gained", 0))
    var xp_text := "获得经验 +%d" % xp_gained
    if levels_gained > 0:
        xp_text += "        升级！Lv.%d → Lv.%d（+%d 加点）" % [
            int(result.get("level_before", 0)), int(result.get("level_after", 0)), levels_gained,
        ]
    else:
        xp_text += "        当前 Lv.%d" % GameState.level
    var xp_label := UiKit.label(xp_text, UiKit.SIZE_SMALL, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
    column.add_child(xp_label)
    _row_nodes.append(xp_label)

    var bar := UiKit.bar(14.0)
    bar.custom_minimum_size = Vector2(420.0, 14.0)
    bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    bar.set_value(GameState.xp_progress())
    column.add_child(bar)
    var xp_line := "已累积 %d / %d 经验" % [GameState.xp, GameState.xp_to_next()] if GameState.level < GameState.LEVEL_MAX else "已达最高等级 Lv.%d" % GameState.level
    var xp_bar_label := UiKit.label(xp_line, UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
    column.add_child(xp_bar_label)
    _row_nodes.append(xp_bar_label)

    column.add_child(UiKit.spacer(6))
    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 14)
    column.add_child(buttons)

    var retry := UiKit.button("重试", UiKit.SIZE_BODY)
    retry.pressed.connect(_on_retry)
    buttons.add_child(retry)

    _next_button = UiKit.button("下一关", UiKit.SIZE_BODY, 22.0, "ui_confirm")
    _next_button.pressed.connect(_on_next)
    _next_button.disabled = not won or int(result.get("level_index", 0)) >= LevelCatalog.COUNT - 1
    buttons.add_child(_next_button)

    var menu := UiKit.button("返回菜单", UiKit.SIZE_BODY, 22.0, "ui_back")
    menu.pressed.connect(_on_menu)
    buttons.add_child(menu)

    var hint := UiKit.label("越挫越勇，Poga想当第一名", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
    column.add_child(hint)

    if not _next_button.disabled:
        _next_button.grab_focus()
    else:
        retry.grab_focus()


func _add_row(parent: VBoxContainer, key: String, value: String) -> void:
    var row := HBoxContainer.new()
    row.custom_minimum_size = Vector2(560.0, 24.0)
    row.add_theme_constant_override("separation", 18)
    parent.add_child(row)
    var key_label := UiKit.label(key, UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
    key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(key_label)
    var value_label := UiKit.label(value, UiKit.SIZE_SMALL, Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
    value_label.custom_minimum_size = Vector2(180.0, 0.0)
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    row.add_child(value_label)
    _row_nodes.append(row)


func _animate_rows() -> void:
    for i: int in range(_row_nodes.size()):
        var node := _row_nodes[i]
        node.modulate = Color(1.0, 1.0, 1.0, 0.0)
        var tween := create_tween()
        tween.tween_interval(float(i) * 0.06)
        tween.tween_property(node, "modulate:a", 1.0, 0.12)


func _on_retry() -> void:
    retry_pressed.emit()


func _on_next() -> void:
    next_pressed.emit()


func _on_menu() -> void:
    menu_pressed.emit()
