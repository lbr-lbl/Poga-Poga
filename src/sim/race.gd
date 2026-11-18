class_name Race
extends Node2D
## 单局比赛：生成赛道/单位/相机/HUD，驱动物理与融合，判定记圈与终点。
##
## 每物理帧的固定顺序（顺序变化会改变手感，修改前先跑 tools/verify.ps1 对比）：
## 1. 采集输入（玩家 / AI / 自动驾驶）
## 2. Racer.simulate：转向 -> 驱动 -> 融合弹力 -> 越野阻尼 -> 位移 -> 耐力
## 3. 碰撞：**眼睛相撞**、凋落物、路旁叶片（躯体不碰撞，躯体是融合的）
## 4. FusionPack.update：方向、排序、槽位、增益、散团
## 5. 清理散团、自动吸附新成员
## 6. 更新赛道进度/记圈、判定终点
##
## 渲染：躯体由 SlimeBlobLayer（metaball）统一绘制，Racer 只画眼睛。

signal race_finished(result: Dictionary)
signal quit_requested()
signal retry_requested()
signal race_started()

enum State { COUNTDOWN, RACING, FINISHED }

const PLAYER_BLOB_TINT := 1.0
const AI_BLOB_TINTS: Array[float] = [0.18, 0.32, 0.24, 0.42, 0.28]

var level_index: int = 0
## AI 难度档位：0 简单 / 1 普通 / 2 困难（影响 AI 属性、操作水平与结算经验）
var ai_tier: int = 1
var level: LevelDef
var track: RaceTrack
var racers: Array[Racer] = []
var packs: Array[FusionPack] = []
var drivers: Dictionary = {}
var player: Racer
var rng := RandomNumberGenerator.new()

var state: State = State.COUNTDOWN
var countdown: float = Tuning.COUNTDOWN_TIME
var race_time: float = 0.0
var finish_order: Array[Racer] = []

## 自动驾驶开关（无头平衡测试用：玩家由 AI 接管）。
var autopilot: bool = false
## 玩家是否可操作（结算/暂停时禁用）。
var input_enabled: bool = true
## 无头机制测试用的强制输入（Main 按脚本设置）
var force_steer: float = 0.0
var force_throttle: float = 0.0
var force_throttle_override: bool = false

var camera: Camera2D
var hud: CanvasLayer
var blob_layer: SlimeBlobLayer

## 调参用统计（无头测试输出，便于验证机制是否真的发生）
var stats_absorb := 0
var stats_detach := 0
var stats_eye_collisions := 0
var stats_leaf_collisions := 0
var stats_debris_collisions := 0
var stats_offroad_frames := 0
var stats_offroad_total := 0
## 玩家耐力波动范围（自动测试用来确认耐力系统真的在动）
var stats_stamina_min := 1.0
var stats_stamina_max := 1.0
var stats_stamina_cap_min := 1.0
## 玩家眼距形态倍率范围（<1 加速挤近，>1 刹车拉开）
var stats_eye_form_min := 1.0
var stats_eye_form_max := 1.0

var _finish_timer: float = 0.0
var _result_emitted: bool = false
var _shake: float = 0.0
var _blob_time: float = 0.0
var _touch_active: bool = false
var _touch_origin: Vector2 = Vector2.ZERO
var _touch_steer: float = 0.0
var _touch_brake: bool = false
var _touch_ids: Dictionary = {}


func _ready() -> void:
	level = LevelCatalog.get_level(level_index)
	track = RaceTrack.new(level)
	rng.seed = 7000 + level_index
	add_child(TrackView.new(track))
	blob_layer = SlimeBlobLayer.new()
	blob_layer.name = "SlimeBlob"
	add_child(blob_layer)
	if OS.get_cmdline_user_args().has("--verbose"):
		var max_curv := 0.0
		for value: float in track.curvature:
			max_curv = maxf(max_curv, value)
		print("RACE_NEW level=%s length=%.1f width=%.1f max_curv=%.5f min_radius=%.0f leaves=%d" % [
			level.id, track.length, track.width, max_curv, 1.0 / maxf(max_curv, 0.00001), track.leaves.size(),
		])
	_spawn_racers()
	if autopilot and not drivers.has(player.id):
		drivers[player.id] = AiDriver.new(player, track, level, 999, ai_tier)
	_setup_camera()
	hud = Hud.new()
	hud.setup(self)
	add_child(hud)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.position = player.position
	camera.rotation = 0.0
	camera.zoom = Vector2.ONE * Tuning.CAMERA_BASE_ZOOM
	camera.ignore_rotation = true
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= delta
			_simulate_step(delta, false)
			if countdown <= 0.0:
				countdown = 0.0
				state = State.RACING
				race_started.emit()
		State.RACING:
			race_time += delta
			_simulate_step(delta, true)
			_update_progress(delta)
			_check_finish()
		State.FINISHED:
			_finish_timer -= delta
			_simulate_step(delta, false)
			if _finish_timer <= 0.0 and not _result_emitted:
				_result_emitted = true
				race_finished.emit(_build_result())


