extends Node

const CombatantNames = preload("res://scripts/combatant_names.gd")
const MatchConfig = preload("res://shared/match_config.gd")

signal lobby_changed(snapshot: Dictionary)
signal connection_failed(message: String)
signal session_ended(message: String)
signal discovery_changed(servers: Array)
signal content_required(descriptors: Array, content_set_hash: String)

const GAME_PORT := 7000
const DISCOVERY_PORT := 7001
const MAX_COMBATANTS := 16
const PROTOCOL_VERSION := 29
const LOBBY_SCENE := "res://lan_lobby.tscn"
const MATCH_SCENE := "res://lan_match.tscn"

var players: Dictionary = {}
var config := {
	"mode": "ffa",
	"map": "training_arena",
	"score_limit": 200,
	"time_limit": 10,
	"bot_count": 0,
	"bot_difficulty": "normal",
	"powerup_spawn_rate": "standard",
	"koth_variant": "tdm"
}
var phase := "offline"
var is_host := false
var is_dedicated_server := false
var game_port := GAME_PORT
var server_name := "LemonShooter Host"
var server_region := "auto"
var public_listing := false
var late_join_enabled := true
var local_profile := {"name": "PLAYER", "team": 0, "model_id": "soldier"}
var local_profiles: Array[Dictionary] = [{"name": "PLAYER", "team": 0, "model_id": "soldier"}]
var last_error := ""
var last_join_endpoint := ""
var _next_entity_id := 1

var _discovery_socket: PacketPeerUDP
var _discovery_timer := 0.0
var _servers_by_key: Dictionary = {}
var _server_expiry: Dictionary = {}

func _ready() -> void:
	_load_profile()
	set_process(true)

func _process(delta: float) -> void:
	_poll_discovery()
	if phase == "browsing":
		_discovery_timer -= delta
		if _discovery_timer <= 0.0:
			_discovery_timer = 1.0
			_send_discovery_query()
		_expire_servers()

func host_session(profiles: Array, requested_config: Dictionary = {}) -> bool:
	leave_session(false)
	last_error = ""
	is_dedicated_server = false
	game_port = GAME_PORT
	public_listing = false
	server_region = "auto"
	local_profiles = _sanitize_profiles(profiles)
	if not _profiles_have_unique_names(local_profiles):
		_fail("Every local player needs a unique name.")
		return false
	local_profile = local_profiles[0]
	server_name = "%s's Match" % str(local_profile["name"])
	config = _sanitize_config(requested_config if not requested_config.is_empty() else config)
	return _create_server_peer(true)

func host_dedicated(options: Dictionary, requested_config: Dictionary) -> bool:
	leave_session(false)
	last_error = ""
	is_dedicated_server = true
	game_port = clampi(int(options.get("port", GAME_PORT)), 1, 65535)
	server_name = _sanitize_server_name(str(options.get("name", "LemonShooter Dedicated")))
	server_region = _sanitize_region(str(options.get("region", "auto")))
	public_listing = options.get("public", true) == true
	late_join_enabled = options.get("late_join", true) == true
	local_profiles.clear()
	players.clear()
	config = _sanitize_config(requested_config)
	return _create_server_peer(false)

func configure_interactive_listing(name: String, listed_publicly: bool, region := "auto") -> void:
	server_name = _sanitize_server_name(name)
	public_listing = listed_publicly
	server_region = _sanitize_region(region)

func _create_server_peer(add_local_profiles: bool) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var peer_capacity := MAX_COMBATANTS - 1 if add_local_profiles else MAX_COMBATANTS
	var result := peer.create_server(game_port, peer_capacity)
	if result != OK:
		_fail("Could not host on UDP port %d (error %d)." % [game_port, result])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	phase = "lobby"
	players.clear()
	_next_entity_id = 1
	if add_local_profiles:
		_add_peer_profiles(1, local_profiles)
	_connect_multiplayer_signals()
	_start_discovery_host()
	_emit_lobby()
	return true

