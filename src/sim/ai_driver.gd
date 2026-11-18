class_name AiDriver
extends RefCounted
## AI 车手：找团、跟车、领骑轮换（不可视耐心条）、弯道刹车、耐力管理、终点冲刺、简单避障。
##
## 只产出 throttle/steer 两个量，与玩家输入走同一套运动学。
## 耐心条规则：领骑下降、跟车恢复，低于 0 时减速侧移让位，恢复后重新领骑。

var racer: Racer
var track: RaceTrack
var level: LevelDef
var rng: RandomNumberGenerator

var patience: float = 1.0
var give_way_timer: float = 0.0
var recovering_stamina: bool = false
var sprinting: bool = false
var mistake_timer: float = 0.0
var mistake_roll: float = 1.0
var last_corner_limit: float = 0.0
var _way_side: float = 1.0
var _stuck_timer: float = 0.0
var _obstacle_ahead: bool = false

## 由难度档位换算出的行为参数（0 简单 / 1 普通 / 2 困难）
var mistake_rate: float = 0.1
var brake_skill: float = 0.5
var patience_scale: float = 1.0
var fuse_bias: float = 1.0


func _init(p_racer: Racer, p_track: RaceTrack, p_level: LevelDef, p_seed: int, p_tier: int = 1) -> void:
	racer = p_racer
	track = p_track
	level = p_level
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	patience = rng.randf_range(0.55, 1.0) if p_tier >= 2 else rng.randf_range(0.45, 1.0)
	_way_side = -1.0 if rng.randf() < 0.5 else 1.0
	var tier := clampi(p_tier, 0, 2)
	mistake_rate = clampf(p_level.ai_mistake_rate * Tuning.AI_TIER_MISTAKE[tier], 0.0, 0.6)
	brake_skill = clampf(p_level.ai_brake_skill * Tuning.AI_TIER_BRAKE[tier], 0.1, 1.0)
	patience_scale = p_level.ai_patience_scale * Tuning.AI_TIER_PATIENCE[tier]
	fuse_bias = p_level.ai_fuse_bias * Tuning.AI_TIER_FUSE[tier]


## 调试用：最近一次弯道限速
func get_corner_limit() -> float:
	return last_corner_limit


## 返回 Vector2(throttle, steer)，throttle ∈ [-1,1]。
func update(delta: float, racers: Array[Racer]) -> Vector2:
	if racer.finished:
		return Vector2(0.0, 0.0)

	var speed := racer.current_speed()
	var steer := _steer_toward_track(speed)
	steer = _seek_pack(steer, racers)
	steer = _give_way_steer(steer)
	# 避障放在最后：优先级高于跟团/让位，否则团里会一路碾过障碍
	steer = _avoid_debris(steer)
	var throttle := _throttle(speed, delta)
	if _obstacle_ahead:
		throttle = minf(throttle, 0.45)
	_roll_mistakes(delta)
	throttle = _apply_mistake(throttle)
	_update_patience(delta)

	# 脱困保险：低速卡死超过 2 秒就放弃让位/巡航，直接朝赛道中心线全油门。
	# （上坡 + 低耐力 + 让位叠加时最容易发生；自动测试会因此超时，必须兜底。）
	if speed < Tuning.BASE_MAX_SPEED * 0.22:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	if _stuck_timer >= 1.6:
		give_way_timer = 0.0
		var target_point := track.point_at(racer.s_pos + 90.0)
		var diff := angle_difference(racer.angle, (target_point - racer.position).angle())
		steer = clampf(diff * 3.6, -1.0, 1.0)
		throttle = 1.0
	# 冲出路面（撞进树叶/树林）时，无条件向赛道中心线靠回来
	if racer.off_road:
		var center_point := track.point_at(racer.s_pos + 70.0)
		var to_center := angle_difference(racer.angle, (center_point - racer.position).angle())
		steer = clampf(to_center * 3.6 + steer * 0.25, -1.0, 1.0)
		throttle = maxf(throttle, 0.8)

	return Vector2(clampf(throttle, -1.0, 1.0), clampf(steer, -1.0, 1.0))


# ------------------------------------------------------------------ 转向

func _steer_toward_track(speed: float) -> float:
	var lookahead := Tuning.AI_LOOKAHEAD_BASE + speed * Tuning.AI_LOOKAHEAD_PER_SPEED
	var target_s := racer.s_pos + lookahead
	var target_point := track.point_at(target_s)
	# 横向纠偏：目标点向中心线收回自身横向偏移的 45%（上限 90px），
	# 收敛而不是硬掰，避免“打满方向 -> 越过中心线 -> 反向打满”的振荡。
	var correction := clampf(racer.center_lateral * 0.60, -110.0, 110.0)
	target_point -= track.normal_at(target_s) * correction
	var desired := (target_point - racer.position).angle()
	var diff := angle_difference(racer.angle, desired)
	return clampf(diff * Tuning.AI_STEER_GAIN, -1.0, 1.0)