func _process(delta: float) -> void:
	_update_camera(delta)
	_blob_time += delta
	if blob_layer != null and is_instance_valid(blob_layer):
		blob_layer.follow_view(get_canvas_transform(), get_viewport().get_visible_rect().size)
		blob_layer.update_racers(racers, _blob_time)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)


# ------------------------------------------------------------------ 生成

func _spawn_racers() -> void:
	var total := level.ai_count + 1
	var columns := 2
	var rows := int(ceil(float(total) / float(columns)))
	var player_slot := mini(2, total - 1)
	var player_stats: Dictionary = GameState.player_stats()

	var tier := clampi(ai_tier, 0, 2)
	var tier_speed: float = Tuning.AI_TIER_SPEED[tier]
	var tier_stats: float = Tuning.AI_TIER_STATS[tier]
	var used_slots: int = 0
	for slot: int in range(total):
		var row := slot / columns
		var column := slot % columns
		var grid := track.start_slot(rows - 1 - row, column, columns)
		var is_player := slot == player_slot
		var stats: Dictionary
		var speed_scale := level.ai_speed_scale * tier_speed
		if is_player:
			stats = player_stats
			speed_scale = 1.0
		else:
			used_slots += 1
			stats = {
				"stamina": 5.0 + tier_stats + rng.randf_range(-0.3, 0.5),
				"speed": 5.0 + tier_stats + rng.randf_range(-0.35, 0.4),
				"stability": 5.0 + tier_stats + rng.randf_range(-0.4, 0.4),
			}
		var racer := Racer.new()
		racer.name = "Player" if is_player else "AI%d" % used_slots
		racer.setup(used_slots if not is_player else 0, is_player, stats, speed_scale)
		racer.race = self
		racer.z_index = 20 if is_player else 10
		_apply_visuals(racer, is_player)
		add_child(racer)
		racer.place_at(grid["position"], grid["angle"], track)
		racers.append(racer)
		if is_player:
			player = racer
		else:
			var driver := AiDriver.new(racer, track, level, 100 + slot + level_index * 31)
			drivers[racer.id] = driver
			racer.is_ai = true


func _apply_visuals(racer: Racer, is_player: bool) -> void:
	racer.blob_radius = Tuning.SLIME_RADIUS
	racer.blob_phase = rng.randf_range(0.0, TAU)
	racer.eye_radius_scale = 1.15 if is_player else rng.randf_range(0.82, 1.02)
	racer.eye_spacing_scale = 1.0 if is_player else rng.randf_range(0.85, 1.12)
	if is_player:
		racer.blob_tint = PLAYER_BLOB_TINT
	else:
		racer.blob_tint = AI_BLOB_TINTS[racer.id % AI_BLOB_TINTS.size()]


# ------------------------------------------------------------------ 模拟

func _simulate_step(delta: float, allow_input: bool) -> void:
	# 1. 输入
	for racer: Racer in racers:
		var input := Vector2.ZERO
		if allow_input and not racer.finished:
			if racer.is_player:
				input = _read_player_input(delta)
			elif drivers.has(racer.id):
				input = (drivers[racer.id] as AiDriver).update(delta, racers)
		racer.simulate(delta, input.x, input.y)

	# 2. 碰撞与障碍
	_resolve_eye_collisions()
	_resolve_debris()
	_resolve_leaves()

	# 3. 融合团更新
	for pack_entry: Variant in packs.duplicate():
		var pack: FusionPack = pack_entry
		var detached := pack.update(delta)
		for racer: Racer in detached:
			racer.fusion_cooldown = Tuning.ABSORB_COOLDOWN
			racer.stability_dip = maxf(racer.stability_dip, 0.2)
			stats_detach += 1
		if not pack.is_valid():
			pack.dissolve()
			packs.erase(pack)

	# 4. 自动吸附（躯体贴近就融合）
	_try_absorb()


