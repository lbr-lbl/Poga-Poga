class_name UiSfx
extends RefCounted
## 界面按键音效（点击 / 确认 / 返回）。
##
## - 纯静态工具，不需要 autoload；首次播放时懒加载并缓存；
## - 每次播放创建一个一次性 AudioStreamPlayer，播完自动释放，同时限制并发数；
## - 无头模式（自动测试/截图）自动静默，不影响逻辑。

const SFX_DIR := "res://assets/sfx/"
const MAX_VOICES := 6

static var _cache: Dictionary = {}
static var _voices: Array[AudioStreamPlayer] = []


## sound: 音效名（不含扩展名），如 "ui_click" / "ui_confirm" / "ui_back"。
static func play(sound: StringName, volume_db: float = -6.0, pitch: float = 1.0) -> void:
    if DisplayServer.get_name() == "headless":
        return
    var stream := _get_stream(sound)
    if stream == null:
        return
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return
    _prune()
    while _voices.size() >= MAX_VOICES:
        _release_oldest()
    var player := AudioStreamPlayer.new()
    player.name = "UiSfxOneShot"
    player.bus = "SFX"
    player.stream = stream
    player.volume_db = clampf(volume_db, -60.0, 0.0)
    player.pitch_scale = clampf(pitch, 0.5, 2.0)
    player.finished.connect(func() -> void:
        _voices.erase(player)
        player.queue_free()
    )
    tree.root.add_child(player)
    _voices.append(player)
    player.play()


static func _get_stream(sound: StringName) -> AudioStream:
    if _cache.has(sound):
        return _cache[sound] as AudioStream
    var path := SFX_DIR + String(sound) + ".wav"
    var stream: AudioStream = null
    if ResourceLoader.exists(path):
        stream = load(path) as AudioStream
    _cache[sound] = stream
    return stream


static func _prune() -> void:
    var alive: Array[AudioStreamPlayer] = []
    for player: AudioStreamPlayer in _voices:
        if is_instance_valid(player) and player.is_inside_tree():
            alive.append(player)
    _voices = alive


static func _release_oldest() -> void:
    if _voices.is_empty():
        return
    var player: AudioStreamPlayer = _voices.pop_front()
    if is_instance_valid(player):
        player.queue_free()
