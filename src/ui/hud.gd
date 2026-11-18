class_name Hud
extends CanvasLayer
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
var _stamina_label: Label


class StaminaBar:
	extends Control
	var stamina: float = 1.0
	var cap: float = 1.0
	var pulse: float = 0.0

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Tuning.COLOR_BAR_BG)
		# 耐力上限阴影（本局临时上限）
		var cap_width := rect.size.x * clampf(cap, 0.0, 1.0)
		draw_rect(Rect2(0.0, 0.0, cap_width, rect.size.y), Tuning.COLOR_BAR_CAP)
		# 当前耐力：低于 30% 时闪烁，强调资源见底
		var fill_color := Tuning.COLOR_BAR_FILL
		if stamina <= 0.30:
			fill_color = Tuning.COLOR_BAR_FILL.lerp(Color(0.25, 0.25, 0.25, 1.0), 0.5 + 0.5 * sin(pulse * 12.0))
		var fill_width := rect.size.x * clampf(stamina, 0.0, 1.0)
		draw_rect(Rect2(0.0, 0.0, fill_width, rect.size.y), fill_color)
		# 上限阴影描边：让“上限下降”也能被看见
		draw_line(Vector2(cap_width, 0.0), Vector2(cap_width, rect.size.y), Color(0.02, 0.02, 0.02, 0.8), 3.0)
		draw_rect(rect, Color(0.02, 0.02, 0.02, 0.98), false, 2.0)
		for i: int in range(1, 4):
			var x := rect.size.x * float(i) / 4.0
			draw_line(Vector2(x, 0.0), Vector2(x, rect.size.y), Color(0.0, 0.0, 0.0, 0.30), 1.0)
		queue_redraw()


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
	_bar.position = Vector2(-220.0, -56.0)
	_bar.size = Vector2(440.0, 22.0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar)

	_stamina_label = UiKit.label("耐力 100%", 20, Tuning.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_stamina_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina_label.position = Vector2(-220.0, -84.0)
	_stamina_label.size = Vector2(440.0, 26.0)
	root.add_child(_stamina_label)


func _process(_delta: float) -> void:
	if race == null or race.player == null:
		return
	var player := race.player
	_rank_label.text = "排名 %d/%d" % [race.player_rank(), race.racers.size()]
	_lap_label.text = "圈 %d/%d" % [race.current_lap(), race.level.total_laps]
	_time_label.text = GameState.format_time(race.race_time)
	_bar.stamina = player.stamina
	_bar.cap = player.stamina_cap
	_bar.pulse = race.race_time
	_stamina_label.text = "耐力 %d%%" % int(round(player.stamina * 100.0))
	if player.stamina <= 0.30:
		_stamina_label.add_theme_color_override("font_color", Tuning.COLOR_ACCENT)
	else:
		_stamina_label.add_theme_color_override("font_color", Tuning.COLOR_TEXT_DIM)
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