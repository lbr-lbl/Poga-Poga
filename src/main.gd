class_name Main
extends Node2D
## 应用根节点：管理 菜单 / 比赛 / 结算 三个屏幕，以及像素化后处理层。
##
## 层级顺序（从下到上）：
##   0  世界（赛道、史莱姆、镜头）
##   1  PixelLayer：把世界像素化（CanvasLayer + 全屏 shader ColorRect）
##   2  比赛 HUD（Race 自己创建的 CanvasLayer）
##   3  UI 层：主菜单 / 结算（CanvasLayer，不受像素化影响）
##
## 自动化入口（无头 / 截图，供 CI 与调参使用）：
##   godot --headless --fixed-fps 60 --path . -- --autotest --level=0
##   godot --headless --fixed-fps 60 --path . -- --autotest --level=0 --verbose
##   godot --headless --fixed-fps 60 --path . -- --autotest --pattern=mechanics
##   godot --path . -- --shots            # 依次截 menu / race / settlement 三张图
##   godot --path . -- --shot --shot-time=6 --level=0

const PIXEL_SHADER_PATH := "res://shaders/pixelate.gdshader"
const AUTOTEST_TIMEOUT := 300.0
const SHOT_PATH := "user://shots/"
## 玩法依赖的输入动作：启动时自检，缺失即报错，避免手改 InputMap 后静默失效。
const REQUIRED_INPUT_ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right",
	&"retry", &"confirm", &"back", &"ui_debug",
]

var _world_root: Node2D
var _ui_layer: CanvasLayer
var _pixel_layer: CanvasLayer
var _pixel_rect: ColorRect
var _pixel_material: ShaderMaterial

var _menu: MainMenu
var _settlement: Settlement
var _race: Race

var _autotest := false
var _autotest_level := 0
var _verbose := false
var _pattern := ""
var _autotest_elapsed := 0.0
var _log_timer := 0.0

var _shot_mode := false
var _shot_timer := 3.0
var _shot_level := 0
var _shots_mode := false
var _shots_step := 0
var _shots_timer := 0.0

var _pixelation_enabled := true

# 机制测试记录
var _mech_fused_at := -1.0
var _mech_detach_at := -1.0
var _mech_reabsorb_at := -1.0
var _mech_max_pack := 0
var _mech_best_pack_index := 99
var _mech_forced_detach := false
var _mech_probe_timer := 0.0
var _mech_teleported := false


func _ready() -> void:
	_setup_layers()
	_parse_cmdline()
	_check_input_actions()
	if _autotest or _shots_mode or _shot_mode:
		GameState.persistence_enabled = false
	if _shots_mode:
		show_menu()
		_shots_timer = 1.0
	elif _autotest:
		start_level(_autotest_level)
	elif _shot_mode:
		start_level(_shot_level)
	else:
		show_menu()


func _check_input_actions() -> void:
	for action: StringName in REQUIRED_INPUT_ACTIONS:
		if not InputMap.has_action(action):
			push_error("缺少输入动作：%s" % action)


func _setup_layers() -> void:
	_world_root = Node2D.new()
	_world_root.name = "World"
	add_child(_world_root)

	_pixel_layer = CanvasLayer.new()
	_pixel_layer.name = "PixelLayer"
	_pixel_layer.layer = 1
	add_child(_pixel_layer)

	_pixel_rect = ColorRect.new()
	_pixel_rect.name = "Pixelation"
	_pixel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(PIXEL_SHADER_PATH):
		_pixel_material = ShaderMaterial.new()
		_pixel_material.shader = load(PIXEL_SHADER_PATH)
		_pixel_rect.material = _pixel_material
	_pixel_layer.add_child(_pixel_rect)
	_pixel_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pixel_layer.visible = false

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UiLayer"
	_ui_layer.layer = 3
	add_child(_ui_layer)


