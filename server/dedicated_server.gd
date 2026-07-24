extends Node

signal status_changed(message: String)

const ServerConfig = preload("res://server/server_config.gd")
const DEFAULT_CONFIG_PATH := "res://server/server.cfg"
const DEDICATED_HOST_SCENE := "res://server/dedicated_host.tscn"

var active := false
var settings: Dictionary = {}
var rotation: Array[Dictionary] = []
var rotation_index := 0
var countdown_remaining := -1.0
var empty_match_remaining := -1.0
var result_remaining := -1.0
var match_completed := false
var smoke_match := false

func _ready() -> void:
	var arguments := OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	active = OS.has_feature("dedicated_server") or _has_argument(arguments, "--server-config")
	if not active:
		return
	settings = _load_settings(_argument_value(arguments, "--server-config", DEFAULT_CONFIG_PATH))
	_apply_cli_overrides(arguments)
	if not _activate_fixed_pack_set():
		get_tree().quit(2)
		return
	rotation = _sanitize_rotation(settings.get("rotation", []))
	rotation_index = 0
	_apply_rotation_entry()
	var options := {
		"name": settings["server_name"],
		"port": settings["port"],
		"region": settings["region"],
		"public": settings["public"],
		"late_join": settings["late_join"]
	}
	if not NetworkSession.host_dedicated(options, NetworkSession.config):
		push_error(NetworkSession.last_error)
		get_tree().quit(3)
		return
	get_tree().call_deferred("change_scene_to_file", DEDICATED_HOST_SCENE)
	set_process(true)
	_announce("Dedicated server ready on UDP %d with content set %s." % [settings["port"], ContentRegistry.get_content_set_hash()])
	smoke_match = _has_argument(arguments, "--smoke-match")
	if smoke_match:
		call_deferred("_run_match_smoke", _argument_value(arguments, "--smoke-map", str(NetworkSession.config["map"])))

func _process(delta: float) -> void:
	if not active:
		return
	if NetworkSession.phase == "lobby":
		_process_lobby(delta)
	elif NetworkSession.phase == "match":
		_process_match(delta)

func _process_lobby(delta: float) -> void:
	empty_match_remaining = -1.0
	var human_count := NetworkSession.get_human_count()
	if human_count < int(settings["minimum_humans"]):
		if countdown_remaining >= 0.0:
			_announce("Countdown cancelled; waiting for %d human player(s)." % int(settings["minimum_humans"]))
		countdown_remaining = -1.0
		return
	if countdown_remaining < 0.0:
		countdown_remaining = float(settings["countdown_seconds"])
		_announce("Match starts in %d seconds." % int(ceil(countdown_remaining)))
	countdown_remaining -= delta
	if countdown_remaining <= 0.0:
		countdown_remaining = -1.0
		NetworkSession.force_start_match()

func _process_match(delta: float) -> void:
	countdown_remaining = -1.0
	if NetworkSession.get_human_count() > 0:
		empty_match_remaining = -1.0
		return
	if empty_match_remaining < 0.0:
		empty_match_remaining = 30.0
		_announce("Server is empty; abandoning the match in 30 seconds.")
	empty_match_remaining -= delta
	if empty_match_remaining <= 0.0:
		empty_match_remaining = -1.0
		_abandon_empty_match()

func notify_match_completed(_winner_key: int) -> void:
	if not active or match_completed:
		return
	match_completed = true
	result_remaining = float(settings["result_seconds"])
	_announce("Match complete; returning to the lobby in %d seconds." % int(settings["result_seconds"]))
	get_tree().create_timer(result_remaining).timeout.connect(_return_after_result)

func _return_after_result() -> void:
	if active and NetworkSession.is_host and NetworkSession.phase == "match":
		result_remaining = -1.0
		match_completed = false
		NetworkSession.return_everyone_to_lobby()
		rotation_index = (rotation_index + 1) % rotation.size()
		_apply_rotation_entry()

func _abandon_empty_match() -> void:
	if not active or NetworkSession.phase != "match":
		return
	match_completed = false
	result_remaining = -1.0
	NetworkSession.return_everyone_to_lobby()
	_announce("Empty match abandoned; rotation position retained.")

