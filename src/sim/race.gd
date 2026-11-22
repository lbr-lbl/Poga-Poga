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
signal pause_requested()
signal retry_requested()
signal race_started()

enum State { COUNTDOWN, RACING, FINISHED, TUTORIAL }

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
## 第一关开赛前的“学习移动”段：只模拟玩家，AI 停在起跑区等待
var prestart_active: bool = false
## 新手引导聚焦时临时拉近镜头（由 Tutorial 设置，1.0 = 正常）
var camera_zoom_bias: float = 1.0
var camera_shake: float = 0.0
var preview_mode: bool = false
var _prestart_prev_s: float = 0.0
var _prestart_elapsed: float = 0.0
var tutorial: Tutorial
var track_view: TrackView
var rival_bars: RivalBars
var tip_overlay: TipOverlay
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
var stats_explosions := 0
## 融合团内部“换领骑”（队首易主）次数：用来验证轮换是否真的发生
var stats_lead_changes := 0
var _pack_leader_record: Dictionary = {}
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
var _touch_zone: Dictionary = {}
var _gyro_ready: bool = false
var _gyro_baseline: Vector3 = Vector3.ZERO


func _ready() -> void:
    level = LevelCatalog.get_level(level_index)
    track = RaceTrack.new(level)
    rng.seed = 7000 + level_index
    track_view = TrackView.new(track)
    add_child(track_view)
    rival_bars = RivalBars.new()
    rival_bars.setup(self)
    add_child(rival_bars)
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
        drivers[player.id] = AiDriver.new(player, track, level, 999, 1, 2)
    _setup_camera()
    hud = Hud.new()
    hud.setup(self)
    add_child(hud)
    hud.show_control_guide(_control_guide_text())
    hud.pause_pressed.connect(_on_pause_button)
    if level_index <= 2 and DisplayServer.get_name() != "headless":
        # 第一关：开赛前序章（学移动）；“跳过操作指引”只跳过序章
        if level_index == 0 and GameState.guide_enabled:
            tutorial = Tutorial.new()
            tutorial.setup(self, level_index, true)
            hud.add_child(tutorial)
            _begin_prestart()
        # 情境提示（坡度/低耐力/障碍/纵列/融合/眼睛）：勾选“需要操作指引”时启用，
        # 每种只在第一次遇到时出现一次。
        if GameState.guide_enabled:
            tip_overlay = TipOverlay.new()
            tip_overlay.setup(self)
            hud.add_child(tip_overlay)


func _setup_camera() -> void:
    camera = Camera2D.new()
    camera.position = player.position
    camera.rotation = 0.0
    camera.zoom = Vector2.ONE * Tuning.CAMERA_BASE_ZOOM
    camera.ignore_rotation = true
    camera.position_smoothing_enabled = false
    add_child(camera)
    camera.make_current()


## 第一关开赛前的学习段：把玩家放在起跑线后面，只模拟玩家，AI 在发车区等待。
func _begin_prestart() -> void:
    state = State.TUTORIAL
    prestart_active = true
    var start_s := track.length - 170.0
    var idx := track.index_at(start_s)
    player.place_at(track.samples[idx], track.tangents[idx].angle(), track)
    player.s_pos = start_s
    player.prev_s = start_s
    player.lap = 0
    player.progress = 0.0
    player.checkpoint_mask = 0
    _prestart_prev_s = start_s
    _prestart_elapsed = 0.0
    if track_view != null:
        track_view.prestart_mode = true
        track_view.queue_redraw()
    # AI 先藏起来，等正式发车再出现
    for racer: Racer in racers:
        if racer != player:
            racer.velocity = Vector2.ZERO
            racer.visible = false
            racer.blob_radius = 0.0


## 学习段里只让玩家动；跨过起跑线后正式开始比赛。
func _prestart_step(delta: float) -> void:
    _prestart_elapsed += delta
    var input := _read_player_input(delta)
    player.simulate(delta, input.x, input.y)
    var result := track.nearest(player.position, player.hint_index)
    player.hint_index = result.index
    player.s_pos = result.s
    var crossed := player.s_pos < track.length * 0.25 and _prestart_prev_s > track.length * 0.70
    _prestart_prev_s = player.s_pos
    if crossed or _prestart_elapsed > 45.0:
        _start_from_prestart()


