class_name RivalBars
extends Node2D
## 只对离 Poga 最近的一个 AI 显示头顶耐力细线；目标切换时淡入淡出，避免闪烁。
## 显示范围：融合体内 115px，非融合 82px。

var race: Race
var _target: Racer
var _alpha: float = 0.0
var _target_lock: float = 0.0


func setup(p_race: Race) -> void:
    race = p_race


func _ready() -> void:
    z_index = 60
    set_process(true)


func _process(delta: float) -> void:
    if race == null or race.player == null:
        _target = null
        return
    var player: Racer = race.player
    var best: Racer = null
    var best_distance := INF
    for racer: Racer in race.racers:
        if racer == player or racer.finished:
            continue
        var distance := racer.position.distance_to(player.position)
        var eligible := distance < 82.0
        if player.pack != null and racer.pack == player.pack and distance < 115.0:
            eligible = true
        if eligible and distance < best_distance:
            best_distance = distance
            best = racer
    _target_lock = maxf(0.0, _target_lock - delta)
    if best != _target:
        var keep_target := _target != null and _target_lock > 0.0 and is_instance_valid(_target)
        if not keep_target:
            _target = best
            _target_lock = 0.45
            _alpha = 0.0
    var want := 1.0 if _target != null else 0.0
    _alpha = move_toward(_alpha, want, delta * 7.0)
    queue_redraw()


func _draw() -> void:
    if _target == null or _alpha <= 0.01:
        return
    var ratio := clampf(_target.stamina, 0.0, 1.0)
    var base := _target.position + Vector2(0.0, -26.0)
    var half := 12.0
    draw_line(base + Vector2(-half, 0.0), base + Vector2(half, 0.0), Color(0.02, 0.02, 0.02, 0.85 * _alpha), 2.6)
    draw_line(base + Vector2(-half, 0.0), base + Vector2(-half + half * 2.0 * ratio, 0.0),
        Color(0.92, 0.92, 0.92, 0.95 * _alpha), 1.5)