func _read_player_input(delta: float) -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	if autopilot and drivers.has(player.id):
		var ai_input: Vector2 = (drivers[player.id] as AiDriver).update(delta, racers)
		if force_throttle_override:
			ai_input.x = clampf(force_throttle, -1.0, 1.0)
		if not is_zero_approx(force_steer):
			ai_input.y = clampf(force_steer, -1.0, 1.0)
		return ai_input
	var throttle := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	if _touch_active:
		if _touch_brake:
			throttle = -1.0
		else:
			throttle = maxf(throttle, 1.0)
		steer = clampf(steer + _touch_steer, -1.0, 1.0)
	return Vector2(throttle, steer)


func _try_absorb() -> void:
	for racer: Racer in racers:
		if racer.pack != null or racer.finished:
			continue
		if racer.fusion_cooldown > 0.0:
			continue
		if racer.stamina < Tuning.ABSORB_MIN_STAMINA:
			continue
		var absorb_range := Tuning.ABSORB_RANGE * (0.65 + 0.35 * racer.stamina)
		var target: Racer = null
		var best_distance := absorb_range
		for other: Racer in racers:
			if other == racer or other.finished:
				continue
			var distance := racer.position.distance_to(other.position)
			if distance > best_distance:
				continue
			if absf(racer.current_speed() - other.current_speed()) > Tuning.ABSORB_SPEED_DIFF:
				continue
			if other.pack != null and (other.pack as FusionPack).size() >= Tuning.PACK_MAX_MEMBERS:
				continue
			best_distance = distance
			target = other
		if target == null:
			continue
		_absorb_into(racer, target)


func _absorb_into(racer: Racer, target: Racer) -> void:
	var pack = target.pack
	if pack == null:
		pack = FusionPack.new(target)
		packs.append(pack)
	if (pack as FusionPack).join(racer):
		racer.fusion_cooldown = 0.0
		stats_absorb += 1


## 真正的碰撞：眼睛相撞。
## 躯体是融合的，只有眼睛是“硬”的：同团内撞眼 -> 减速 + 稳定低谷 + 约束松弛（易散团）；
## 不同个体撞眼 -> 更重，并且双方脱离当前团。
func _resolve_eye_collisions() -> void:
	var count := racers.size()
	for i: int in range(count):
		var a: Racer = racers[i]
		if a.finished or a.eye_collision_cooldown > 0.0:
			continue
		for j: int in range(i + 1, count):
			var b: Racer = racers[j]
			if b.finished or b.eye_collision_cooldown > 0.0:
				continue
			var distance := a.eye_distance_to(b)
			if distance > Tuning.EYE_COLLISION_DIST:
				continue
			stats_eye_collisions += 1
			a.eye_collision_cooldown = Tuning.EYE_COLLISION_COOLDOWN
			b.eye_collision_cooldown = Tuning.EYE_COLLISION_COOLDOWN
			var normal := b.position - a.position
			if normal.length_squared() < 0.0001:
				normal = Vector2.RIGHT
			else:
				normal = normal.normalized()
			var same_pack: bool = a.pack != null and a.pack == b.pack
			if same_pack:
				a.take_hit(Tuning.COLLISION_SPEED_LOSS * 0.5, Tuning.COLLISION_STABILITY_DIP * 0.7,
					-normal * Tuning.COLLISION_KNOCKBACK * 0.20)
				b.take_hit(Tuning.COLLISION_SPEED_LOSS * 0.5, Tuning.COLLISION_STABILITY_DIP * 0.7,
					normal * Tuning.COLLISION_KNOCKBACK * 0.20)
				(a.pack as FusionPack).add_shock(Tuning.EYE_SHOCK)
				if distance < Tuning.EYE_COLLISION_DIST * 0.35:
					_detach(a, 0.35)
					_detach(b, 0.35)
			else:
				a.take_hit(Tuning.COLLISION_SPEED_LOSS, Tuning.COLLISION_STABILITY_DIP,
					-normal * Tuning.COLLISION_KNOCKBACK * 0.45)
				b.take_hit(Tuning.COLLISION_SPEED_LOSS, Tuning.COLLISION_STABILITY_DIP,
					normal * Tuning.COLLISION_KNOCKBACK * 0.45)
				_detach(a, 0.5)
				_detach(b, 0.5)
			if a.is_player or b.is_player:
				_shake = maxf(_shake, 0.7)


