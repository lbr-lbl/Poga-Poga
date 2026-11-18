class_name Tuning
extends RefCounted
## 全局数值表（Single Source of Truth）。
##
## 所有玩法手感参数集中在这里，方便策划调参；禁止在玩法脚本里散落魔法数字。
## 单位：距离 px，速度 px/s，加速度 px/s^2，时间 s，角度 rad。
## 世界尺度：赛道半径约 760px，路宽 230px，史莱姆半径 18px。
##
## 手感基调（v0.3）：鼻涕虫式移动 —— 慢、粘、惯性大；躯体会融合成一坨黏液，
## 真正的“碰撞”发生在眼睛之间。

# ---------------------------------------------------------------- 基础运动（慢速黏滞）
const BASE_MAX_SPEED := 215.0
const BASE_ACCEL := 135.0
const BRAKE_DECEL := 360.0
const TURN_RATE := 1.75
## 侧向抓地很低：转向会滑出去，像黏在糖浆里
const LATERAL_GRIP := 2.3
## 滑行掉速：稳定 5 时 0.34/s，稳定 10 时 0.165/s
const COAST_DRAG_BASE := 0.34
const COAST_DRAG_PER_STABILITY := 0.022
const SPEED_STAT_GAIN := 0.030
const STAMINA_ACCEL_FLOOR := 0.50
## 蠕动节律：加速力有轻微起伏（视觉上躯体也在呼吸）
const GOO_PULSE_RATE := 4.2
const GOO_PULSE_ACCEL := 0.10

# ---------------------------------------------------------------- 耐力
const DRAIN_ACCEL := 0.130
const DRAIN_CAP := 0.022
const REGEN_COAST := 0.33
const REGEN_CAP_COAST := 0.10
const REGEN_BRAKE := 0.060
const REGEN_CAP_BRAKE := 0.010
const LOW_STAMINA_GRIP := 0.55

# ---------------------------------------------------------------- 融合（躯体合并 + 眼睛约束）
## 躯体几乎贴上就会自动融合：视觉上合成一坨，物理上是同一个融合团
const ABSORB_RANGE := 46.0
const ABSORB_SPEED_DIFF := 70.0
const ABSORB_COOLDOWN := 0.70
const ABSORB_MIN_STAMINA := 0.08
## 融合团成员躯体中心间距：小于两倍半径，躯体必然重叠成一坨
const PACK_SPACING := 26.0
const PACK_MAX_MEMBERS := 6
## 纵向弹力软（加速/刹车可在团内换位），横向弹力强（保持纵列）
const PACK_SPRING_LONG := 2.6
const PACK_SPRING_LAT := 5.5
const PACK_DAMPING := 0.35
## 散团阈值按“眼睛/躯体被拉开”的程度计
const PACK_DETACH_DIST := 72.0
const PACK_DETACH_LATERAL := 50.0
const PACK_TENSION_TIME := 0.38
const PACK_HEADING_BLEND := 0.60

## 融合增益：人数（边际递减）× 团内位置（后位更大）× 贴近度 × 纵列度
const GAIN_COUNT_COEF := 0.30
const GAIN_RANK_FLOOR := 0.35
const GAIN_BASE := 0.55
const GAIN_STAMINA_SAVE := 0.32
const GAIN_ACCEL_BONUS := 0.30
const GAIN_SPEED_BONUS := 0.16
const GAIN_STABILITY_PENALTY := 0.32

# ---------------------------------------------------------------- 眼睛（碰撞的真正来源）
## 眼睛在躯体前方多远
const EYE_FORWARD := 10.0
## 两眼中心间距
const EYE_SPACING := 12.0
## 单只眼睛的视觉半径
const EYE_RADIUS := 3.7
## 两只眼睛中心距离小于该值 = 眼睛碰到一起（碰撞）
const EYE_COLLISION_DIST := 6.8
## 同一次眼睛碰撞的冷却
const EYE_COLLISION_COOLDOWN := 0.55
## 团内眼睛撞击后，约束松弛导致的额外张力
const EYE_SHOCK := 0.6

## 形态：加速时两眼靠近、刹车时拉远（倍率）
const EYE_SQUEEZE_ACCEL := 0.22
const EYE_SQUEEZE_BRAKE := 0.30
## 形态：碰撞后的 >< 眯眼与左右晃动时长/幅度
const EYE_SQUINT_TIME := 0.55
const EYE_SQUINT_ANGLE := 0.85
const EYE_SHAKE_AMPLITUDE := 2.4

# ---------------------------------------------------------------- 碰撞惩罚
const COLLISION_SPEED_LOSS := 0.18
const COLLISION_STABILITY_DIP := 1.0
const COLLISION_KNOCKBACK := 70.0
const STABILITY_DIP_ACCEL := 0.55
const STABILITY_DIP_GRIP := 0.60
const STABILITY_DIP_COAST := 1.6

# ---------------------------------------------------------------- 林间小道边缘的叶子
## 叶子的“碰撞半径” = 视觉尺寸 × 该系数
const LEAF_COLLIDER_SCALE := 0.62
const LEAF_COLLISION_SPEED_LOSS := 0.18
const LEAF_COLLISION_STAMINA := 0.06
const LEAF_COLLISION_DIP := 0.9
const LEAF_HIT_COOLDOWN := 0.70
const LEAF_BUCKET_SIZE := 64.0

