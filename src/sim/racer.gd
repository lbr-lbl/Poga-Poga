class_name Racer
extends Node2D
## 单只史莱姆（玩家或 AI）：运动、双层耐力、稳定、融合参与、记圈进度、眼睛。
##
## 说明：
## - 本类不读取输入、不跑 AI：`Race` 每物理帧算好 throttle/steer 后调用 `simulate()`，
##   这样玩家、AI、自动测试走同一条运动学路径，调参结论可复现。
## - **躯体由 SlimeBlobLayer 统一绘制**（多只靠近会融合成一坨黏液），
##   本类只绘制眼睛；眼睛也是碰撞判定的实际依据（见 `eye_left()/eye_right()`）。
## - 位置 = 躯体中心；眼睛在躯体前方 `EYE_FORWARD` 处，两眼横向间距受团内张力挤压。

const BODY_RADIUS := Tuning.SLIME_RADIUS

signal lap_completed(lap_index: int, lap_time: float)
signal crossed_finish()

var id: int = 0
var display_name: String = ""
var is_player: bool = false
var is_ai: bool = true

## 属性：stamina / speed / stability，范围 5..10。
var stats: Dictionary = {"stamina": 5.0, "speed": 5.0, "stability": 5.0}
## 难度倍率：AI 由关卡给，玩家恒为 1.0。
var speed_scale: float = 1.0

# 表现参数（由 Race 配置）
var blob_radius: float = Tuning.SLIME_RADIUS
var blob_tint: float = 0.4
var blob_phase: float = 0.0
## 眼睛视觉大小倍率：玩家更大更亮，AI 各有差异（无 UI 标识下靠眼睛认人）
var eye_radius_scale: float = 1.0
## 两眼间距倍率：AI 个体差异（无 UI 标识下靠眼睛认人）
var eye_spacing_scale: float = 1.0

var velocity: Vector2 = Vector2.ZERO
var angle: float = 0.0
var throttle_in: float = 0.0
var steer_in: float = 0.0

var stamina: float = 1.0
var stamina_cap: float = 1.0
var stability_dip: float = 0.0
var fusion_gain: float = 0.0
var fusion_cooldown: float = 0.0
var eye_collision_cooldown: float = 0.0
var leaf_hit_cooldown: float = 0.0
var pack = null
var pack_index: int = -1

var lap: int = 0
var s_pos: float = 0.0
var hint_index: int = -1
var prev_s: float = 0.0
var progress: float = 0.0
var checkpoint_mask: int = 0
var finished: bool = false
var finish_order: int = 0
var finish_time: float = -1.0
var lap_times: Array[float] = []
var lap_start_time: float = 0.0
var off_road: bool = false
var center_dist: float = 0.0
var center_lateral: float = 0.0

var track: RaceTrack
## Race 实例。不写类型以避免 Racer <-> Race 的循环类型依赖（由 Race 单向引用 Racer）。
var race = null

var _slope: float = 0.0
var _hit_flash: float = 0.0
var _move_phase: float = 0.0
## 形态：加速/刹车导致的眼距倍率（平滑后用于绘制与眼睛碰撞）
var _spacing_form: float = 1.0
## 形态：碰撞后眯眼（><）强度 0..1
var _squint: float = 0.0
## 形态：碰撞后左右晃动时长与相位
var _shake_timer: float = 0.0
var _shake_phase: float = 0.0
## 玩家史莱姆的音效节点（SlimeAudio，无头模式为 null）
var _audio = null


func setup(p_id: int, p_is_player: bool, p_stats: Dictionary, p_speed_scale: float) -> void:
	id = p_id
	is_player = p_is_player
	is_ai = not p_is_player
	stats = p_stats.duplicate()
	speed_scale = p_speed_scale
	display_name = "P" if is_player else "A%d" % p_id


func place_at(p_position: Vector2, p_angle: float, p_track: RaceTrack) -> void:
	position = p_position
	angle = p_angle
	rotation = p_angle
	track = p_track
	velocity = Vector2.ZERO
	var res := track.nearest(position, -1)
	hint_index = res.index
	s_pos = res.s
	prev_s = s_pos
	progress = s_pos


func _ready() -> void:
	if is_player:
		var audio_script := load("res://src/audio/slime_audio.gd")
		if audio_script != null:
			_audio = audio_script.new()
			_audio.name = "SlimeAudio"
			add_child(_audio)


# ------------------------------------------------------------------ 眼睛

