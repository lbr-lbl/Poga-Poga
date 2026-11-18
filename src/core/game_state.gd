extends Node
## 全局存档与元数据（autoload：GameState）。
##
## 职责边界：
## - 只保存跨场景长期数据：车手等级/经验、属性等级、AI 难度选择、解锁进度、最佳成绩。
## - 不保存任何单局比赛状态（比赛状态属于 Race，重开即销毁）。
## - 提供“关卡结算 -> 经验 -> 升级 -> 存档”的唯一入口，避免各界面各写一份公式。
##
## v0.4 变更：取消“点数购买”，改为经验升级。
## - 每场比赛按「排名系数 × AI 难度加成 × 关卡难度」获得经验；
## - 经验满则升 1 级，升级所需经验随等级递增（80 + 30 × 当前等级）；
## - 每升 1 级获得 1 点自由加点；三项属性“等级”从 0 开始（0/5），重置直接回到 0 级。

const SAVE_PATH := "user://poga_profile.cfg"
const SAVE_VERSION := 3

## 属性：数值等级 0..5，最终属性 = 基础 5 + 等级（有效范围 5..10）。
const STAT_BASE := 5
const STAT_MAX_LEVEL := 5
const STAT_KEYS: Array[String] = ["stamina", "speed", "stability"]
const STAT_NAMES := {"stamina": "耐力", "speed": "速度", "stability": "稳定"}

## 车手等级：0 级起步，最高 10 级（共 10 点加点）。
const LEVEL_MAX := 10
const XP_BASE := 80
const XP_GROWTH := 30

## 经验奖励公式（唯一入口见 register_result）。
const BASE_XP := 70
const RANK_XP_COEF: Array[float] = [1.0, 0.65, 0.45, 0.30, 0.20, 0.12]
const LEVEL_XP_COEF: Array[float] = [1.0, 1.35, 1.7]
## AI 三档难度：经验加成 + 显示名（0 简单 / 1 普通 / 2 困难）。
const AI_TIER_NAMES: Array[String] = ["简单", "普通", "困难"]
const AI_TIER_XP_COEF: Array[float] = [1.0, 1.45, 2.0]

var level: int = 0
var xp: int = 0
var alloc: Dictionary = {"stamina": 0, "speed": 0, "stability": 0}

## 已解锁关卡数量（1 表示只解锁第一关）。
var unlocked_levels: int = 1
var best_times: Array = [0.0, 0.0, 0.0]
var best_ranks: Array = [0, 0, 0]
var total_races: int = 0
var total_wins: int = 0
## 玩家选择的 AI 难度（0/1/2），影响对手强度与经验加成。
var selected_tier: int = 1
## 自动化测试/截图模式关闭写盘，避免污染玩家存档。
var persistence_enabled: bool = true

## 最新一局结算数据，供结算界面读取（不持久化）。
var last_result: Dictionary = {}


func _ready() -> void:
	load_profile()


# ------------------------------------------------------------------ 经验 / 等级

func xp_to_next() -> int:
	if level >= LEVEL_MAX:
		return 0
	return XP_BASE + XP_GROWTH * level


func xp_progress() -> float:
	if level >= LEVEL_MAX:
		return 1.0
	var need := xp_to_next()
	if need <= 0:
		return 1.0
	return clampf(float(xp) / float(need), 0.0, 1.0)


func total_points_earned() -> int:
	return level


func points_spent() -> int:
	var total := 0
	for key: String in STAT_KEYS:
		total += int(alloc.get(key, 0))
	return total


func available_points() -> int:
	return maxi(0, total_points_earned() - points_spent())


func add_xp(amount: int) -> int:
	var gained := maxi(0, amount)
	xp += gained
	var levels_gained := 0
	while level < LEVEL_MAX:
		var need := xp_to_next()
		if need <= 0 or xp < need:
			break
		xp -= need
		level += 1
		levels_gained += 1
	if level >= LEVEL_MAX:
		xp = 0
	return levels_gained


# ------------------------------------------------------------------ 属性

func stat_level(key: String) -> int:
	return clampi(int(alloc.get(key, 0)), 0, STAT_MAX_LEVEL)


func stat_value(key: String) -> int:
	return STAT_BASE + stat_level(key)


func player_stats() -> Dictionary:
	return {
		"stamina": float(stat_value("stamina")),
		"speed": float(stat_value("speed")),
		"stability": float(stat_value("stability")),
	}


func can_upgrade(key: String) -> bool:
	if available_points() <= 0:
		return false
	return stat_level(key) < STAT_MAX_LEVEL


func upgrade(key: String) -> bool:
	if not can_upgrade(key):
		return false
	alloc[key] = stat_level(key) + 1
	save_profile()
	return true


