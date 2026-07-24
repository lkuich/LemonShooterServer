class_name LemonServerConfig
extends RefCounted

const DEFAULT_DIRECTORY_URL := "https://lemonshooter-web-staging.loren-jk3.workers.dev/api/v1"

static func defaults() -> Dictionary:
	return {
		"server_name": "LemonShooter Dedicated",
		"port": 7000,
		"region": "auto",
		"public": true,
		"capacity": 16,
		"minimum_humans": 1,
		"countdown_seconds": 20,
		"result_seconds": 10,
		"late_join": true,
		"bot_difficulty": "normal",
		"directory_url": DEFAULT_DIRECTORY_URL,
		"packs": [],
		"rotation": []
	}

static func load_settings(path: String) -> Dictionary:
	var settings := defaults()
	var resolved_path := resolve_path(path)
	if FileAccess.file_exists(resolved_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(resolved_path))
		if parsed is Dictionary:
			settings.merge(parsed, true)
	settings["server_name"] = str(settings["server_name"]).strip_edges().left(48)
	settings["port"] = clampi(int(settings["port"]), 1, 65535)
	settings["minimum_humans"] = clampi(int(settings["minimum_humans"]), 1, 16)
	settings["countdown_seconds"] = clampi(int(settings["countdown_seconds"]), 3, 300)
	settings["result_seconds"] = clampi(int(settings["result_seconds"]), 3, 60)
	settings["capacity"] = 16
	return settings

static func resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	var current_directory := DirAccess.open(".")
	if current_directory:
		return current_directory.get_current_dir().path_join(path)
	return path

static func apply_cli_overrides(settings: Dictionary, arguments: PackedStringArray) -> void:
	var port_text := argument_value(arguments, "--port", "")
	if port_text.is_valid_int():
		settings["port"] = clampi(int(port_text), 1, 65535)
	var server_name := argument_value(arguments, "--name", "")
	if not server_name.is_empty():
		settings["server_name"] = server_name.strip_edges().left(48)
	if has_argument(arguments, "--private"):
		settings["public"] = false

static func has_argument(arguments: PackedStringArray, key: String) -> bool:
	for argument in arguments:
		if argument == key or argument.begins_with(key + "="):
			return true
	return false

static func argument_value(arguments: PackedStringArray, key: String, fallback: String) -> String:
	for index in arguments.size():
		var argument := arguments[index]
		if argument.begins_with(key + "="):
			return argument.substr(key.length() + 1)
		if argument == key and index + 1 < arguments.size():
			return arguments[index + 1]
	return fallback