func _avoid_debris(steer: float) -> float:
	_obstacle_ahead = false
	if track.debris.is_empty():
		return steer
	var forward := Vector2.from_angle(racer.angle)
	for item: Dictionary in track.debris:
		var to_item: Vector2 = item["position"] - racer.position
		var along := to_item.dot(forward)
		if along < 4.0 or along > 150.0:
			continue
		var lateral := to_item.dot(forward.orthogonal())
		var radius: float = float(item["radius"]) + Tuning.SLIME_RADIUS + 16.0
		if absf(lateral) < radius:
			var avoid_dir := -1.0 if lateral >= 0.0 else 1.0
			var urgency := clampf(1.0 - along / 150.0, 0.25, 1.0)
			# 不要为了躲障碍而撞进路边的树叶：贴近某一侧时优先减速而不是猛打方向
			var edge := racer.center_lateral / maxf(track.half_width, 1.0)
			var outward := avoid_dir * edge > 0.30 and absf(edge) > 0.30
			if outward:
				steer = clampf(steer + avoid_dir * 0.20 * urgency, -1.0, 1.0)
				_obstacle_ahead = true
			else:
				steer = clampf(steer + avoid_dir * 0.75 * urgency, -1.0, 1.0)
				if along < 70.0:
					_obstacle_ahead = true
	return steer


func _seek_pack(steer: float, racers: Array[Racer]) -> float:
	if racer.pack != null:
		return steer
	var target: Racer = null
	var best_distance := 150.0
	for other: Racer in racers:
		if other == racer:
			continue
		var distance := racer.position.distance_to(other.position)
		if distance < best_distance:
			best_distance = distance
			target = other
	if target == null:
		return steer
	var to_target := (target.position - racer.position).angle()
	var diff := angle_difference(racer.angle, to_target)
	if absf(diff) > deg_to_rad(62.0):
		return steer
	var blend := clampf(0.65 * fuse_bias, 0.0, 0.9)
	var seek_steer := clampf(diff * 3.4, -1.0, 1.0)
	return clampf(lerpf(steer, seek_steer, blend), -1.0, 1.0)


func _give_way_steer(steer: float) -> float:
	if give_way_timer <= 0.0:
		return steer
	# 弯道里让位幅度收敛，避免整团被带出路面
	var curvature := track.max_curvature_ahead(racer.s_pos, 220.0)
	var corner_factor := clampf(1.0 - curvature / 0.0035, 0.25, 1.0)
	return clampf(steer + _way_side * 0.42 * corner_factor, -1.0, 1.0)


# ------------------------------------------------------------------ 油门

func _throttle(speed: float, delta: float) -> float:
	var total_progress := float(racer.progress) / (track.length * float(level.total_laps))
	if total_progress > Tuning.AI_SPRINT_PROGRESS:
		sprinting = true

	if sprinting:
		return 1.0

	var corner_limit := _corner_speed_limit()
	if speed > corner_limit * 1.04:
		return -1.0

	# 耐力管理：低于低阈值转入滑行恢复，恢复到舒适值再加速
	if not recovering_stamina and racer.stamina < Tuning.AI_LOW_STAMINA:
		recovering_stamina = true
	if recovering_stamina and racer.stamina > Tuning.AI_COMFORT_STAMINA:
		recovering_stamina = false
	if recovering_stamina:
		return 0.0

	if give_way_timer > 0.0:
		return 0.55

	if racer.pack != null and racer.pack_index == 0 and patience < 0.25:
		return 0.72

	# 接近弯道限速时收油，避免忽刹忽加
	if speed > corner_limit * 0.92:
		return 0.35
	return 1.0


func _corner_speed_limit() -> float:
	var lookahead := 170.0 + racer.current_speed() * 0.55
	var curvature := track.max_curvature_ahead(racer.s_pos, lookahead)
	var tightness := clampf(curvature / 0.0025, 0.0, 1.0)
	var slow := Tuning.AI_CORNER_SLOWDOWN * tightness * brake_skill
	var limit := maxf(120.0, Tuning.BASE_MAX_SPEED * (1.0 - slow) * racer.speed_scale)
	last_corner_limit = limit
	return limit


# ------------------------------------------------------------------ 耐心条 / 失误

func _update_patience(delta: float) -> void:
	if give_way_timer > 0.0:
		give_way_timer = maxf(0.0, give_way_timer - delta)
		if give_way_timer <= 0.0:
			patience = 0.55
	if racer.pack != null and racer.pack.size() > 1:
		if racer.pack_index == 0:
			patience -= delta * Tuning.AI_PATIENCE_LEAD_DRAIN / maxf(patience_scale, 0.1)
			if patience <= 0.0:
				give_way_timer = Tuning.AI_GIVE_WAY_TIME
				_way_side = -_way_side
		else:
			patience += delta * Tuning.AI_PATIENCE_FOLLOW_REGEN
	else:
		patience += delta * 0.7
	patience = clampf(patience, 0.0, 1.0)


func _roll_mistakes(delta: float) -> void:
	mistake_roll = rng.randf()
	if mistake_timer > 0.0:
		mistake_timer = maxf(0.0, mistake_timer - delta)
		return
	if mistake_roll < mistake_rate * delta:
		mistake_timer = rng.randf_range(0.25, 0.6)


func _apply_mistake(throttle: float) -> float:
	if mistake_timer > 0.0:
		return throttle * 0.35
	return throttle