func _parse_cmdline() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--autotest":
			_autotest = true
		elif argument == "--verbose":
			_verbose = true
		elif argument.begins_with("--level="):
			_autotest_level = clampi(int(argument.get_slice("=", 1)), 0, LevelCatalog.COUNT - 1)
			_shot_level = _autotest_level
		elif argument.begins_with("--pattern="):
			_pattern = argument.get_slice("=", 1)
			_autotest = true
		elif argument == "--shot":
			_shot_mode = true
		elif argument.begins_with("--shot-time="):
			_shot_timer = maxf(0.2, float(argument.get_slice("=", 1)))
		elif argument.begins_with("--tier="):
			GameState.selected_tier = clampi(int(argument.get_slice("=", 1)), 0, 2)
		elif argument == "--shots":
			_shots_mode = true


# ------------------------------------------------------------------ 屏幕切换

func show_menu() -> void:
	_clear_screens()
	_pixel_layer.visible = false
	_menu = MainMenu.new()
	_menu.name = "MainMenu"
	_menu.level_selected.connect(start_level)
	_menu.quit_pressed.connect(_on_quit_game)
	_mount_ui(_menu)


## 把全屏 UI 挂到 UI 层，并显式铺满视口。
## 说明：CanvasLayer 不会替子 Control 做尺寸同步，直接 set_anchors_preset 在
## 运行期窗口已存在时拿不到布局通知，会导致 UI 只按最小尺寸排在左上角。
func _mount_ui(node: Control) -> void:
	_ui_layer.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func start_level(index: int) -> void:
	_clear_screens()
	_pixel_layer.visible = _pixelation_enabled
	_race = Race.new()
	_race.name = "Race"
	_race.level_index = clampi(index, 0, LevelCatalog.COUNT - 1)
	_race.ai_tier = GameState.selected_tier
	_race.autopilot = _autotest or _shot_mode or _shots_mode
	_race.race_finished.connect(_on_race_finished)
	_race.quit_requested.connect(show_menu)
	_race.retry_requested.connect(_on_retry_pressed)
	_world_root.add_child(_race)


func _clear_screens() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _settlement != null:
		_settlement.queue_free()
		_settlement = null
	if _race != null:
		_race.queue_free()
		_race = null


# ------------------------------------------------------------------ 比赛回调

func _on_race_finished(result: Dictionary) -> void:
	var reward := GameState.register_result(
		int(result.get("level_index", 0)),
		int(result.get("rank", 6)),
		float(result.get("total_time", 0.0)),
		bool(result.get("won", false)),
		int(result.get("ai_tier", 1))
	)
	result["xp"] = int(reward.get("xp", 0))
	result["levels_gained"] = int(reward.get("levels_gained", 0))
	result["level_before"] = int(reward.get("level_before", 0))
	result["level_after"] = int(reward.get("level_after", 0))
	GameState.last_result = result

	if _autotest:
		_report_autotest(result)
		get_tree().quit(0)
		return

	_settlement = Settlement.new()
	_settlement.name = "Settlement"
	_settlement.setup(result)
	_settlement.retry_pressed.connect(_on_retry_pressed)
	_settlement.next_pressed.connect(_on_next_pressed.bind(int(result.get("level_index", 0))))
	_settlement.menu_pressed.connect(show_menu)
	_mount_ui(_settlement)
	if _race != null and _race.hud != null:
		_race.hud.visible = false

	if _shots_mode and _shots_step == 1 and _settlement != null:
		_shots_step = 2
		_shots_timer = 1.2


func _on_retry_pressed() -> void:
	if _race != null:
		start_level(_race.level_index)
	else:
		start_level(0)


func _on_next_pressed(level_index: int) -> void:
	start_level(mini(level_index + 1, LevelCatalog.COUNT - 1))


func _on_quit_game() -> void:
	get_tree().quit(0)


# ------------------------------------------------------------------ 自动测试 / 机制验证 / 截图

func _process(delta: float) -> void:
	if _shots_mode:
		_run_shots(delta)
		return
	if _shot_mode:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_shot_mode = false
			_capture_screenshot("shot")
			get_tree().quit(0)
		return
	if not _autotest:
		return

	_autotest_elapsed += delta
	if _pattern != "":
		_run_mechanics_pattern()
		_log_timer += delta
		if _log_timer >= 1.0:
			_log_timer = 0.0
			_log_state()
		if _autotest_elapsed > 30.0 or (_race != null and _race.state == Race.State.FINISHED):
			_report_mechanics()
			get_tree().quit(0)
		return

	_log_timer += delta
	if _verbose and _log_timer >= 1.0:
		_log_timer = 0.0
		_log_state()
	if _autotest_elapsed > AUTOTEST_TIMEOUT:
		printerr("AUTOTEST_TIMEOUT")
		get_tree().quit(1)