## 路旁叶片碰撞：贴边行驶会撞进树叶里。
func _resolve_leaves() -> void:
	for racer: Racer in racers:
		if racer.finished or not racer.can_hit_leaf():
			continue
		var indices := track.leaf_indices_near(racer.s_pos)
		for leaf_index: int in indices:
			var leaf: Dictionary = track.leaves[leaf_index]
			var radius: float = float(leaf["radius"]) + Tuning.SLIME_RADIUS * 0.70
			var leaf_position: Vector2 = leaf["position"]
			if racer.position.distance_squared_to(leaf_position) > radius * radius:
				continue
			racer.mark_leaf_hit()
			var push := racer.position - leaf_position
			if racer.off_road:
				# 已经冲到叶子外侧：往赛道中心推，别把人越推越远
				push = track.point_at(racer.s_pos) - racer.position
			if push.length_squared() < 0.01:
				push = track.normal_at(racer.s_pos)
			racer.take_hit(Tuning.LEAF_COLLISION_SPEED_LOSS, Tuning.LEAF_COLLISION_DIP, push.normalized() * 26.0)
			racer.stamina = maxf(0.0, racer.stamina - Tuning.LEAF_COLLISION_STAMINA)
			_detach(racer, 0.5)
			stats_leaf_collisions += 1
			if racer.is_player:
				_shake = maxf(_shake, 0.8)
			break


func _resolve_debris() -> void:
	if track.debris.is_empty():
		return
	for index: int in range(track.debris.size()):
		var item: Dictionary = track.debris[index]
		var radius: float = float(item["radius"]) + Tuning.SLIME_RADIUS * 0.70
		var item_position: Vector2 = item["position"]
		for racer: Racer in racers:
			if racer.finished or not racer.can_hit_leaf():
				continue
			if racer.position.distance_squared_to(item_position) > radius * radius:
				continue
			racer.mark_leaf_hit()
			var push: Vector2 = racer.position - item_position
			if push.length_squared() < 0.01:
				push = Vector2.RIGHT
			racer.take_hit(Tuning.LEAF_COLLISION_SPEED_LOSS, Tuning.LEAF_COLLISION_DIP, push.normalized() * 30.0)
			racer.stamina = maxf(0.0, racer.stamina - Tuning.LEAF_COLLISION_STAMINA)
			_detach(racer, 0.5)
			stats_debris_collisions += 1
			if racer.is_player:
				_shake = maxf(_shake, 0.8)


func _detach(racer: Racer, cooldown: float = Tuning.ABSORB_COOLDOWN) -> void:
	if racer.pack == null:
		return
	var pack = racer.pack
	(pack as FusionPack).leave(racer)
	racer.fusion_cooldown = maxf(racer.fusion_cooldown, cooldown)
	stats_detach += 1
	if not (pack as FusionPack).is_valid():
		(pack as FusionPack).dissolve()
		packs.erase(pack)


# ------------------------------------------------------------------ 进度 / 终点

func _update_progress(delta: float) -> void:
	for racer: Racer in racers:
		racer.update_progress(delta)
		if racer == player:
			stats_stamina_min = minf(stats_stamina_min, racer.stamina)
			stats_stamina_max = maxf(stats_stamina_max, racer.stamina)
			stats_stamina_cap_min = minf(stats_stamina_cap_min, racer.stamina_cap)
			stats_eye_form_min = minf(stats_eye_form_min, racer.eye_form())
			stats_eye_form_max = maxf(stats_eye_form_max, racer.eye_form())
		if racer.off_road:
			stats_offroad_frames += 1
			racer.stamina = maxf(0.0, racer.stamina - Tuning.OFFROAD_EXTRA_DRAIN * 0.35 * delta)
	stats_offroad_total += 1


func _check_finish() -> void:
	var newly: Array[Racer] = []
	for racer: Racer in racers:
		if racer.finished and racer.finish_order == 0:
			newly.append(racer)
	if newly.is_empty():
		return
	newly.sort_custom(func(a: Racer, b: Racer) -> bool:
		if not is_equal_approx(a.finish_time, b.finish_time):
			return a.finish_time < b.finish_time
		return a.s_pos > b.s_pos
	)
	for racer: Racer in newly:
		racer.finish_order = finish_order.size() + 1
		finish_order.append(racer)
	_end_race(newly[0].is_player)


func _end_race(player_first: bool) -> void:
	if state == State.FINISHED:
		return
	state = State.FINISHED
	_finish_timer = Tuning.FINISH_HOLD_TIME
	_shake = maxf(_shake, 0.5)
	input_enabled = false