## 当前两眼间距：团内张力越大越挤；加速靠近、刹车拉远（形态表演 + 碰撞真值共用）。
func eye_spacing_current() -> float:
	var squeeze := 0.0
	if pack != null:
		squeeze = clampf(float(pack.tension_ratio(self)), 0.0, 1.0) * 0.30
	return Tuning.EYE_SPACING * eye_spacing_scale * _spacing_form * (1.0 - squeeze)


func eye_center() -> Vector2:
	return position + Vector2.from_angle(angle) * Tuning.EYE_FORWARD


func eye_left() -> Vector2:
	var forward := Vector2.from_angle(angle)
	var right := forward.orthogonal()
	return position + forward * Tuning.EYE_FORWARD - right * (eye_spacing_current() * 0.5)


func eye_right() -> Vector2:
	var forward := Vector2.from_angle(angle)
	var right := forward.orthogonal()
	return position + forward * Tuning.EYE_FORWARD + right * (eye_spacing_current() * 0.5)


## 两只史莱姆最近的一对眼睛之间的距离（碰撞判定用）。
func eye_distance_to(other: Racer) -> float:
	var a_left := eye_left()
	var a_right := eye_right()
	var b_left := other.eye_left()
	var b_right := other.eye_right()
	return minf(
		minf(a_left.distance_to(b_left), a_left.distance_to(b_right)),
		minf(a_right.distance_to(b_left), a_right.distance_to(b_right))
	)


# ------------------------------------------------------------------ 运动

func simulate(dt: float, throttle: float, steer: float) -> void:
	if finished:
		throttle = 0.0
		steer = 0.0
	throttle_in = clampf(throttle, -1.0, 1.0)
	steer_in = clampf(steer, -1.0, 1.0)

	fusion_cooldown = maxf(0.0, fusion_cooldown - dt)
	stability_dip = maxf(0.0, stability_dip - dt)
	eye_collision_cooldown = maxf(0.0, eye_collision_cooldown - dt)
	leaf_hit_cooldown = maxf(0.0, leaf_hit_cooldown - dt)
	_slope = track.slope_at(s_pos)

	_apply_steering(dt)
	_apply_drive(dt)
	if pack != null:
		_apply_fusion_spring(dt)
	_apply_off_road_drag(dt)
	position += velocity * dt
	_update_stamina(dt)
	_update_shape(dt)
	_update_visual(dt)
	if _audio != null:
		_audio.set_state(throttle_in, current_speed(), _shake_timer > 0.0)
	queue_redraw()


## 形态表演：加速时两眼靠近、刹车时拉远；碰撞后眯眼并左右晃动。
func _update_shape(dt: float) -> void:
	var target_form := 1.0
	if throttle_in > 0.05:
		target_form -= Tuning.EYE_SQUEEZE_ACCEL * throttle_in
	elif throttle_in < -0.05:
		target_form += Tuning.EYE_SQUEEZE_BRAKE * (-throttle_in)
	target_form = clampf(target_form, 0.55, 1.45)
	_spacing_form = lerpf(_spacing_form, target_form, clampf(12.0 * dt, 0.0, 1.0))
	if _squint > 0.0:
		_squint = maxf(0.0, _squint - dt / maxf(Tuning.EYE_SQUINT_TIME, 0.05))
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - dt)
		_shake_phase += dt * 26.0


## 当前形态倍率：<1 眼睛靠近（加速），>1 眼睛拉远（刹车）。自动测试用来验证形态生效。
func eye_form() -> float:
	return _spacing_form


## 绘制用的晃动偏移（眼睛与黏液躯体共用，碰撞时左右晃动）。
func draw_shake_offset() -> Vector2:
	if _shake_timer <= 0.0:
		return Vector2.ZERO
	var strength := clampf(_shake_timer / maxf(Tuning.EYE_SQUINT_TIME, 0.05), 0.0, 1.0) * Tuning.EYE_SHAKE_AMPLITUDE
	return Vector2(sin(_shake_phase), cos(_shake_phase * 0.8)) * strength


func current_speed() -> float:
	return velocity.length()


func max_speed() -> float:
	var base := Tuning.BASE_MAX_SPEED * (1.0 + (float(stats.speed) - 5.0) * Tuning.SPEED_STAT_GAIN) * speed_scale
	base *= 0.74 + 0.26 * stamina_cap
	base *= 1.0 + Tuning.GAIN_SPEED_BONUS * fusion_gain
	if off_road:
		base *= Tuning.OFFROAD_SPEED_MULT
	if _slope < 0.0:
		base *= 1.0 + 0.18 * _slope
	elif _slope > 0.0:
		base *= 1.0 + 0.12 * _slope
	return maxf(base, 30.0)