func _run_mechanics_pattern() -> void:
	if _race == null or _race.player == null:
		return
	var race_time := _race.race_time
	var player := _race.player
	if _pattern != "mechanics":
		return
	_race.force_steer = 0.0
	_race.force_throttle_override = true
	if race_time >= 2.0 and race_time < 3.6:
		# 形态测试：全油门 -> 眼睛靠近
		_race.force_throttle = 1.0
	elif race_time >= 3.6 and race_time < 4.2:
		# 形态测试：刹车 -> 眼睛拉远
		_race.force_throttle = -1.0
	elif race_time >= 4.2 and race_time < 6.4:
		# 主动横向拉扯：验证“转向可主动脱离融合团”
		_race.force_steer = 0.95
		_race.force_throttle = 1.0
		_mech_forced_detach = true
	elif race_time >= 6.4 and race_time < 12.0:
		# 松开方向、收油滑行，让后面的融合团追上来，验证“可以重新融合”
		_race.force_throttle = 0.05
	else:
		_race.force_throttle_override = false

	# 12s 后如果还没重新融合，用测试仪器把玩家放回对手身边（只验证吸收逻辑，不属于正式玩法）
	if race_time >= 12.0 and not _mech_teleported and _mech_detach_at >= 0.0 and player.pack == null:
		_mech_teleported = _race.debug_attract_player_to_nearest()

	var pack_size: int = (player.pack as FusionPack).size() if player.pack != null else 0
	if pack_size > 0 and _mech_fused_at < 0.0:
		_mech_fused_at = race_time
	if pack_size > _mech_max_pack:
		_mech_max_pack = pack_size
	if player.pack != null:
		_mech_best_pack_index = mini(_mech_best_pack_index, player.pack_index)
	if _mech_forced_detach and _mech_fused_at >= 0.0 and pack_size == 0 and _mech_detach_at < 0.0 and race_time > 4.0:
		_mech_detach_at = race_time
	if _mech_detach_at >= 0.0 and pack_size > 0 and _mech_reabsorb_at < 0.0:
		_mech_reabsorb_at = race_time

	# 调试探针：记录强制转向期间与槽位的横向偏差
	_mech_probe_timer += get_process_delta_time()
	if race_time >= 3.4 and race_time < 6.6 and _mech_probe_timer >= 0.2:
		_mech_probe_timer = 0.0
		var lateral := 0.0
		var pack_dir := Vector2.RIGHT
		if player.pack != null:
			pack_dir = (player.pack as FusionPack).direction
			var slot: Vector2 = (player.pack as FusionPack).slot_for(player)
			lateral = absf((slot - player.position).dot(pack_dir.orthogonal()))
		print("  MECH t=%.2f steer=%.2f pack=%d lat=%.1f v=%.0f" % [
			race_time, player.steer_in, pack_size, lateral, player.current_speed(),
		])


func _report_mechanics() -> void:
	print("MECHANICS fused_at=%.2f detach_at=%.2f reabsorb_at=%.2f max_pack=%d best_pack_index=%d eye_form=%.2f..%.2f" % [
		_mech_fused_at, _mech_detach_at, _mech_reabsorb_at, _mech_max_pack, _mech_best_pack_index,
		_race.stats_eye_form_min if _race != null else 1.0,
		_race.stats_eye_form_max if _race != null else 1.0,
	])