func join_session(endpoint: String, profiles: Array) -> bool:
	leave_session(false)
	last_error = ""
	local_profiles = _sanitize_profiles(profiles)
	local_profile = local_profiles[0]
	last_join_endpoint = endpoint.strip_edges()
	var parsed := _parse_endpoint(endpoint)
	if parsed.is_empty():
		_fail("Enter a valid IPv4 address or host name.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(parsed["host"], parsed["port"])
	if result != OK:
		_fail("Could not start the connection (error %d)." % result)
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	phase = "connecting"
	players.clear()
	_next_entity_id = 1
	_connect_multiplayer_signals()
	return true

func leave_session(change_scene := true, message := "") -> void:
	if is_host and public_listing:
		DirectoryClient.deregister()
	_stop_discovery()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	is_host = false
	is_dedicated_server = false
	phase = "offline"
	if not message.is_empty():
		last_error = message
		session_ended.emit(message)
	if change_scene and get_tree().current_scene and get_tree().current_scene.scene_file_path != LOBBY_SCENE:
		get_tree().change_scene_to_file(LOBBY_SCENE)

func begin_browsing() -> void:
	_stop_discovery()
	phase = "browsing"
	_servers_by_key.clear()
	_server_expiry.clear()
	_discovery_socket = PacketPeerUDP.new()
	_discovery_socket.set_broadcast_enabled(true)
	var result := _discovery_socket.bind(0)
	if result != OK:
		_fail("LAN discovery could not bind a UDP socket.")
		return
	_discovery_timer = 0.0

func stop_browsing() -> void:
	if phase == "browsing":
		phase = "offline"
	_stop_discovery()

func set_ready(ready: bool) -> void:
	if phase != "lobby":
		return
	if is_host:
		_set_player_ready(multiplayer.get_unique_id(), ready)
	else:
		_request_ready.rpc_id(1, ready)

func set_team(team: int) -> void:
	team = clampi(team, 0, 1)
	if is_host:
		_set_player_team(multiplayer.get_unique_id(), team)
	else:
		_request_team.rpc_id(1, team)

func update_config(changes: Dictionary) -> void:
	if not is_host or phase != "lobby":
		return
	var previous_mode := str(config.get("mode", "ffa"))
	var previously_used_teams := _config_uses_teams(config)
	var merged := config.duplicate(true)
	merged.merge(changes, true)
	if changes.has("mode") and str(changes["mode"]) != previous_mode and not changes.has("score_limit"):
		var limits := {"ffa": 200, "tdm": 3000, "juggernaut": 15, "infection": 20, "koth": 100}
		merged["score_limit"] = int(limits.get(str(changes["mode"]), 200))
	config = _sanitize_config(merged)
	if _config_uses_teams(config) and not previously_used_teams:
		_rebalance_teams()
	_clear_ready_states()
	_emit_lobby()

func can_start() -> bool:
	if not is_host or players.is_empty() or phase != "lobby":
		return false
	for record in players.values():
		if not record.get("ready", false):
			return false
	return true

func start_match() -> void:
	if not can_start():
		return
	phase = "match"
	_begin_match.rpc(_snapshot())
	get_tree().change_scene_to_file(MATCH_SCENE)

func force_start_match() -> void:
	if not is_host or phase != "lobby" or players.is_empty():
		return
	phase = "match"
	_begin_match.rpc(_snapshot())
	get_tree().change_scene_to_file(MATCH_SCENE)

func return_everyone_to_lobby() -> void:
	if not is_host:
		return
	phase = "lobby"
	_clear_ready_states()
	_start_discovery_host()
	_return_to_lobby.rpc(_snapshot())
	if is_dedicated_server:
		get_tree().change_scene_to_file("res://root.tscn")
	else:
		get_tree().change_scene_to_file(LOBBY_SCENE)

func get_local_record() -> Dictionary:
	var records := get_local_records()
	return records[0] if not records.is_empty() else {}

func get_local_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var local_peer := multiplayer.get_unique_id()
	for record in players.values():
		if int(record.get("peer_id", 0)) == local_peer:
			result.append(record)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("local_index", 0)) < int(b.get("local_index", 0)))
	return result