## 重置等级与加点：回到 0 级、0 经验、三项 0 级（成绩与解锁进度保留）。
func reset_level() -> void:
	level = 0
	xp = 0
	for key: String in STAT_KEYS:
		alloc[key] = 0
	save_profile()


# ------------------------------------------------------------------ 结算

## 关卡结算唯一入口：返回 {xp, level_before, level_after, unlocked_new}。
func register_result(level_index: int, rank: int, total_time: float, won: bool, ai_tier: int = 1) -> Dictionary:
	var level_coef: float = LEVEL_XP_COEF[clampi(level_index, 0, LEVEL_XP_COEF.size() - 1)]
	var rank_coef: float = RANK_XP_COEF[clampi(rank - 1, 0, RANK_XP_COEF.size() - 1)]
	var tier_coef: float = AI_TIER_XP_COEF[clampi(ai_tier, 0, AI_TIER_XP_COEF.size() - 1)]
	var xp_gain := int(round(BASE_XP * level_coef * rank_coef * tier_coef))

	var level_before := level
	var unlocked_new := false
	xp_gain = maxi(xp_gain, 1)
	add_xp(xp_gain)
	total_races += 1
	if won:
		total_wins += 1
		var previous_unlocked := unlocked_levels
		unlocked_levels = maxi(unlocked_levels, mini(level_index + 2, 3))
		unlocked_new = unlocked_levels > previous_unlocked

	if level_index >= 0 and level_index < best_times.size():
		var previous: float = float(best_times[level_index])
		if total_time > 0.0 and (previous <= 0.0 or total_time < previous):
			best_times[level_index] = total_time
		var previous_rank: int = int(best_ranks[level_index])
		if previous_rank <= 0 or rank < previous_rank:
			best_ranks[level_index] = rank

	save_profile()
	return {
		"xp": xp_gain,
		"level_before": level_before,
		"level_after": level,
		"levels_gained": level - level_before,
		"unlocked_new": unlocked_new,
	}


# ------------------------------------------------------------------ 存档

func save_profile() -> void:
	if not persistence_enabled:
		return
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "level", level)
	config.set_value("meta", "xp", xp)
	config.set_value("meta", "unlocked_levels", unlocked_levels)
	config.set_value("meta", "total_races", total_races)
	config.set_value("meta", "total_wins", total_wins)
	config.set_value("meta", "selected_tier", selected_tier)
	for key: String in STAT_KEYS:
		config.set_value("alloc", key, stat_level(key))
	for i: int in range(best_times.size()):
		config.set_value("records", "best_time_%d" % i, float(best_times[i]))
		config.set_value("records", "best_rank_%d" % i, int(best_ranks[i]))
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("存档写入失败: %s" % error_string(err))


func load_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		return
	level = clampi(int(config.get_value("meta", "level", 0)), 0, LEVEL_MAX)
	xp = maxi(0, int(config.get_value("meta", "xp", 0)))
	unlocked_levels = clampi(int(config.get_value("meta", "unlocked_levels", 1)), 1, 3)
	total_races = int(config.get_value("meta", "total_races", 0))
	total_wins = int(config.get_value("meta", "total_wins", 0))
	selected_tier = clampi(int(config.get_value("meta", "selected_tier", 1)), 0, 2)
	for key: String in STAT_KEYS:
		alloc[key] = clampi(int(config.get_value("alloc", key, 0)), 0, STAT_MAX_LEVEL)
	# 旧版本存档没有 level 字段时，按加点总和兜底，避免玩家数据清零
	if not config.has_section_key("meta", "level") and not config.has_section_key("meta", "xp"):
		level = mini(points_spent(), LEVEL_MAX)
	for i: int in range(best_times.size()):
		best_times[i] = float(config.get_value("records", "best_time_%d" % i, 0.0))
		best_ranks[i] = int(config.get_value("records", "best_rank_%d" % i, 0))


func reset_profile() -> void:
	level = 0
	xp = 0
	unlocked_levels = 1
	total_races = 0
	total_wins = 0
	best_times = [0.0, 0.0, 0.0]
	best_ranks = [0, 0, 0]
	for key: String in STAT_KEYS:
		alloc[key] = 0
	save_profile()


func set_selected_tier(tier: int) -> void:
	selected_tier = clampi(tier, 0, 2)
	save_profile()


# ------------------------------------------------------------------ 工具

## 通用格式化：秒 -> mm:ss.cc
static func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.--"
	var minutes := int(seconds) / 60
	var secs := int(seconds) % 60
	var centis := int(round((seconds - floor(seconds)) * 100.0))
	if centis >= 100:
		centis = 99
	return "%02d:%02d.%02d" % [minutes, secs, centis]