func _log_state() -> void:
	if _race == null or _race.player == null:
		return
	var player := _race.player
	print("t=%.1f rank=%d lap=%d s=%.0f packs=%d player_pack=%d stamina=%.2f cap=%.2f speed=%.0f throttle=%.2f" % [
		_race.race_time,
		_race.player_rank(),
		player.lap,
		player.progress,
		_race.packs.size(),
		(player.pack as FusionPack).size() if player.pack != null else 0,
		player.stamina,
		player.stamina_cap,
		player.current_speed(),
		player.throttle_in,
	])
	if _verbose:
		var driver: AiDriver = _race.drivers.get(player.id)
		var limit := 0.0
		if driver != null:
			limit = driver.get_corner_limit()
		print("  P v=%.0f thr=%.2f steer=%.2f st=%.2f cap=%.2f lat=%.0f limit=%.0f pack=%d off=%s" % [
			player.current_speed(),
			player.throttle_in,
			player.steer_in,
			player.stamina,
			player.stamina_cap,
			player.center_lateral,
			limit,
			(player.pack as FusionPack).size() if player.pack != null else 0,
			"Y" if player.off_road else "n",
		])
		print("  " + _race.debug_dump())


func _report_autotest(result: Dictionary) -> void:
	print("AUTOTEST_RESULT level=%d tier=%d won=%s rank=%d time=%.2f laps=%s xp=%d level_after=%d" % [
		int(result.get("level_index", 0)),
		int(result.get("ai_tier", 1)),
		str(bool(result.get("won", false))),
		int(result.get("rank", 0)),
		float(result.get("total_time", 0.0)),
		str(result.get("lap_times", [])),
		int(result.get("xp", 0)),
		int(result.get("level_after", 0)),
	])
	var ranking: Array = result.get("ranking", [])
	var parts: PackedStringArray = PackedStringArray()
	for entry: Dictionary in ranking:
		parts.append("%s%s(%.0f|%.0f)" % [
			str(entry.get("name", "?")),
			"*" if bool(entry.get("is_player", false)) else "",
			float(entry.get("progress", 0.0)),
			float(entry.get("avg_speed", 0.0)),
		])
	print("AUTOTEST_RANKING " + ",".join(parts))
	var absorb := 0
	var detach := 0
	var offroad_ratio := 0.0
	var pack_count := 0
	var eye_coll := 0
	var leaf_coll := 0
	var debris_coll := 0
	if _race != null:
		absorb = _race.stats_absorb
		detach = _race.stats_detach
		offroad_ratio = float(_race.stats_offroad_frames) / maxf(float(_race.stats_offroad_total * maxi(_race.racers.size(), 1)), 1.0)
		pack_count = _race.packs.size()
		eye_coll = _race.stats_eye_collisions
		leaf_coll = _race.stats_leaf_collisions
		debris_coll = _race.stats_debris_collisions
	print("AUTOTEST_STATS absorb=%d detach=%d eye_coll=%d leaf_coll=%d debris_coll=%d offroad_ratio=%.3f packs=%d" % [
		absorb, detach, eye_coll, leaf_coll, debris_coll, offroad_ratio, pack_count,
	])
	if _race != null:
		print("AUTOTEST_STAMINA min=%.2f max=%.2f cap_min=%.2f eye_form=%.2f..%.2f level=%d xp=%d/%d tier=%d" % [
			_race.stats_stamina_min, _race.stats_stamina_max, _race.stats_stamina_cap_min,
			_race.stats_eye_form_min, _race.stats_eye_form_max,
			GameState.level, GameState.xp, GameState.xp_to_next(), GameState.selected_tier,
		])


func _run_shots(delta: float) -> void:
	match _shots_step:
		0:
			_shots_timer -= delta
			if _shots_timer <= 0.0:
				_capture_screenshot("01_menu")
				_shots_step = 1
				start_level(0)
				_shots_timer = 9.0
		1:
			_shots_timer -= delta
			if _shots_timer <= 0.0:
				_capture_screenshot("02_race")
				_shots_step = 2
				_shots_timer = 1.2
		2:
			if _settlement == null:
				return
			_shots_timer -= delta
			if _shots_timer <= 0.0:
				_capture_screenshot("03_settlement")
				_shots_step = 3
				_shots_timer = 0.3
		3:
			_shots_timer -= delta
			if _shots_timer <= 0.0:
				get_tree().quit(0)


func _capture_screenshot(label: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_PATH))
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_PATH + label + ".png")
	var err := image.save_png(path)
	print("SCREENSHOT %s err=%d size=%dx%d" % [path, err, image.get_width(), image.get_height()])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_debug"):
		_pixelation_enabled = not _pixelation_enabled
		if _race != null:
			_pixel_layer.visible = _pixelation_enabled