func get_owner_peer_id(entity_id: int) -> int:
	return int(players.get(entity_id, {}).get("peer_id", 0))

func peer_owns_entity(peer_id: int, entity_id: int) -> bool:
	return players.has(entity_id) and int(players[entity_id].get("peer_id", 0)) == peer_id

func get_entity_ids_for_peer(peer_id: int) -> Array[int]:
	var result: Array[int] = []
	for entity_id in players:
		if int(players[entity_id].get("peer_id", 0)) == peer_id:
			result.append(int(entity_id))
	result.sort_custom(func(a: int, b: int) -> bool: return int(players[a].get("local_index", 0)) < int(players[b].get("local_index", 0)))
	return result

func get_primary_entity_for_peer(peer_id: int) -> int:
	var ids := get_entity_ids_for_peer(peer_id)
	return ids[0] if not ids.is_empty() else 0

func get_human_count() -> int:
	return players.size()

func get_expected_bot_count() -> int:
	var open_slots := maxi(MAX_COMBATANTS - players.size(), 0)
	if config.get("mode", "ffa") == "infection":
		return open_slots
	var count := mini(int(config.get("bot_count", 0)), open_slots)
	if config.get("mode", "ffa") == "juggernaut" and count == 0 and open_slots > 0:
		return 1
	return count

func uses_teams() -> bool:
	return _config_uses_teams(config)

func _config_uses_teams(value: Dictionary) -> bool:
	return MatchConfig.uses_teams(value)

func _connect_multiplayer_signals() -> void:
	var connected_callable := Callable(self, "_on_connected_to_server")
	if not multiplayer.connected_to_server.is_connected(connected_callable):
		multiplayer.connected_to_server.connect(connected_callable)
	var failed_callable := Callable(self, "_on_connection_failed")
	if not multiplayer.connection_failed.is_connected(failed_callable):
		multiplayer.connection_failed.connect(failed_callable)
	var disconnected_callable := Callable(self, "_on_server_disconnected")
	if not multiplayer.server_disconnected.is_connected(disconnected_callable):
		multiplayer.server_disconnected.connect(disconnected_callable)
	var peer_disconnected_callable := Callable(self, "_on_peer_disconnected")
	if not multiplayer.peer_disconnected.is_connected(peer_disconnected_callable):
		multiplayer.peer_disconnected.connect(peer_disconnected_callable)

func _on_connected_to_server() -> void:
	phase = "lobby"
	var installed_hashes: Array[String] = []
	for descriptor in ContentRegistry.get_pack_descriptors():
		installed_hashes.append(str(descriptor.get("sha256", "")))
	_register_player.rpc_id(1, PROTOCOL_VERSION, ContentRegistry.get_content_set_hash(), installed_hashes, local_profiles)

func _on_connection_failed() -> void:
	_fail("Could not connect to the LAN host.")
	leave_session(false)

func _on_server_disconnected() -> void:
	var message := last_error if not last_error.is_empty() else "Host disconnected."
	leave_session(false, message)
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host:
		return
	var removed := false
	for entity_id in players.keys():
		if int(players[entity_id].get("peer_id", 0)) == peer_id:
			players.erase(entity_id)
			removed = true
	if not removed:
		return
	_emit_lobby()