func accel_rate() -> float:
	var base := Tuning.BASE_ACCEL * (1.0 + (float(stats.speed) - 5.0) * 0.05) * speed_scale
	base *= Tuning.STAMINA_ACCEL_FLOOR + (1.0 - Tuning.STAMINA_ACCEL_FLOOR) * clampf(stamina, 0.0, 1.0)
	base *= 1.0 + Tuning.GAIN_ACCEL_BONUS * fusion_gain
	if stability_dip > 0.0:
		base *= Tuning.STABILITY_DIP_ACCEL
	if off_road:
		base *= Tuning.OFFROAD_ACCEL_MULT
	if _slope < 0.0:
		base *= 1.0 + 0.25 * _slope
	return base


func grip() -> float:
	var stab_norm := clampf((float(stats.stability) - 5.0) / 5.0, -1.0, 1.0)
	var value := 0.82 + 0.18 * (stab_norm * 0.5 + 0.5)
	value *= Tuning.LOW_STAMINA_GRIP + (1.0 - Tuning.LOW_STAMINA_GRIP) * clampf(stamina * 1.6, 0.0, 1.0)
	if stability_dip > 0.0:
		value *= Tuning.STABILITY_DIP_GRIP
	if pack != null:
		value *= 0.92
	if _slope > 0.0:
		value *= 1.0 - 0.18 * _slope
	return clampf(value, 0.25, 1.1)


func _apply_steering(dt: float) -> void:
	var speed_ratio := clampf(current_speed() / Tuning.BASE_MAX_SPEED, 0.0, 1.25)
	var turn := Tuning.TURN_RATE * (0.5 + 0.5 * speed_ratio) * grip()
	angle = wrapf(angle + steer_in * turn * dt, -PI, PI)


func _apply_drive(dt: float) -> void:
	var forward := Vector2.from_angle(angle)
	var right := forward.orthogonal()
	var vf := velocity.dot(forward)
	var vl := velocity.dot(right)
	var vmax := max_speed()

	# 蠕动：加速力随节律轻微起伏，让速度像鼻涕虫一样“一拱一拱”
	_move_phase += (0.7 + clampf(vf / Tuning.BASE_MAX_SPEED, 0.0, 1.0) * 2.4) * Tuning.GOO_PULSE_RATE * dt
	var pulse := 1.0 + Tuning.GOO_PULSE_ACCEL * sin(_move_phase)

	if throttle_in > 0.01:
		if stamina > 0.001:
			var a := accel_rate() * pulse * throttle_in * (1.0 - clampf(vf / vmax, 0.0, 1.0))
			vf += a * dt
	elif throttle_in < -0.01:
		vf = move_toward(vf, 0.0, Tuning.BRAKE_DECEL * absf(throttle_in) * dt)
	else:
		var drag := Tuning.coast_drag(stats)
		if stability_dip > 0.0:
			drag *= Tuning.STABILITY_DIP_COAST
		if off_road:
			drag += Tuning.OFFROAD_DRAG
		if _slope < 0.0:
			drag += 0.22 * (-_slope)
		vf *= exp(-drag * dt)

	if vf > vmax:
		vf = lerpf(vf, vmax, clampf(4.0 * dt, 0.0, 1.0))
	if _slope > 0.0:
		vf += 26.0 * _slope * dt
	elif _slope < 0.0:
		vf -= 18.0 * (-_slope) * dt
	vf = maxf(vf, 0.0)

	vl *= exp(-Tuning.LATERAL_GRIP * grip() * dt)
	velocity = forward * vf + right * vl


## 融合弹力：把个体拉向团内槽位。
## 纵向（沿团方向）弹力刻意做得很软，这样“加速前移 / 刹车后移”真的能在团内换位；
## 横向弹力更强，负责维持纵列。玩家用加速/刹车/转向与弹力对抗，就是调位与脱离的操作入口。
func _apply_fusion_spring(dt: float) -> void:
	var target: Vector2 = pack.slot_for(self)
	var offset := target - position
	var pack_direction: Vector2 = pack.direction
	var along := offset.dot(pack_direction)
	var lateral_offset := offset - pack_direction * along
	var tension: float = pack.tension_ratio(self)
	var stiffness_scale := 1.0 + 0.9 * tension
	velocity += pack_direction * along * Tuning.PACK_SPRING_LONG * stiffness_scale * dt
	velocity += lateral_offset * Tuning.PACK_SPRING_LAT * stiffness_scale * dt
	var pack_velocity: Vector2 = pack.velocity()
	velocity += (pack_velocity - velocity) * Tuning.PACK_DAMPING * dt