func _start_from_prestart() -> void:
    if not prestart_active:
        return
    prestart_active = false
    state = State.COUNTDOWN
    countdown = Tuning.COUNTDOWN_TIME
    if track_view != null:
        track_view.prestart_mode = false
        track_view.queue_redraw()
    for racer: Racer in racers:
        racer.visible = true
        racer.blob_radius = Tuning.SLIME_RADIUS
    player.place_at(track.point_at(0.0), track.tangent_at(0.0).angle(), track)
    player.s_pos = 0.0
    player.prev_s = 0.0
    player.lap = 0
    player.progress = 0.0
    player.checkpoint_mask = 0
    player.lap_times.clear()
    if tutorial != null:
        tutorial.finish_now()
        tutorial = null


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
            if _finish_timer <= 0.0 and not _result_emitted:
                _result_emitted = true
                race_finished.emit(_build_result())
        State.TUTORIAL:
            _prestart_step(delta)


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

    # 所有性格都按困难难度（tier 2）的数值与操作行动
    var tier_speed: float = Tuning.AI_TIER_SPEED[2]
    var tier_stats: float = Tuning.AI_TIER_STATS[2]
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
        racer.exploded.connect(_on_racer_exploded.bind(racer))
        racer.regrouped.connect(_on_racer_regrouped.bind(racer))
        racer.race = self
        racer.z_index = 20 if is_player else 10
        _apply_visuals(racer, is_player)
        add_child(racer)
        racer.place_at(grid["position"], grid["angle"], track)
        racers.append(racer)
        if is_player:
            player = racer
        else:
            var driver := AiDriver.new(racer, track, level, 100 + slot + level_index * 31, ai_tier, 2)
            drivers[racer.id] = driver
            racer.is_ai = true
            racer.ai_personality = ai_tier


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
        # 统计队首轮换
        var leader: Racer = pack.leader()
        if leader != null:
            var previous: Racer = _pack_leader_record.get(pack, null)
            if previous != null and previous != leader:
                stats_lead_changes += 1
            _pack_leader_record[pack] = leader
        if not pack.is_valid():
            pack.dissolve()
            _pack_leader_record.erase(pack)
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
    if OS.has_feature("mobile"):
        var settings := SettingsStore.load_settings()
        if bool(settings.get("gyro", false)) and GyroProbe.available:
            return _gyro_input()
        return _touch_input()
    var throttle := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
    var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
    return Vector2(throttle, steer)


func _control_guide_text() -> String:
    return InputDevice.guide()


func _on_pause_button() -> void:
    pause_requested.emit()


func _is_evil(racer: Racer) -> bool:
    var driver = drivers.get(racer.id)
    return driver != null and int(driver.personality) == 2


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
            # 邪恶 AI 会主动甩开你，不会和你融合
            if (racer.is_player and _is_evil(other)) or (other.is_player and _is_evil(racer)):
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
            # 眼睛碰撞也会掉耐力（团内碰撞同样生效）
            a.drain_stamina(Tuning.EYE_STAMINA_DRAIN)
            b.drain_stamina(Tuning.EYE_STAMINA_DRAIN)
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

## 自检/截图用：把镜头拉到能看见整条赛道。
func debug_preview() -> void:
    if camera == null or track == null:
        return
    preview_mode = true
    var bounds := Rect2(track.samples[0], Vector2.ZERO)
    for point: Vector2 in track.samples:
        bounds = bounds.expand(point)
    var center := bounds.get_center()
    var extent := maxf(bounds.size.x, bounds.size.y) * 0.5 + track.half_width + 80.0
    var viewport := get_viewport_rect().size
    var fit := minf(viewport.x, viewport.y) / maxf(extent * 2.0, 1.0) * 0.92
    camera.zoom = Vector2.ONE * fit
    camera.position = center
    camera.offset = Vector2.ZERO
    if hud != null:
        hud.visible = false


func _on_racer_exploded(racer: Racer) -> void:
    stats_explosions += 1
    camera_shake = 1.0
    if racer != null and racer.is_player:
        racer.play_explosion_audio()
        if hud != null:
            hud.trigger_break()
            hud.show_scatter_hint()


func _on_racer_regrouped(racer: Racer) -> void:
    if racer != null and racer.is_player and hud != null:
        hud.hide_scatter_hint()