@rpc("any_peer", "call_remote", "reliable")
func _register_player(protocol: int, content_set_hash: String, _installed_hashes: Array, profiles: Array) -> void:
	if not is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL_VERSION:
		_reject_join.rpc_id(peer_id, "This host uses a different multiplayer protocol version.")
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	if content_set_hash != ContentRegistry.get_content_set_hash():
		_require_content.rpc_id(peer_id, ContentRegistry.get_pack_descriptors(), ContentRegistry.get_content_set_hash())
		return
	if phase == "match" and not late_join_enabled:
		_reject_join.rpc_id(peer_id, "This server does not allow late joining.")
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	var clean_profiles := _sanitize_profiles(profiles)
	if players.size() + clean_profiles.size() > MAX_COMBATANTS:
		_reject_join.rpc_id(peer_id, "The lobby is full.")
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	var incoming_names: Array[String] = []
	for clean in clean_profiles:
		var clean_name := str(clean["name"])
		if _name_in_use(clean_name) or clean_name.to_lower() in incoming_names:
			_reject_join.rpc_id(peer_id, "Every local player needs a unique name.")
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
			return
		incoming_names.append(clean_name.to_lower())
	_add_peer_profiles(peer_id, clean_profiles)
	_emit_lobby()
	if phase == "match":
		_begin_match.rpc_id(peer_id, _snapshot())

@rpc("authority", "call_remote", "reliable")
func _require_content(descriptors: Array, required_hash: String) -> void:
	var validation := ContentRegistry.validate_pack_descriptors(descriptors)
	if not validation.get("ok", false):
		_fail("The server advertised an invalid community content set.")
		return
	content_required.emit(descriptors, required_hash)

@rpc("authority", "call_remote", "reliable")
func _reject_join(message: String) -> void:
	last_error = message
	connection_failed.emit(message)

@rpc("any_peer", "call_remote", "reliable")
func _request_ready(ready: bool) -> void:
	if is_host:
		_set_player_ready(multiplayer.get_remote_sender_id(), ready)

@rpc("any_peer", "call_remote", "reliable")
func _request_team(team: int) -> void:
	if is_host:
		_set_player_team(multiplayer.get_remote_sender_id(), clampi(team, 0, 1))

