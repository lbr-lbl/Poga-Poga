class_name SlimeAudio
extends Node2D
## 玩家史莱姆的音效（挂在玩家 Racer 身上，位置音源）。
##
## - 加速：循环播放「win~ win~」，音高随速度略升；
## - 刹车：循环播放「Pooo~」；
## - 碰撞：播放一次「Poga」，带随机音高避免重复听感。
##
## 音频缺失 / 无头模式自动静默降级，绝不影响玩法与自动测试。

const ACCEL_PATH := "res://assets/sfx/winwin.wav"
const BRAKE_PATH := "res://assets/sfx/pooo.wav"
const HIT_PATH := "res://assets/sfx/poga.wav"

const ACCEL_DB := -11.0
const BRAKE_DB := -9.0
const HIT_DB := -4.0

var _enabled: bool = true
var _accel: AudioStreamPlayer2D
var _brake: AudioStreamPlayer2D
var _poga: AudioStreamPlayer2D
var _hit_cooldown: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_enabled = false
		return
	_accel = _make_player(ACCEL_PATH, ACCEL_DB, true)
	_brake = _make_player(BRAKE_PATH, BRAKE_DB, true)
	_poga = _make_player(HIT_PATH, HIT_DB, false)
	if OS.get_cmdline_user_args().has("--verbose"):
		print("SLIMEAUDIO ready accel=%s brake=%s hit=%s" % [_accel != null, _brake != null, _poga != null])


func _make_player(path: String, volume_db: float, looped: bool) -> AudioStreamPlayer2D:
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path)
	if stream == null:
		return null
	if looped and stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = maxi(1, int(wav.get_length() * float(wav.mix_rate)))
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 3000.0
	player.attenuation = 0.15
	player.panning_strength = 0.6
	add_child(player)
	return player


## 每帧由 Racer 调用，决定加速/刹车循环音。
func set_state(throttle: float, speed: float, stunned: bool) -> void:
	if not _enabled:
		return
	_hit_cooldown = maxf(0.0, _hit_cooldown - get_process_delta_time())
	var accel_on := throttle > 0.35 and speed > 15.0 and not stunned
	var brake_on := throttle < -0.35 and not stunned
	var speed_ratio := clampf(speed / maxf(Tuning.BASE_MAX_SPEED, 1.0), 0.0, 1.0)
	_update_loop(_accel, accel_on, 0.92 + speed_ratio * 0.35)
	_update_loop(_brake, brake_on, 0.98)


func _update_loop(player: AudioStreamPlayer2D, enabled: bool, pitch: float) -> void:
	if player == null:
		return
	if enabled:
		player.pitch_scale = pitch
		if not player.playing:
			player.play()
	elif player.playing:
		player.stop()


## 碰撞音「Poga」。
func play_poga() -> void:
	if not _enabled or _poga == null or _hit_cooldown > 0.0:
		return
	_hit_cooldown = 0.12
	_poga.pitch_scale = randf_range(0.92, 1.08)
	_poga.play()


func stop_all() -> void:
	for player: AudioStreamPlayer2D in [_accel, _brake]:
		if player != null and player.playing:
			player.stop()