func _apply_off_road_drag(dt: float) -> void:
	if off_road:
		velocity *= exp(-0.55 * dt)


func _update_stamina(dt: float) -> void:
	var ratio := clampf(current_speed() / maxf(max_speed(), 1.0), 0.0, 1.2)
	var st_mult := Tuning.stamina_mult(stats)
	var fusion_save := 1.0 - Tuning.GAIN_STAMINA_SAVE * fusion_gain
	if throttle_in > 0.05 and stamina > 0.0:
		# 基础消耗 + 速度相关消耗：即使低速也会持续掉，保证耐力条是活的资源
		var speed_factor := 0.45 + 0.55 * pow(clampf(ratio, 0.0, 1.2), 1.4)
		var drain := Tuning.DRAIN_ACCEL * speed_factor * fusion_save / maxf(st_mult, 0.3)
		if off_road:
			drain += Tuning.OFFROAD_EXTRA_DRAIN
		if _slope < 0.0:
			drain *= 1.0 + 0.3 * (-_slope)
		stamina -= drain * dt
		stamina_cap -= Tuning.DRAIN_CAP * (0.35 + 0.65 * clampf(ratio, 0.0, 1.0)) * fusion_save * dt
	elif throttle_in < -0.05:
		stamina += Tuning.REGEN_BRAKE * dt
		stamina_cap += Tuning.REGEN_CAP_BRAKE * dt
	else:
		stamina += Tuning.REGEN_COAST * st_mult * dt
		stamina_cap += Tuning.REGEN_CAP_COAST * st_mult * dt
	stamina_cap = clampf(stamina_cap, 0.18, 1.0)
	stamina = clampf(stamina, 0.0, stamina_cap)


func _update_visual(dt: float) -> void:
	rotation = angle
	_hit_flash = maxf(0.0, _hit_flash - dt * 1.8)


# ------------------------------------------------------------------ 碰撞/受击

func take_hit(speed_loss: float, dip: float, knock_velocity: Vector2 = Vector2.ZERO) -> void:
	var speed := current_speed()
	if speed > 1.0:
		velocity = velocity.normalized() * speed * (1.0 - clampf(speed_loss, 0.0, 0.9))
	velocity += knock_velocity
	stability_dip = maxf(stability_dip, dip)
	_hit_flash = 1.0
	# 碰撞表演：眯成 >< 并左右晃动
	_squint = 1.0
	_shake_timer = Tuning.EYE_SQUINT_TIME
	_shake_phase += 1.3
	if _audio != null:
		_audio.play_poga()


func can_hit_leaf() -> bool:
	return leaf_hit_cooldown <= 0.0


func mark_leaf_hit() -> void:
	leaf_hit_cooldown = Tuning.LEAF_HIT_COOLDOWN


# ------------------------------------------------------------------ 记圈 / 进度

func update_progress(dt: float) -> void:
	if finished:
		return
	var result := track.nearest(position, hint_index)
	hint_index = result.index
	s_pos = result.s
	center_dist = result.dist
	center_lateral = result.lateral
	off_road = result.dist > track.half_width

	# 环道进度：先做“跨圈修正”，再判断本帧扫过了哪些检查点/终点线。
	# 不能简单用 prev_s > cur_s 判跨圈：最近点投影会让 s 出现小幅回退，会产生假记圈。
	var length := track.length
	var delta := s_pos - prev_s
	if delta < -length * 0.5:
		delta += length
	elif delta > length * 0.5:
		delta -= length

	if delta > 0.0:
		for i: int in range(track.checkpoints.size()):
			var bit := 1 << i
			if (checkpoint_mask & bit) != 0:
				continue
			var offset := fposmod(track.checkpoints[i] - prev_s, length)
			if offset > 0.0 and offset <= delta:
				checkpoint_mask |= bit

		var finish_offset := fposmod(0.0 - prev_s, length)
		if finish_offset > 0.0 and finish_offset <= delta:
			var required := (1 << track.checkpoints.size()) - 1
			if checkpoint_mask == required:
				lap += 1
				var now := 0.0
				if race != null:
					now = float(race.race_time)
				var lap_time := maxf(0.0, now - lap_start_time)
				lap_times.append(lap_time)
				lap_start_time = now
				checkpoint_mask = 0
				lap_completed.emit(lap, lap_time)
				if lap >= track.level.total_laps:
					finished = true
					finish_time = now
					crossed_finish.emit()
			else:
				checkpoint_mask = 0
	progress = float(lap) * track.length + s_pos
	prev_s = s_pos