func _build_result() -> Dictionary:
	var standings := racers.duplicate()
	standings.sort_custom(func(a: Racer, b: Racer) -> bool: return a.rank_progress() > b.rank_progress())
	var player_rank := 1
	var ranking: Array[Dictionary] = []
	for i: int in range(standings.size()):
		var racer: Racer = standings[i]
		if racer == player:
			player_rank = i + 1
		ranking.append({
			"name": racer.display_name,
			"is_player": racer.is_player,
			"rank": i + 1,
			"finished": racer.finished,
			"progress": racer.progress,
			"avg_speed": racer.progress / maxf(race_time, 0.001),
		})
	var total_time := race_time
	if player.finished:
		total_time = player.finish_time
	return {
		"level_index": level_index,
		"level_id": level.id,
		"level_name": level.display_name,
		"level_subtitle": level.subtitle,
		"ai_tier": ai_tier,
		"total_laps": level.total_laps,
		"won": player.finish_order == 1,
		"player_finished": player.finished,
		"rank": player_rank,
		"racer_count": racers.size(),
		"total_time": total_time,
		"lap_times": player.lap_times.duplicate(),
		"ranking": ranking,
		"points": 0,
	}


# ------------------------------------------------------------------ 相机 / 输入

func _update_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	var speed := player.current_speed()
	var ratio := clampf(speed / Tuning.BASE_MAX_SPEED, 0.0, 1.25)
	var target_zoom := lerpf(Tuning.CAMERA_BASE_ZOOM, Tuning.CAMERA_FAST_ZOOM, clampf(ratio, 0.0, 1.0))
	if player.pack != null:
		var pack_size: int = (player.pack as FusionPack).size()
		target_zoom *= 1.0 - Tuning.CAMERA_PACK_ZOOM_STEP * float(maxi(0, pack_size - 1))
	var zoom_lerp := 1.0 - exp(-Tuning.CAMERA_ZOOM_LERP * delta)
	camera.zoom = camera.zoom.lerp(Vector2.ONE * maxf(target_zoom, 0.70), zoom_lerp)
	var target_position := player.position + player.velocity * Tuning.CAMERA_SPEED_LOOKAHEAD
	var follow_lerp := 1.0 - exp(-Tuning.CAMERA_FOLLOW_LERP * delta)
	camera.position = camera.position.lerp(target_position, follow_lerp)
	if _shake > 0.0:
		camera.offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * _shake * 7.0
	else:
		camera.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back") and state != State.FINISHED:
		quit_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("retry"):
		retry_requested.emit()
		get_viewport().set_input_as_handled()
	elif state == State.FINISHED and event.is_action_pressed("confirm"):
		retry_requested.emit()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# 触屏原型：按住加速，左右拖动转向，双指按下刹车（详见 README）
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_ids[touch.index] = true
			if _touch_ids.size() == 1:
				_touch_origin = touch.position
				_touch_steer = 0.0
			if _touch_ids.size() >= 2:
				_touch_brake = true
			_touch_active = true
		else:
			_touch_ids.erase(touch.index)
			if _touch_ids.is_empty():
				_touch_active = false
				_touch_steer = 0.0
				_touch_brake = false
			else:
				_touch_brake = _touch_ids.size() >= 2
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_ids.size() == 1:
			var offset := drag.position.x - _touch_origin.x
			_touch_steer = clampf(offset / 110.0, -1.0, 1.0)


# ------------------------------------------------------------------ 供 UI / 测试查询

func player_rank() -> int:
	if player == null:
		return 1
	var my_progress := player.rank_progress()
	var rank := 1
	for other: Racer in racers:
		if other == player:
			continue
		if other.rank_progress() > my_progress:
			rank += 1
	return rank


func current_lap() -> int:
	return mini(player.lap + 1, level.total_laps)


func is_counting_down() -> bool:
	return state == State.COUNTDOWN


## 仅测试用：把玩家放到最近的对手身后，验证“散团后仍能重新自动吸附”。
func debug_attract_player_to_nearest() -> bool:
	if player == null:
		return false
	var best: Racer = null
	var best_distance := INF
	for other: Racer in racers:
		if other == player:
			continue
		var distance := player.position.distance_to(other.position)
		if distance < best_distance:
			best_distance = distance
			best = other
	if best == null:
		return false
	player.position = best.position - Vector2.from_angle(best.angle) * (Tuning.ABSORB_RANGE * 0.6)
	player.velocity = best.velocity
	player.fusion_cooldown = 0.0
	player.stamina = maxf(player.stamina, Tuning.ABSORB_MIN_STAMINA + 0.05)
	return true


func debug_dump() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for racer: Racer in racers:
		parts.append("%s[s=%.0f v=%.0f st=%.2f off=%s d=%.0f pack=%d/%d]" % [
			racer.display_name,
			racer.progress,
			racer.current_speed(),
			racer.stamina,
			"Y" if racer.off_road else "n",
			racer.center_dist,
			racer.pack_index,
			(racer.pack as FusionPack).size() if racer.pack != null else 0,
		])
	return " ".join(parts)