func _run_match_smoke(map_id: String) -> void:
	await get_tree().process_frame
	var smoke_config := NetworkSession.config.duplicate(true)
	smoke_config["map"] = map_id
	smoke_config["mode"] = "ffa"
	NetworkSession.config = NetworkSession._sanitize_config(smoke_config)
	if str(NetworkSession.config["map"]) != map_id:
		push_error("Dedicated match smoke rejected map '%s'." % map_id)
		get_tree().quit(4)
		return
	NetworkSession.players[900000] = {
		"entity_id": 900000,
		"peer_id": 2147483646,
		"local_index": 0,
		"name": "PACKAGE_SMOKE",
		"model_id": "soldier",
		"team": 900000,
		"ready": true
	}
	NetworkSession.phase = "match"
	get_tree().change_scene_to_file(NetworkSession.MATCH_SCENE)
	await get_tree().scene_changed
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if not scene or scene.scene_file_path != NetworkSession.MATCH_SCENE or not scene.has_method("_send_local_state"):
		push_error("Dedicated match smoke did not enter the match scene.")
		get_tree().quit(4)
		return
	_announce("Match smoke passed for %s with %d combatant(s)." % [
		map_id,
		get_tree().get_nodes_in_group("combatants").size()
	])
	get_tree().change_scene_to_file(DEDICATED_HOST_SCENE)
	await get_tree().scene_changed
	await get_tree().process_frame
	get_tree().quit(0)

func _apply_rotation_entry() -> void:
	if rotation.is_empty():
		return
	NetworkSession.config = NetworkSession._sanitize_config(rotation[rotation_index])
	NetworkSession.late_join_enabled = settings["late_join"]
	NetworkSession._emit_lobby()
	_announce("Rotation %d/%d: %s on %s." % [
		rotation_index + 1,
		rotation.size(),
		str(NetworkSession.config["mode"]).to_upper(),
		str(ContentRegistry.resolve_map(NetworkSession.config["map"]).get("name", NetworkSession.config["map"]))
	])

func _load_settings(path: String) -> Dictionary:
	return ServerConfig.load_settings(path)

func _apply_cli_overrides(arguments: PackedStringArray) -> void:
	ServerConfig.apply_cli_overrides(settings, arguments)

func _sanitize_rotation(raw_rotation: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_rotation is Array:
		for entry in raw_rotation:
			if entry is Dictionary:
				var merged: Dictionary = entry.duplicate(true)
				merged["bot_difficulty"] = merged.get("bot_difficulty", settings["bot_difficulty"])
				result.append(NetworkSession._sanitize_config(merged))
	if result.is_empty():
		result.append(NetworkSession._sanitize_config({
			"map": "training_arena",
			"mode": "ffa",
			"score_limit": 200,
			"time_limit": 10,
			"bot_count": 6,
			"bot_difficulty": settings["bot_difficulty"]
		}))
	return result

func _activate_fixed_pack_set() -> bool:
	var raw_packs = settings.get("packs", [])
	if raw_packs is not Array:
		push_error("Dedicated pack configuration must be an array.")
		return false
	var descriptor_report := ContentRegistry.validate_pack_descriptors(raw_packs)
	if not raw_packs.is_empty() and not descriptor_report.get("ok", false):
		push_error("Invalid pack descriptors: %s" % ", ".join(descriptor_report.get("errors", [])))
		return false
	for descriptor in raw_packs:
		var pack_path := str(descriptor.get("path", ""))
		if pack_path.is_empty():
			pack_path = ContentRegistry.cached_pack_path(str(descriptor.get("sha256", "")))
		var report := ContentRegistry.activate_pack(pack_path, descriptor)
		if not report.get("ok", false):
			push_error("Pack '%s' failed validation: %s" % [descriptor.get("id", ""), ", ".join(report.get("errors", []))])
			return false
	return true

func _has_argument(arguments: PackedStringArray, key: String) -> bool:
	return ServerConfig.has_argument(arguments, key)

func _argument_value(arguments: PackedStringArray, key: String, fallback: String) -> String:
	return ServerConfig.argument_value(arguments, key, fallback)

func _announce(message: String) -> void:
	print("[dedicated] %s" % message)
	status_changed.emit(message)
