class_name SlimeAudio
extends Node2D
## 玩家史莱姆的音效（挂在玩家 Racer 身上，位置音源）。
##
## - 加速：**音高固定**，只按“提速有多猛”调整发声间隔（越猛叫得越急）；
##   滑行/匀速/刹车时完全不发声；
## - 刹车：循环「Pooo~」，音高固定；
## - 碰撞：一次性「Poga」；
## - 低耐力：轻柔的「呼—呼」喘息循环，音量渐入渐出；耐力清空时一声短促的「吱！」。
##
## 无头模式 / 资源缺失自动静默降级。

const ACCEL_PATHS: Array[String] = [
    "res://assets/sfx/winwin.wav",
    "res://assets/sfx/winwin2.wav",
    "res://assets/sfx/winwin3.wav",
]
const BRAKE_PATH := "res://assets/sfx/pooo.wav"
const HIT_PATH := "res://assets/sfx/poga.wav"
const TIRED_PATH := "res://assets/sfx/tired.wav"
const GASP_PATH := "res://assets/sfx/gasp.wav"

const ACCEL_DB := -12.0
const BRAKE_DB := -9.0
const HIT_DB := -4.0
const TIRED_SILENT_DB := -60.0

var _enabled: bool = true
var _accel_pool: Array[AudioStreamPlayer2D] = []
var _accel_index: int = 0
var _brake: AudioStreamPlayer2D
var _poga: AudioStreamPlayer2D
var _tired: AudioStreamPlayer2D
var _gasp: AudioStreamPlayer2D

var _accel_timer: float = 0.0
var _hit_cooldown: float = 0.0
var _was_empty := false
var _tired_volume: float = TIRED_SILENT_DB


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        _enabled = false
        return
    for path: String in ACCEL_PATHS:
        var player := _make_player(path, ACCEL_DB, false)
        if player != null:
            _accel_pool.append(player)
    _brake = _make_player(BRAKE_PATH, BRAKE_DB, true)
    _poga = _make_player(HIT_PATH, HIT_DB, false)
    _tired = _make_player(TIRED_PATH, TIRED_SILENT_DB, true)
    _gasp = _make_player(GASP_PATH, -9.0, false)
    if OS.get_cmdline_user_args().has("--verbose"):
        print("SLIMEAUDIO ready accel=%s brake=%s hit=%s tired=%s gasp=%s" % [
            _accel_pool.size() > 0, _brake != null, _poga != null, _tired != null, _gasp != null,
        ])


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


## 每帧由 Racer 调用。
func set_state(throttle: float, speed: float, accel: float, stamina: float, empty: bool, stunned: bool) -> void:
    if not _enabled:
        return
    var dt := get_process_delta_time()
    _hit_cooldown = maxf(0.0, _hit_cooldown - dt)
    _accel_timer -= dt
    var speed_ratio := clampf(speed / maxf(Tuning.BASE_MAX_SPEED, 1.0), 0.0, 1.0)
    var accel_ratio := clampf(accel / maxf(Tuning.BASE_ACCEL, 1.0), 0.0, 1.4)

    # 加速声：音高固定，只改变“叫的频率”；多播放器轮换，避免下一声把上一声截断
    var accelerating := accel > 14.0 and throttle > 0.15 and speed > 8.0 and not stunned
    if accelerating:
        if _accel_timer <= 0.0 and not _accel_pool.is_empty():
            var urgency := clampf(accel_ratio, 0.0, 1.4)
            var interval := lerpf(0.62, 0.20, clampf(urgency / 1.2, 0.0, 1.0))
            _accel_timer = interval * randf_range(0.92, 1.08)
            var player := _claim_accel_player()
            if player != null:
                player.pitch_scale = randf_range(0.995, 1.005)
                player.volume_db = -15.0 + clampf(urgency, 0.0, 1.2) * 5.0 + speed_ratio * 2.0
                player.play()
    else:
        _accel_timer = minf(_accel_timer, 0.10)

    var brake_on := throttle < -0.35 and not stunned
    _update_loop(_brake, brake_on, 1.0, -10.0)

    # 低耐力喘息：音量渐入渐出，避免突兀
    var target_volume := TIRED_SILENT_DB
    var tired_on := stamina < 0.25 and not stunned
    if tired_on:
        var low := clampf((0.25 - stamina) / 0.25, 0.0, 1.0)
        target_volume = -27.0 + low * 6.0
    _tired_volume = move_toward(_tired_volume, target_volume, dt * 26.0)
    if _tired != null:
        _tired.volume_db = _tired_volume
        _tired.pitch_scale = 1.0
        if _tired_volume > -46.0 and not _tired.playing:
            _tired.play()
        elif _tired_volume <= -46.0 and _tired.playing:
            _tired.stop()

    # 耐力刚清空：短促的一声“吱！”，同时进入喘息
    if empty and not _was_empty and _gasp != null:
        _gasp.pitch_scale = randf_range(0.98, 1.03)
        _gasp.play()
    _was_empty = empty


## 找一个空闲的播放器；全忙就等下一声，绝不复用正在发声的播放器。
func _claim_accel_player() -> AudioStreamPlayer2D:
    var count := _accel_pool.size()
    for offset: int in range(count):
        var index := (_accel_index + offset) % count
        var player: AudioStreamPlayer2D = _accel_pool[index]
        if not player.playing:
            _accel_index = (index + 1) % count
            return player
    return null


func _update_loop(player: AudioStreamPlayer2D, enabled: bool, pitch: float, volume_db: float) -> void:
    if player == null:
        return
    if enabled:
        player.pitch_scale = pitch
        player.volume_db = volume_db
        if not player.playing:
            player.play()
    elif player.playing:
        player.stop()


## 碰撞音「Poga」。
## 彻底耗尽爆炸：用低沉的“pooo”加一点噪声感，短促但有分量。
func play_explosion() -> void:
    if _poga == null:
        return
    _poga.pitch_scale = 0.55
    _poga.volume_db = 0.0
    _poga.play()


func play_poga() -> void:
    if not _enabled or _poga == null or _hit_cooldown > 0.0:
        return
    _hit_cooldown = 0.15
    _poga.pitch_scale = randf_range(0.96, 1.04)
    _poga.play()


func stop_all() -> void:
    for player: AudioStreamPlayer2D in [_brake, _tired]:
        if player != null and player.playing:
            player.stop()
    for player: AudioStreamPlayer2D in _accel_pool:
        player.stop()
