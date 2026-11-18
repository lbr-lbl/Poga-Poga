class_name MainMenu
extends Control
## 主菜单：选关、AI 难度、车手等级/经验、属性加点、操作说明。
##
## 风格约定（与比赛 HUD / 结算统一）：
## - 像素字体、纯灰度、直角细边框面板、统一的 30/20 字号层级；
## - 顶部是身份区（标题 + 等级/经验），中部左右两栏，底部操作提示；
## - 所有可交互元素都走 UiKit，选中态用 UiKit.set_button_selected()。

signal level_selected(index: int)
signal quit_pressed()

const LEVEL_BLURBS: Array[String] = [
	"宽环形赛道：熟悉加速 / 滑行 / 转向 / 自动融合",
	"上坡减速耗耐，下坡转向变难",
	"树枝落叶小石子：碰撞掉耐、易散团",
]

var _level_buttons: Array[Button] = []
var _level_labels: Array[Label] = []
var _tier_buttons: Array[Button] = []
var _stat_value_labels: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _points_label: Label
var _level_label: Label
var _xp_bar: UiKit.PixBar
var _xp_label: Label
var _best_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()
	_focus_default()


func _focus_default() -> void:
	# 键盘/手柄进入菜单时给一个默认焦点，避免只能用鼠标
	for index: int in range(_level_buttons.size()):
		if not _level_buttons[index].disabled:
			_level_buttons[index].grab_focus()
			return


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("090909")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var decor := MenuDecor.new()
	decor.set_anchors_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(decor)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_build_header())
	column.add_child(UiKit.separator())

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	content.add_child(_build_race_panel())
	content.add_child(_build_driver_panel())

	column.add_child(UiKit.separator())
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	var hint := UiKit.label(
		"W/↑ 加速    A D 转向    S/空格 刹车    松开滑行    R 重试    ESC 返回",
		UiKit.SIZE_SMALL,
		Tuning.COLOR_TEXT_DIM
	)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hint)
	var quit := UiKit.button("退出游戏", UiKit.SIZE_SMALL, 14.0)
	quit.custom_minimum_size = Vector2(140.0, 38.0)
	quit.pressed.connect(_on_quit_pressed)
	bottom.add_child(quit)


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(UiKit.label("POGA POGA", 50, Tuning.COLOR_ACCENT))
	left.add_child(UiKit.label("史莱姆融合竞速 · 最小可玩版本", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(360.0, 0.0)
	row.add_child(right)

	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 10)
	right.add_child(level_row)
	_level_label = UiKit.label("Lv.0", 40, Tuning.COLOR_ACCENT)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_row.add_child(_level_label)
	_best_label = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_row.add_child(_best_label)

	_xp_bar = UiKit.bar(16.0)
	right.add_child(_xp_bar)
	_xp_label = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
	right.add_child(_xp_label)
	return row


func _build_race_panel() -> Control:
	var panel := UiKit.panel(Tuning.COLOR_PANEL, UiKit.PANEL_BORDER_DIM, 14.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	column.add_child(UiKit.label("比赛", UiKit.SIZE_BODY, Tuning.COLOR_TEXT))

	# 对手强度（三段式选择）
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 8)
	column.add_child(tier_row)
	tier_row.add_child(UiKit.label("对手强度", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))
	for tier: int in range(3):
		var button := UiKit.button("", UiKit.SIZE_SMALL, 10.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0.0, 36.0)
		button.pressed.connect(_on_tier_pressed.bind(tier))
		tier_row.add_child(button)
		_tier_buttons.append(button)
	column.add_child(UiKit.spacer(2))

	var levels := LevelCatalog.all()
	for i: int in range(levels.size()):
		var button := UiKit.button("", UiKit.SIZE_SMALL, 14.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.pressed.connect(_on_level_pressed.bind(i))
		column.add_child(button)
		_level_buttons.append(button)

		var caption := UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.custom_minimum_size = Vector2(0.0, 20.0)
		column.add_child(caption)
		_level_labels.append(caption)
	return panel


func _build_driver_panel() -> Control:
	var panel := UiKit.panel(Tuning.COLOR_PANEL, UiKit.PANEL_BORDER_DIM, 14.0)
	panel.custom_minimum_size = Vector2(400.0, 0.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	column.add_child(UiKit.label("车手", UiKit.SIZE_BODY, Tuning.COLOR_TEXT))
	_points_label = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
	_points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_points_label)
	column.add_child(UiKit.separator())
	column.add_child(UiKit.label("属性", UiKit.SIZE_BODY, Tuning.COLOR_TEXT))

	var definitions := [
		{"key": "stamina", "name": "耐力", "desc": "上限/恢复"},
		{"key": "speed", "name": "速度", "desc": "加速/极速"},
		{"key": "stability", "name": "稳定", "desc": "抓地/抗散"},
	]
	for definition: Dictionary in definitions:
		var key: String = definition["key"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := UiKit.label(str(definition["name"]), UiKit.SIZE_SMALL, Tuning.COLOR_TEXT)
		name_label.custom_minimum_size = Vector2(48.0, 0.0)
		row.add_child(name_label)
		var desc_label := UiKit.label(str(definition["desc"]), UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc_label)
		var value_label := UiKit.label("0/5", UiKit.SIZE_SMALL, Tuning.COLOR_ACCENT)
		value_label.custom_minimum_size = Vector2(44.0, 0.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		var plus := UiKit.button("+", UiKit.SIZE_SMALL, 8.0)
		plus.custom_minimum_size = Vector2(40.0, 30.0)
		plus.pressed.connect(_on_upgrade_pressed.bind(key))
		row.add_child(plus)
		column.add_child(row)
		_stat_value_labels[key] = value_label
		_upgrade_buttons[key] = plus

	column.add_child(UiKit.spacer(2))
	var reset := UiKit.button("重置等级与加点", UiKit.SIZE_SMALL, 12.0)
	reset.custom_minimum_size = Vector2(0.0, 36.0)
	reset.pressed.connect(_on_reset_pressed)
	column.add_child(reset)

	var tip := UiKit.label("升级 +1 加点，属性等级 0→5", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM)
	column.add_child(tip)
	return panel


# ------------------------------------------------------------------ 事件

func _on_level_pressed(index: int) -> void:
	if index >= GameState.unlocked_levels:
		return
	level_selected.emit(index)


func _on_tier_pressed(tier: int) -> void:
	GameState.set_selected_tier(tier)
	refresh()


func _on_quit_pressed() -> void:
	quit_pressed.emit()


func _on_upgrade_pressed(key: String) -> void:
	if GameState.upgrade(key):
		refresh()


func _on_reset_pressed() -> void:
	GameState.reset_level()
	refresh()


# ------------------------------------------------------------------ 刷新

func refresh() -> void:
	var levels := LevelCatalog.all()
	for i: int in range(levels.size()):
		var level: LevelDef = levels[i]
		var unlocked := i < GameState.unlocked_levels
		var button := _level_buttons[i]
		var caption := _level_labels[i]
		if unlocked:
			button.text = "%s   %s   %d 圈" % [level.subtitle, level.display_name, level.total_laps]
			button.disabled = false
			var best_time: float = float(GameState.best_times[i])
			var best_rank: int = int(GameState.best_ranks[i])
			var record := ""
			if best_time > 0.0:
				record = "    最佳 %s" % GameState.format_time(best_time)
				if best_rank > 0:
					record += " · 第 %d 名" % best_rank
			caption.text = LEVEL_BLURBS[i] + record
		else:
			button.text = "%s   %s   %d 圈   （未解锁）" % [level.subtitle, level.display_name, level.total_laps]
			button.disabled = true
			caption.text = "先赢下前一关即可解锁"

	for tier: int in range(_tier_buttons.size()):
		var button := _tier_buttons[tier]
		var multiplier := GameState.AI_TIER_XP_COEF[tier]
		button.text = "%s ×%.2f" % [GameState.AI_TIER_NAMES[tier], multiplier]
		UiKit.set_button_selected(button, tier == GameState.selected_tier, 10.0)

	_level_label.text = "Lv.%d" % GameState.level
	_level_label.add_theme_color_override("font_color", Tuning.COLOR_ACCENT)
	if GameState.level >= GameState.LEVEL_MAX:
		_xp_bar.value = 1.0
		_xp_label.text = "已达最高等级"
	else:
		_xp_bar.value = GameState.xp_progress()
		_xp_label.text = "经验 %d / %d   ·   升级 +1 加点" % [GameState.xp, GameState.xp_to_next()]
	_best_label.text = "战绩 %d 场 / %d 胜" % [GameState.total_races, GameState.total_wins]

	_points_label.text = "可用加点 %d   ·   对手 %s ×%.2f" % [
		GameState.available_points(),
		GameState.AI_TIER_NAMES[GameState.selected_tier],
		GameState.AI_TIER_XP_COEF[GameState.selected_tier],
	]
	for key: String in _stat_value_labels.keys():
		var value_label: Label = _stat_value_labels[key]
		value_label.text = "%d/%d" % [GameState.stat_level(key), GameState.STAT_MAX_LEVEL]
		var plus: Button = _upgrade_buttons[key]
		plus.disabled = not GameState.can_upgrade(key)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back"):
		quit_pressed.emit()
		get_viewport().set_input_as_handled()


## 菜单背景：极简环形剪影（纯绘制，不依赖美术资源）。
class MenuDecor:
	extends Control

	func _draw() -> void:
		var center := size * Vector2(0.74, 0.5)
		var radius := minf(size.x, size.y) * 0.46
		var color := Color(0.15, 0.15, 0.15, 0.5)
		draw_arc(center, radius, 0.0, TAU, 128, color, 54.0, false)
		draw_arc(center, radius * 0.74, 0.0, TAU, 96, Color(0.10, 0.10, 0.10, 0.5), 10.0, false)
		for i: int in range(160):
			var angle := float(i) * 2.7
			var distance := radius * (1.05 + 0.6 * fmod(float(i) * 0.37, 1.0))
			var point := center + Vector2(cos(angle), sin(angle)) * distance
			if point.x < 0.0 or point.y < 0.0 or point.x > size.x or point.y > size.y:
				continue
			draw_circle(point, 4.0 + fmod(float(i), 3.0) * 2.0, Color(0.08, 0.08, 0.08, 0.65))