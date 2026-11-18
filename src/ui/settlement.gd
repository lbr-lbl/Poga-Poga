class_name Settlement
extends Control
## 结算界面：排名、总时长、每圈记圈/圈速、获得经验与升级，以及重试 / 下一关 / 返回菜单。
##
## 风格与主菜单、HUD 统一：像素字体、纯灰度、直角细边框、30/20 字号层级。
## 不直接改存档：经验与升级由 Main 通过 GameState.register_result 计算后写入 result 再传入。

signal retry_pressed()
signal next_pressed()
signal menu_pressed()

var result: Dictionary = {}
var _next_button: Button


func setup(p_result: Dictionary) -> void:
	result = p_result


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


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
	var title := UiKit.label("第一名！" if won else "未获得第一", UiKit.SIZE_HERO if won else 60, Tuning.COLOR_ACCENT if won else Tuning.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
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

	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 26)
	rows.add_theme_constant_override("v_separation", 4)
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
	column.add_child(UiKit.label(xp_text, UiKit.SIZE_SMALL, Tuning.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))

	var bar := UiKit.bar(14.0)
	bar.custom_minimum_size = Vector2(420.0, 14.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.value = GameState.xp_progress()
	column.add_child(bar)
	var xp_line := "已累积 %d / %d 经验" % [GameState.xp, GameState.xp_to_next()] if GameState.level < GameState.LEVEL_MAX else "已达最高等级 Lv.%d" % GameState.level
	column.add_child(UiKit.label(xp_line, UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	column.add_child(UiKit.spacer(6))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	column.add_child(buttons)

	var retry := UiKit.button("重试  R", UiKit.SIZE_BODY)
	retry.pressed.connect(_on_retry)
	buttons.add_child(retry)

	_next_button = UiKit.button("下一关  Enter", UiKit.SIZE_BODY)
	_next_button.pressed.connect(_on_next)
	_next_button.disabled = not won or int(result.get("level_index", 0)) >= LevelCatalog.COUNT - 1
	buttons.add_child(_next_button)

	var menu := UiKit.button("返回菜单  Esc", UiKit.SIZE_BODY)
	menu.pressed.connect(_on_menu)
	buttons.add_child(menu)

	var hint := UiKit.label("失败可无限重试；每关目标：玩家个体第一", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(hint)

	if not _next_button.disabled:
		_next_button.grab_focus()
	else:
		retry.grab_focus()


func _add_row(parent: GridContainer, key: String, value: String) -> void:
	var key_label := UiKit.label(key, UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
	parent.add_child(key_label)
	var value_label := UiKit.label(value, UiKit.SIZE_SMALL, Tuning.COLOR_TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(value_label)


func _on_retry() -> void:
	retry_pressed.emit()


func _on_next() -> void:
	next_pressed.emit()


func _on_menu() -> void:
	menu_pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("retry"):
		retry_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm"):
		next_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back"):
		menu_pressed.emit()
		get_viewport().set_input_as_handled()