func rank_progress() -> float:
	if finished:
		return 1000000.0 - float(finish_order)
	return progress


# ------------------------------------------------------------------ 绘制（只画眼睛）

func _draw() -> void:
	var shake := draw_shake_offset()
	var spacing := eye_spacing_current()
	var eye_y := spacing * 0.5
	var eye_x := Tuning.EYE_FORWARD
	var radius := Tuning.EYE_RADIUS * eye_radius_scale
	if _hit_flash > 0.0:
		radius += _hit_flash * 0.9

	var eye_color := Tuning.COLOR_EYE
	var pupil_color := Tuning.COLOR_PUPIL
	# 融合时眼睛更亮（“融合后只露眼睛”）
	if fusion_gain > 0.02:
		eye_color = Tuning.COLOR_EYE.lightened(0.12)

	var socket_radius := radius + 2.6
	var left_eye := Vector2(eye_x, -eye_y) + shake
	var right_eye := Vector2(eye_x, eye_y) + shake

	# 眼窝：把眼睛“嵌”进黏液里（深色圆环保证在深色躯体上可读）
	draw_circle(left_eye, socket_radius, Color(0.02, 0.02, 0.02, 0.95))
	draw_circle(right_eye, socket_radius, Color(0.02, 0.02, 0.02, 0.95))

	if _squint > 0.25:
		_draw_squint(left_eye, right_eye, radius, eye_color, shake)
		return

	var pupil_shift := clampf(steer_in * 1.1, -1.2, 1.2)
	# 眼球
	draw_circle(left_eye, radius, eye_color)
	draw_circle(right_eye, radius, eye_color)
	# 瞳孔
	draw_circle(left_eye + Vector2(radius * 0.42, pupil_shift * 0.6), radius * 0.52, pupil_color)
	draw_circle(right_eye + Vector2(radius * 0.42, pupil_shift * 0.6), radius * 0.52, pupil_color)
	# 一点高光，让眼睛在黑白画面里更“活”
	draw_circle(left_eye + Vector2(-radius * 0.38, -radius * 0.38), radius * 0.24, Color(1.0, 1.0, 1.0, 0.95))
	draw_circle(right_eye + Vector2(-radius * 0.38, -radius * 0.38), radius * 0.24, Color(1.0, 1.0, 1.0, 0.95))


## 碰撞时的“><”眯眼：两只眼睛各画成朝向对方的尖角，并随晃动左右摆。
func _draw_squint(left_eye: Vector2, right_eye: Vector2, radius: float, color: Color, shake: Vector2) -> void:
	var strength := clampf(_squint, 0.0, 1.0)
	var arm := radius * (0.85 + 0.25 * strength)
	var depth := radius * (0.65 + 0.35 * strength)
	var line_color := color
	var wobble := sin(_shake_phase * 1.3) * strength * 1.6

	# > 形（左眼，尖角朝内）
	draw_line(left_eye + Vector2(-arm + 0.6, -depth), left_eye + Vector2(arm * 0.35 + 0.6, wobble), line_color, 2.6, true)
	draw_line(left_eye + Vector2(-arm + 0.6, depth), left_eye + Vector2(arm * 0.35 + 0.6, wobble), line_color, 2.6, true)
	# < 形（右眼，尖角朝内）
	draw_line(right_eye + Vector2(arm - 0.6, -depth), right_eye + Vector2(-arm * 0.35 - 0.6, wobble), line_color, 2.6, true)
	draw_line(right_eye + Vector2(arm - 0.6, depth), right_eye + Vector2(-arm * 0.35 - 0.6, wobble), line_color, 2.6, true)
	# 晃动时加一点小汗滴似的短线，强调受击
	if strength > 0.5:
		draw_line(left_eye + Vector2(0.0, -(radius + 2.6) - 2.0), left_eye + Vector2(0.0, -(radius + 2.6) - 6.0), Color(0.9, 0.9, 0.9, 0.8), 1.6, true)