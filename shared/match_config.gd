class_name LemonMatchConfig
extends RefCounted

const MODES := ["ffa", "tdm", "juggernaut", "infection", "koth"]
const BOT_DIFFICULTIES := ["easy", "normal", "hard"]
const POWERUP_SPAWN_RATES := ["scarce", "standard", "aggressive", "mayhem"]
const KOTH_VARIANTS := ["ffa", "tdm"]
const TIME_LIMITS := [5, 10, 15, 20]
const DEFAULT_SCORES := {
	"ffa": 200,
	"tdm": 3000,
	"juggernaut": 15,
	"infection": 20,
	"koth": 100
}

static func sanitize(value: Dictionary, map_supports_mode: Callable, max_combatants := 16) -> Dictionary:
	var mode := str(value.get("mode", "ffa"))
	if mode not in MODES:
		mode = "ffa"
	var map_id := str(value.get("map", "training_arena"))
	if not map_supports_mode.call(map_id, mode):
		map_id = "training_arena"
	var difficulty := str(value.get("bot_difficulty", "normal"))
	if difficulty not in BOT_DIFFICULTIES:
		difficulty = "normal"
	var powerup_spawn_rate := str(value.get("powerup_spawn_rate", "standard"))
	if powerup_spawn_rate not in POWERUP_SPAWN_RATES:
		powerup_spawn_rate = "standard"
	var default_score := int(DEFAULT_SCORES.get(mode, 200))
	var score := int(value.get("score_limit", default_score))
	if mode == "tdm":
		score = clampi(int(roundi(float(score) / 500.0) * 500), 500, 10000)
	elif mode == "ffa":
		score = clampi(int(roundi(float(score) / 50.0) * 50), 50, 1000)
	else:
		score = clampi(int(roundi(float(score) / 5.0) * 5), 5, 100)
	var time_limit := int(value.get("time_limit", 10))
	if time_limit not in TIME_LIMITS:
		time_limit = 10
	var koth_variant := str(value.get("koth_variant", "tdm"))
	if koth_variant not in KOTH_VARIANTS:
		koth_variant = "tdm"
	return {
		"mode": mode,
		"map": map_id,
		"score_limit": score,
		"time_limit": time_limit,
		"bot_count": clampi(int(value.get("bot_count", 0)), 0, max_combatants - 1),
		"bot_difficulty": difficulty,
		"powerup_spawn_rate": powerup_spawn_rate,
		"koth_variant": koth_variant
	}

static func uses_teams(value: Dictionary) -> bool:
	var mode := str(value.get("mode", "ffa"))
	return mode == "tdm" or (mode == "koth" and str(value.get("koth_variant", "tdm")) == "tdm")
