class_name MusicPlayer
extends Node
## 背景音乐：循环播放柔和的森林风芯片音乐。
##
## - 挂在 Main 下，菜单与比赛共用，不随场景切换中断；
## - 音量固定为低音量背景；按 M 可静音/恢复；
## - 无头模式不创建播放器，自动测试完全静音。

const TRACK_PATH := "res://assets/music/forest_theme.ogg"
const VOLUME_DB := -14.0
const MUTED_DB := -80.0

var _player: AudioStreamPlayer
var _muted: bool = false


func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        return
    if not ResourceLoader.exists(TRACK_PATH):
        push_warning("背景音乐缺失：" + TRACK_PATH)
        return
    var stream: AudioStream = load(TRACK_PATH)
    if stream is AudioStreamOggVorbis:
        (stream as AudioStreamOggVorbis).loop = true
    elif stream is AudioStreamWAV:
        var wav: AudioStreamWAV = stream
        wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
        wav.loop_begin = 0
        wav.loop_end = maxi(1, int(wav.get_length() * float(wav.mix_rate)))

    _player = AudioStreamPlayer.new()
    _player.name = "ForestTheme"
    _player.stream = stream
    _player.volume_db = -60.0
    _player.bus = "Music"
    add_child(_player)
    _player.play()
    if OS.get_cmdline_user_args().has("--verbose"):
        print("MUSIC ready track=%s len=%.1fs loop=%s" % [TRACK_PATH, stream.get_length(), str(stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop)])
    # 2 秒淡入，避免开场突然有音乐
    var tween := create_tween()
    tween.tween_property(_player, "volume_db", VOLUME_DB, 2.0).set_trans(Tween.TRANS_SINE)


func toggle_mute() -> bool:
    _muted = not _muted
    if _player != null:
        _player.volume_db = MUTED_DB if _muted else VOLUME_DB
    return _muted


func is_muted() -> bool:
    return _muted