func _update_camera(delta: float) -> void:
    if preview_mode:
        return
    if camera == null or player == null:
        return
    var speed := player.current_speed()
    var ratio := clampf(speed / Tuning.BASE_MAX_SPEED, 0.0, 1.25)
    var target_zoom := lerpf(Tuning.CAMERA_BASE_ZOOM, Tuning.CAMERA_FAST_ZOOM, clampf(ratio, 0.0, 1.0))
    target_zoom *= camera_zoom_bias
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
        pause_requested.emit()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("retry"):
        retry_requested.emit()
        get_viewport().set_input_as_handled()
    elif state == State.FINISHED and event.is_action_pressed("confirm"):
        retry_requested.emit()
        get_viewport().set_input_as_handled()


func _touch_input() -> Vector2:
    var left := false
    var right := false
    var brake := false
    for zone: String in _touch_zone.values():
        if zone == "left":
            left = true
        elif zone == "right":
            right = true
        elif zone == "brake":
            brake = true
    if brake:
        return Vector2(-1.0, 0.0)
    if left and right:
        return Vector2(1.0, 0.0)
    if left:
        return Vector2(0.0, -1.0)
    if right:
        return Vector2(0.0, 1.0)
    return Vector2.ZERO


func _gyro_input() -> Vector2:
    if player == null:
        return Vector2.ZERO
    var accel := Input.get_accelerometer()
    if not _gyro_ready:
        _gyro_baseline = accel
        _gyro_ready = true
        return Vector2.ZERO
    # 设备倾斜方向与加速度计读数方向相反；整体取反后：
    # 向 Poga 前方倾斜 = 加速，反向倾斜 = 刹车，左右倾斜 = 转向。
    var tilt := (Vector2(accel.x, accel.y) - Vector2(_gyro_baseline.x, _gyro_baseline.y)) * -1.0
    var forward := Vector2.from_angle(player.angle)
    var along := tilt.dot(forward)
    var lateral := tilt.dot(forward.orthogonal())
    var throttle := clampf(along / 3.0, -1.0, 1.0) if absf(along) > 0.35 else 0.0
    var steer := clampf(lateral / 2.4, -1.0, 1.0) if absf(lateral) > 0.35 else 0.0
    return Vector2(throttle, steer)


func _input(event: InputEvent) -> void:
    if not OS.has_feature("mobile"):
        return
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            var half := get_viewport_rect().size.x * 0.5
            if touch.position.y > get_viewport_rect().size.y * 0.72:
                _touch_zone[touch.index] = "brake"
            elif touch.position.x < half:
                _touch_zone[touch.index] = "left"
            else:
                _touch_zone[touch.index] = "right"
        else:
            _touch_zone.erase(touch.index)
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if drag.relative.y > 5.0:
            _touch_zone[drag.index] = "brake"


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


## 前方是否有即将进入的坡道：-1 上坡、+1 下坡、0 无。
func approaching_slope() -> int:
    if player == null or track == null:
        return 0
    var best := 9999.0
    var sign := 0
    for zone: LevelDef.SlopeZone in track.level.slopes:
        var start := zone.from_ratio * track.length
        var distance := fposmod(start - player.s_pos, track.length)
        if distance > 25.0 and distance < 320.0 and distance < best:
            best = distance
            sign = -1 if zone.slope < 0.0 else 1
    return sign


## 前方是否有一处障碍（用于第一次遇到障碍时的提示）。
func debris_ahead(max_distance: float = 260.0) -> bool:
    if player == null or track == null:
        return false
    var forward := Vector2.from_angle(player.angle)
    var side := forward.orthogonal()
    for item: Dictionary in track.debris:
        var to_item: Vector2 = item["position"] - player.position
        var along := to_item.dot(forward)
        if along < 20.0 or along > max_distance:
            continue
        if absf(to_item.dot(side)) < track.half_width:
            return true
    return false


func current_terrain_name() -> String:
    if player == null or track == null or track.level.terrain.is_empty():
        return ""
    var ratio := fposmod(player.s_pos / track.length, 1.0)
    for zone: LevelDef.TerrainZone in track.level.terrain:
        if ratio >= zone.from_ratio and ratio < zone.to_ratio:
            match zone.kind:
                &"forest":
                    return "林间"
                &"plain":
                    return "旷野"
                &"rock":
                    return "岩地"
                &"highland":
                    return "高地"
    return ""


func player_slope() -> float:
    if player == null or track == null:
        return 0.0
    return track.slope_at(player.s_pos)


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
