extends Node

var bot_map_id := "training_arena"
var game_mode_id := "bots"
var bot_difficulty_id := "normal"
var powerup_spawn_rate_id := "standard"
var ffa_player_count := 5
var tdm_player_count := 16
var tdm_score_limit := 3000
var tdm_time_limit_minutes := 10
var infection_player_count := 50
var koth_player_count := 8
var koth_team_mode := "tdm"

func get_ffa_score_limit() -> int:
	# Scale the point target with the number of simultaneous combatants while
	# preserving the original five-player, twenty-kill match length at 10 points
	# per base kill.
	return clampi(ffa_player_count, 5, 50) * 40