# ---------------------------------------------------------------- 越野惩罚
const OFFROAD_SPEED_MULT := 0.50
const OFFROAD_ACCEL_MULT := 0.60
const OFFROAD_EXTRA_DRAIN := 0.16
const OFFROAD_DRAG := 0.55

# ---------------------------------------------------------------- AI
const AI_LOOKAHEAD_BASE := 70.0
const AI_LOOKAHEAD_PER_SPEED := 0.42
const AI_STEER_GAIN := 2.4
const AI_PATIENCE_LEAD_DRAIN := 0.18
const AI_PATIENCE_FOLLOW_REGEN := 0.45
const AI_GIVE_WAY_TIME := 0.9
const AI_LOW_STAMINA := 0.12
const AI_COMFORT_STAMINA := 0.35
const AI_SPRINT_PROGRESS := 0.82
const AI_CORNER_SLOWDOWN := 0.55

## AI 三档难度：速度 / 失误倍率 / 弯道刹车 / 耐心 / 融合倾向 / 属性加成
const AI_TIER_SPEED: Array[float] = [0.85, 1.0, 1.08]
const AI_TIER_MISTAKE: Array[float] = [2.4, 1.0, 0.35]
const AI_TIER_BRAKE: Array[float] = [0.65, 1.0, 1.25]
const AI_TIER_PATIENCE: Array[float] = [1.25, 1.0, 0.85]
const AI_TIER_FUSE: Array[float] = [0.75, 1.0, 1.2]
const AI_TIER_STATS: Array[float] = [0.0, 0.30, 0.60]

# ---------------------------------------------------------------- 赛道
const TRACK_SAMPLE_COUNT := 1200
const START_GRID_OFFSET := 28.0
const START_GRID_SPACING := 40.0
const CHECKPOINT_RATIO: Array[float] = [0.30, 0.60, 0.88]

# ---------------------------------------------------------------- 镜头（随朝向旋转）
const CAMERA_BASE_ZOOM := 1.38
const CAMERA_FAST_ZOOM := 1.12
const CAMERA_ZOOM_LERP := 2.2
const CAMERA_FOLLOW_LERP := 5.0
const CAMERA_SPEED_LOOKAHEAD := 0.20
const CAMERA_PACK_ZOOM_STEP := 0.028
const SLIME_RADIUS := 18.0
const COUNTDOWN_TIME := 3.2
const FINISH_HOLD_TIME := 1.0

# ---------------------------------------------------------------- 配色（纯黑白灰）
const COLOR_BG := Color("0a0a0a")
const COLOR_ROAD := Color("b4b4b4")
const COLOR_ROAD_EDGE := Color("e9e9e9")
const COLOR_ROAD_DARK := Color("8c8c8c")
const COLOR_FOREST := Color("0c0c0c")
const COLOR_FOREST_ALT := Color("151515")
const COLOR_FOREST_HI := Color("242424")
const COLOR_LEAF_FILL := Color("101010")
const COLOR_LEAF_OUTLINE := Color("cfcfcf")
const COLOR_HELPER := Color("d8d8d8")
const COLOR_DANGER := Color("c9c9c9")
const COLOR_TEXT := Color("ececec")
const COLOR_TEXT_DIM := Color("9a9a9a")
const COLOR_ACCENT := Color("ffffff")
const COLOR_PANEL := Color(0.04, 0.04, 0.04, 0.92)
const COLOR_BAR_BG := Color("1e1e1e")
const COLOR_BAR_CAP := Color("4a4a4a")
const COLOR_BAR_FILL := Color("dedede")
const COLOR_BAR_LOW := Color("b8b8b8")
const COLOR_BLOB_BODY := Color("121212")
const COLOR_BLOB_TINT := Color("8a8a8a")
const COLOR_BLOB_RIM := Color("bdbdbd")
const COLOR_EYE := Color("f2f2f2")
const COLOR_PUPIL := Color("0d0d0d")


## 一条史莱姆的基础属性 -> 派生系数。属性范围 5..10。
static func speed_mult(stats: Dictionary) -> float:
	return 1.0 + (float(stats.get("speed", 5.0)) - 5.0) * SPEED_STAT_GAIN


static func stamina_mult(stats: Dictionary) -> float:
	return 1.0 + (float(stats.get("stamina", 5.0)) - 5.0) * 0.075


static func coast_drag(stats: Dictionary) -> float:
	var stability := float(stats.get("stability", 5.0))
	return maxf(0.12, COAST_DRAG_BASE - (stability - 5.0) * COAST_DRAG_PER_STABILITY)


## 融合增益（0..1）：人数边际递减 × 团内位置 × 贴近度 × 纵列度。
static func fusion_gain(count: int, rank: int, closeness: float, column: float) -> float:
	if count < 2:
		return 0.0
	var count_factor := 1.0 + GAIN_COUNT_COEF * log(float(count)) / log(2.0)
	var rank_factor := GAIN_RANK_FLOOR
	if count > 1:
		rank_factor = GAIN_RANK_FLOOR + (1.0 - GAIN_RANK_FLOOR) * float(rank) / float(count - 1)
	var gain := GAIN_BASE * count_factor * rank_factor * clampf(closeness, 0.0, 1.0) * clampf(column, 0.0, 1.0)
	return clampf(gain, 0.0, 1.0)


## 排名颜色（结算用）
static func rank_color(rank: int) -> Color:
	if rank == 1:
		return COLOR_ACCENT
	return COLOR_TEXT_DIM