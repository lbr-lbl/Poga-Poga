class_name FusionPack
extends RefCounted
## 一个融合团：管理成员排序、槽位（眼睛约束）、增益与散团。
##
## 团内动力学：
## 1. 团方向由成员朝向按“越靠前权重越大”加权平均（前部个体主导转向）；
## 2. 成员沿团方向投影排序，前位为锚点，其余成员的目标槽位 = 锚点 - 方向 × 间距 × 序号；
##    间距小于两倍躯体半径，所以相邻成员的躯体会重叠成一坨（视觉由 SlimeBlobLayer 融合）；
## 3. 每个后位成员的应力 = 与槽位的距离/横向偏移，超过阈值并持续一小段时间即散团；
## 4. 增益由 人数（边际递减）× 团内位置（后位更大）× 贴近度 × 纵列度 决定。
##
## 注意：团内不再有“躯体碰撞”，真正的碰撞是眼睛相撞，由 Race 统一判定。

var members: Array[Racer] = []
var direction: Vector2 = Vector2.RIGHT
var anchor: Racer = null
var shock: float = 0.0

var _slots: Dictionary = {}
var _tension: Dictionary = {}
var _detach_timer: Dictionary = {}
var _velocity: Vector2 = Vector2.ZERO


func _init(first: Racer) -> void:
    members.append(first)
    first.pack = self
    first.pack_index = 0
    direction = Vector2.from_angle(first.angle)


func size() -> int:
    return members.size()


func is_valid() -> bool:
    return members.size() >= 2


func leader() -> Racer:
    return anchor


func join(racer: Racer) -> bool:
    if members.size() >= Tuning.PACK_MAX_MEMBERS:
        return false
    if members.has(racer):
        return false
    members.append(racer)
    racer.pack = self
    racer.pack_index = members.size() - 1
    racer.fusion_gain = 0.0
    _detach_timer[racer.id] = 0.0
    return true


func leave(racer: Racer) -> void:
    members.erase(racer)
    racer.pack = null
    racer.pack_index = -1
    racer.fusion_gain = 0.0
    _slots.erase(racer.id)
    _tension.erase(racer.id)
    _detach_timer.erase(racer.id)


func dissolve() -> Array[Racer]:
    var released: Array[Racer] = members.duplicate()
    for member: Racer in members:
        member.pack = null
        member.pack_index = -1
        member.fusion_gain = 0.0
    members.clear()
    return released


func slot_for(racer: Racer) -> Vector2:
    if _slots.has(racer.id):
        return _slots[racer.id]
    return racer.position


func tension_ratio(racer: Racer) -> float:
    return float(_tension.get(racer.id, 0.0))


func velocity() -> Vector2:
    # 以队首速度为基准：后位成员被“拖着走”，而不是大家互相平均速度把队首拖慢
    if anchor != null:
        return anchor.velocity
    return _velocity


func add_shock(amount: float) -> void:
    shock = minf(1.6, shock + amount)


## 每物理帧更新队形。返回本帧散团脱离的成员（由 Race 负责冷却与统计）。
func update(dt: float) -> Array[Racer]:
    shock = maxf(0.0, shock - dt * 1.8)
    if members.size() < 2:
        return []

    # 1. 团方向（前位权重大）
    var heading_sum := Vector2.ZERO
    for i: int in range(members.size()):
        var member: Racer = members[i]
        heading_sum += Vector2.from_angle(member.angle) * (1.0 / (1.0 + float(i)))
    if heading_sum.length_squared() > 0.0001:
        direction = heading_sum.normalized()

    # 2. 排序（带滞回，避免槽位抖动）
    for i: int in range(1, members.size()):
        var front: Racer = members[i - 1]
        var back: Racer = members[i]
        if back.position.dot(direction) > front.position.dot(direction) + 4.0:
            members[i - 1] = back
            members[i] = front

    anchor = members[0]

    # 3. 槽位、朝向对齐
    for i: int in range(members.size()):
        var member: Racer = members[i]
        member.pack_index = i
        var slot := anchor.position - direction * (Tuning.PACK_SPACING * float(i))
        _slots[member.id] = slot
        var influence := 0.30 if i == 0 else 1.0
        var blend := clampf(Tuning.PACK_HEADING_BLEND * dt * influence, 0.0, 1.0)
        member.angle = lerp_angle(member.angle, direction.angle(), blend)
    if members.size() > 0:
        _velocity = anchor.velocity

    # 4. 张力、增益、散团判定
    var lateral_axis := direction.orthogonal()
    var detached: Array[Racer] = []
    # 队首也有少量增益（人数越多越明显），否则融合只对后位有利、整团反而更慢
    if members.size() >= 2:
        var anchor_gain := Tuning.fusion_gain(members.size(), 0, 1.0, 1.0)
        anchor.fusion_gain = lerpf(anchor.fusion_gain, anchor_gain, clampf(8.0 * dt, 0.0, 1.0))
    else:
        anchor.fusion_gain = 0.0
    for i: int in range(1, members.size()):
        var member: Racer = members[i]
        var offset: Vector2 = _slots[member.id] - member.position
        var dist := offset.length()
        var lateral := absf(offset.dot(lateral_axis))
        var closeness := clampf(1.0 - dist / 80.0, 0.0, 1.0)
        var column := clampf(1.0 - lateral / Tuning.PACK_DETACH_LATERAL, 0.0, 1.0)
        var gain := Tuning.fusion_gain(members.size(), i, closeness, column)
        member.fusion_gain = lerpf(member.fusion_gain, gain, clampf(8.0 * dt, 0.0, 1.0))
        _tension[member.id] = clampf(dist / Tuning.PACK_DETACH_DIST, 0.0, 1.5)

        var limit_dist := Tuning.PACK_DETACH_DIST * (1.0 - 0.22 * shock)
        var limit_lateral := Tuning.PACK_DETACH_LATERAL * (1.0 - 0.25 * shock)
        var straining := dist > limit_dist * 0.82 or lateral > limit_lateral * 0.85
        var timer := float(_detach_timer.get(member.id, 0.0))
        if straining:
            timer += dt
        else:
            timer = maxf(0.0, timer - dt * 2.0)
        _detach_timer[member.id] = timer

        var force_detach := dist > limit_dist or lateral > limit_lateral
        var tired_detach := member.stamina < 0.04 and dist > Tuning.PACK_SPACING * 0.8
        var tension_detach := timer > Tuning.PACK_TENSION_TIME
        if force_detach or tension_detach or tired_detach:
            detached.append(member)

    for member: Racer in detached:
        leave(member)
    return detached