@rpc("authority", "call_remote", "reliable")
func _sync_lobby(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func _begin_match(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)
	phase = "match"
	get_tree().change_scene_to_file(MATCH_SCENE)

@rpc("authority", "call_remote", "reliable")
func _return_to_lobby(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)
	phase = "lobby"
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _set_player_ready(peer_id: int, ready: bool) -> void:
	for entity_id in players:
		if int(players[entity_id].get("peer_id", 0)) == peer_id:
			players[entity_id]["ready"] = ready
	_emit_lobby()

func _set_player_team(peer_id: int, team: int) -> void:
	if config["mode"] != "tdm":
		return
	for entity_id in players:
		if int(players[entity_id].get("peer_id", 0)) == peer_id:
			players[entity_id]["team"] = team
			players[entity_id]["ready"] = false
	_emit_lobby()

func _balance_new_player(entity_id: int) -> void:
	if config["mode"] != "tdm":
		players[entity_id]["team"] = entity_id
		return
	var counts := [0, 0]
	for id in players:
		if id != entity_id:
			counts[players[id]["team"]] += 1
	players[entity_id]["team"] = 0 if counts[0] <= counts[1] else 1

func _rebalance_teams() -> void:
	var ids := players.keys()
	ids.sort()
	for index in ids.size():
		players[ids[index]]["team"] = index % 2

func _emit_lobby() -> void:
	var snapshot := _snapshot()
	lobby_changed.emit(snapshot)
	if is_host and multiplayer.has_multiplayer_peer():
		_sync_lobby.rpc(snapshot)

func _snapshot() -> Dictionary:
	return {
		"protocol": PROTOCOL_VERSION,
		"phase": phase,
		"players": players.duplicate(true),
		"config": config.duplicate(true),
		"content_set_hash": ContentRegistry.get_content_set_hash(),
		"packs": ContentRegistry.get_pack_descriptors()
	}

func _apply_snapshot(snapshot: Dictionary) -> void:
	players = snapshot.get("players", {}).duplicate(true)
	_next_entity_id = 1
	for entity_id in players.keys():
		_next_entity_id = maxi(_next_entity_id, int(entity_id) + 1)
	config = _sanitize_config(snapshot.get("config", {}))
	phase = snapshot.get("phase", "lobby")
	lobby_changed.emit(_snapshot())

func _new_player_record(entity_id: int, peer_id: int, local_index: int, profile: Dictionary) -> Dictionary:
	return {
		"entity_id": entity_id,
		"peer_id": peer_id,
		"local_index": local_index,
		"name": profile["name"],
		"model_id": profile.get("model_id", "soldier"),
		"team": int(profile.get("team", 0)),
		"ready": false
	}

func _add_peer_profiles(peer_id: int, profiles: Array[Dictionary]) -> void:
	for local_index in profiles.size():
		var entity_id := _allocate_entity_id()
		players[entity_id] = _new_player_record(entity_id, peer_id, local_index, profiles[local_index])
		_balance_new_player(entity_id)

func _allocate_entity_id() -> int:
	while players.has(_next_entity_id):
		_next_entity_id += 1
	var result := _next_entity_id
	_next_entity_id += 1
	return result

func _sanitize_profiles(profiles: Array) -> Array[Dictionary]:
	var clean: Array[Dictionary] = []
	for profile in profiles.slice(0, 4):
		if profile is Dictionary:
			clean.append(_sanitize_profile(profile))
	if clean.is_empty():
		clean.append(_sanitize_profile({"name": "PLAYER"}))
	return clean

func _profiles_have_unique_names(profiles: Array[Dictionary]) -> bool:
	var names: Array[String] = []
	for profile in profiles:
		var normalized := str(profile.get("name", "")).to_lower()
		if normalized in names:
			return false
		names.append(normalized)
	return true

func _sanitize_profile(profile: Dictionary) -> Dictionary:
	var player_name := str(profile.get("name", "PLAYER")).strip_edges()
	player_name = player_name.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	if player_name.is_empty():
		player_name = CombatantNames.random_unique()
	if player_name.length() > 20:
		player_name = player_name.left(20)
	var model_id := str(profile.get("model_id", "soldier"))
	if not ContentRegistry.has_model(model_id) or ContentRegistry.resolve_model(model_id).get("infection_only", false):
		model_id = "soldier"
	return {"name": player_name, "team": clampi(int(profile.get("team", 0)), 0, 1), "model_id": model_id}

func _sanitize_config(value: Dictionary) -> Dictionary:
	return MatchConfig.sanitize(value, _map_supports_mode, MAX_COMBATANTS)

func _map_supports_mode(map_id: String, mode: String) -> bool:
	return ContentRegistry.has_map(map_id) and mode in ContentRegistry.resolve_map(map_id).get("supported_modes", [])

func _clear_ready_states() -> void:
	for peer_id in players:
		players[peer_id]["ready"] = false

func _name_in_use(player_name: String) -> bool:
	for record in players.values():
		if str(record["name"]).nocasecmp_to(player_name) == 0:
			return true
	return false

func _parse_endpoint(endpoint: String) -> Dictionary:
	var text := endpoint.strip_edges()
	if text.is_empty():
		return {}
	var host := text
	var port := game_port
	var separator := text.rfind(":")
	if separator > 0 and text.find(":") == separator:
		host = text.left(separator)
		var port_text := text.substr(separator + 1)
		if not port_text.is_valid_int():
			return {}
		port = int(port_text)
	if host.is_empty() or port < 1 or port > 65535:
		return {}
	return {"host": host, "port": port}

func _load_profile() -> void:
	var file := ConfigFile.new()
	if file.load("user://lan_profile.cfg") == OK:
		local_profile = _sanitize_profile({
			"name": file.get_value("player", "name", "PLAYER"),
			"model_id": file.get_value("player", "model_id", "soldier")
		})
	if str(local_profile.get("name", "")).to_upper() == "PLAYER":
		local_profile["name"] = CombatantNames.random_unique()
	local_profiles = [local_profile.duplicate(true)]

func _save_profile() -> void:
	var file := ConfigFile.new()
	file.set_value("player", "name", local_profile["name"])
	file.set_value("player", "model_id", local_profile.get("model_id", "soldier"))
	file.save("user://lan_profile.cfg")

func _start_discovery_host() -> void:
	_stop_discovery()
	_discovery_socket = PacketPeerUDP.new()
	if _discovery_socket.bind(DISCOVERY_PORT) != OK:
		_discovery_socket = null

func _stop_discovery() -> void:
	if _discovery_socket:
		_discovery_socket.close()
	_discovery_socket = null

func _send_discovery_query() -> void:
	if not _discovery_socket:
		return
	_discovery_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_discovery_socket.put_packet(JSON.stringify({"kind": "lemon_query", "protocol": PROTOCOL_VERSION}).to_utf8_buffer())

func _poll_discovery() -> void:
	if not _discovery_socket:
		return
	while _discovery_socket.get_available_packet_count() > 0:
		var packet := _discovery_socket.get_packet()
		var source_ip := _discovery_socket.get_packet_ip()
		var source_port := _discovery_socket.get_packet_port()
		var parsed = JSON.parse_string(packet.get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		if is_host and parsed.get("kind") == "lemon_query":
			var response := get_server_metadata()
			response["kind"] = "lemon_host"
			_discovery_socket.set_dest_address(source_ip, source_port)
			_discovery_socket.put_packet(JSON.stringify(response).to_utf8_buffer())
		elif phase == "browsing" and parsed.get("kind") == "lemon_host" and int(parsed.get("protocol", -1)) == PROTOCOL_VERSION:
			parsed["address"] = source_ip
			var key := "%s:%d" % [source_ip, int(parsed.get("port", GAME_PORT))]
			_servers_by_key[key] = parsed
			_server_expiry[key] = Time.get_ticks_msec() + 3500
			discovery_changed.emit(_servers_by_key.values())

func _expire_servers() -> void:
	var changed := false
	var now := Time.get_ticks_msec()
	for key in _server_expiry.keys():
		if _server_expiry[key] < now:
			_server_expiry.erase(key)
			_servers_by_key.erase(key)
			changed = true
	if changed:
		discovery_changed.emit(_servers_by_key.values())

func _fail(message: String) -> void:
	last_error = message
	connection_failed.emit(message)

func get_server_metadata() -> Dictionary:
	var map_definition := ContentRegistry.resolve_map(str(config.get("map", "training_arena")))
	return {
		"protocol": PROTOCOL_VERSION,
		"name": server_name,
		"type": "dedicated" if is_dedicated_server else "player",
		"region": server_region,
		"port": game_port,
		"phase": phase,
		"mode": str(config.get("mode", "ffa")),
		"mode_label": str(config.get("mode", "ffa")).replace("_", " ").to_upper(),
		"map": str(config.get("map", "training_arena")),
		"map_label": str(map_definition.get("name", config.get("map", "Training Arena"))),
		"humans": get_human_count(),
		"bots": get_expected_bot_count(),
		"capacity": MAX_COMBATANTS,
		"modded": ContentRegistry.is_modded(),
		"content_set_hash": ContentRegistry.get_content_set_hash(),
		"packs": ContentRegistry.get_pack_descriptors()
	}

func _sanitize_server_name(value: String) -> String:
	var clean := value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	if clean.is_empty():
		clean = "LemonShooter Server"
	return clean.left(48)

func _sanitize_region(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized not in ["auto", "na-west", "na-east", "eu", "asia", "oceania", "south-america"]:
		return "auto"
	return normalized
