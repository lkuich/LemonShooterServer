extends "res://shared/match_runtime.gd"

const NetworkAvatar = preload("res://scripts/network_avatar.gd")
const GrenadeProjectile = preload("res://scripts/grenade_projectile.gd")
const ThrowingAxe = preload("res://scripts/throwing_axe.gd")
const CombatRules = preload("res://shared/combat_rules.gd")
const SuicideVestCharge = preload("res://scripts/suicide_vest_charge.gd")
const PortalManager = preload("res://scripts/portal_manager.gd")
const ForceImpactDamage = preload("res://scripts/force_impact_damage.gd")

const MATCH_COMMUNICATIONS_PATH := "res://scripts/match_communications.gd"
const SPLIT_SCREEN_MANAGER_PATH := "res://scripts/split_screen_manager.gd"

var entities: Dictionary = {}
var local_player: CharacterBody3D
var local_players: Array[CharacterBody3D] = []
var local_players_by_entity: Dictionary = {}
var match_scores: Dictionary = {}
var remaining_time := 600.0
var snapshot_timer := 0.0
var input_timer := 0.0
var bot_serial := 1000
var result_pending := false
var projectile_serial := 1
var pickup_serial := 1
var network_pickups: Dictionary = {}
var killstreaks: Dictionary = {}
var streak_inventories: Dictionary = {}
var vehicle_serial := 1
var vehicle_ids: Dictionary = {}
var client_vehicles: Dictionary = {}
var timer_label: Label
var server_weapon_by_peer: Dictionary = {}
var server_shot_time: Dictionary = {}
var server_shot_serial: Dictionary = {}
var server_collateral_state: Dictionary = {}
var server_grenades: Dictionary = {}
var server_axes: Dictionary = {}
var server_throw_time: Dictionary = {}
var hud_last_streak := -1
var hud_best_streak := 0
var hud_last_perks: Array[String] = []
var local_death_feedback_active := false
var lan_juggernaut_id := 0
var lan_hill_scores := Vector2.ZERO
var network_attack_dogs: Dictionary = {}
var remote_bot_portal_managers: Dictionary = {}
var remote_player_portal_managers: Dictionary = {}
var server_player_portals: Dictionary = {}
var match_communications: CanvasLayer
var split_screen_manager: Control
var inventory_menus: Dictionary = {}
var server_physics_utilities: Dictionary = {}
var server_ground_pound_times: Dictionary = {}
var server_respawns_pending: Dictionary = {}
var server_respawn_skip_requests: Dictionary = {}

func _ready() -> void:
	if NetworkSession.phase != "match" or NetworkSession.players.is_empty():
		get_tree().call_deferred("change_scene_to_file", "res://lan_lobby.tscn")
		return
	GameSession.bot_map_id = NetworkSession.config["map"]
	GameSession.game_mode_id = NetworkSession.config["mode"]
	GameSession.bot_difficulty_id = NetworkSession.config["bot_difficulty"]
	GameSession.powerup_spawn_rate_id = str(NetworkSession.config.get("powerup_spawn_rate", "standard"))
	GameSession.koth_team_mode = str(NetworkSession.config.get("koth_variant", "tdm"))
	_configure_special_mode()
	score_target = NetworkSession.config["score_limit"]
	remaining_time = float(NetworkSession.config["time_limit"]) * 60.0
	if not NetworkSession.is_dedicated_server:
		_ensure_audio_buses()
	_build_world()
	_build_arena()
	_build_waypoints()
	NetworkSession.lobby_changed.connect(_on_session_roster_changed)
	if not NetworkSession.is_dedicated_server:
		Input.joy_connection_changed.connect(_on_split_joy_connection_changed)
	_spawn_network_humans()
	if not NetworkSession.is_dedicated_server:
		_assign_local_input_devices()
	if multiplayer.is_server():
		_spawn_server_bots()
		if NetworkSession.config["map"] not in ["highrise", "suburban_test_site"] and not (infection_mode and NetworkSession.config["map"] == "city"):
			call_deferred("_spawn_initial_vehicles")
		jetpack_spawn_timer = _powerup_interval(18.0, 35.0)
		coil_gun_spawn_timer = _powerup_interval(28.0, 50.0)
		suicide_vest_spawn_timer = _powerup_interval(35.0, 65.0)
		physics_pickup_timers = {
			"ricochet": _powerup_interval(20.0, 35.0),
			"force": _powerup_interval(32.0, 50.0),
			"gravity_bomb": _powerup_interval(26.0, 44.0),
			"sticky_bomb": _powerup_interval(34.0, 52.0)
		}
	if not NetworkSession.is_dedicated_server:
		_build_match_hud()
		_build_split_screen()
		_build_match_communications()
	_spawn_mystery_box()
	_initialize_lan_special_mode()
	if not NetworkSession.is_dedicated_server:
		_update_lan_leaderboard()
		_start_music()
	_begin_lan_loadout_intermission()

func _build_split_screen() -> void:
	if local_players.is_empty():
		return
	var split_screen_script = load(SPLIT_SCREEN_MANAGER_PATH)
	split_screen_manager = split_screen_script.new()
	split_screen_manager.name = "SplitScreen"
	add_child(split_screen_manager)
	split_screen_manager.setup(local_players, get_world_3d())
	if local_players.size() > 1:
		for index in local_players.size():
			var menu: CanvasLayer = inventory_menus.get(local_players[index].entity_id)
			if menu:
				split_screen_manager.attach_player_ui(index, menu)
	if local_players.size() > 1 and combat_hud:
		combat_hud.set_player_status_visible(false)
		combat_hud.set_player_damage_visible(false)

func _process(delta: float) -> void:
	if loadout_intermission_active:
		_update_lan_loadout_intermission(delta)
		return
	if combat_hud and local_player and combat_hud.is_leaderboard_visible():
		_update_lan_leaderboard()
	if not match_active:
		return
	remaining_time = maxf(remaining_time - delta, 0.0)
	input_timer -= delta
	if input_timer <= 0.0:
		input_timer = 0.05
		_send_local_state()
		_send_vehicle_input()
	if multiplayer.is_server():
		_update_lan_special_mode(delta)
		_update_server_pickups(delta)
		_update_server_physics_utilities(delta)
		_register_server_vehicles()
		snapshot_timer -= delta
		if snapshot_timer <= 0.0:
			snapshot_timer = 0.05
			_publish_snapshot()
		if remaining_time <= 0.0 and not sudden_death:
			_resolve_time_limit()
	_update_match_hud()

func _initialize_lan_special_mode() -> void:
	if king_mode:
		_build_hill_placeholder()
		if multiplayer.is_server():
			_move_lan_hill(true)
	elif juggernaut_mode and multiplayer.is_server():
		var ids := entities.keys()
		ids.sort()
		if not ids.is_empty():
			_set_lan_juggernaut(int(ids[0]))
	elif infection_mode and multiplayer.is_server():
		for entity in entities.values():
			entity.team_id = 0
			if entity.has_method("set_mode_infected"):
				entity.set_mode_infected(false)
		var bot_candidates: Array[int] = []
		var human_candidates: Array[int] = []
		for raw_id in entities.keys():
			var entity_id := int(raw_id)
			if entity_id >= 1000:
				bot_candidates.append(entity_id)
			else:
				human_candidates.append(entity_id)
		bot_candidates.sort()
		human_candidates.sort()
		var candidates: Array[int] = bot_candidates + human_candidates
		var seed_count := mini(2, maxi(entities.size() - 1, 1))
		for index in mini(seed_count, candidates.size()):
			_set_lan_infected(candidates[index])

func _update_lan_special_mode(delta: float) -> void:
	if king_mode:
		_update_lan_hill(delta)
	elif infection_mode:
		if _lan_survivor_count() == 0:
			_finish_match(1)

func _move_lan_hill(initial := false) -> void:
	if waypoints.is_empty():
		return
	var candidates := _hill_candidates(initial)
	hill_position = (candidates if not candidates.is_empty() else waypoints).pick_random()
	hill_move_timer = HILL_MOVE_INTERVAL
	if hill_root:
		hill_root.position = hill_position - Vector3.UP * 0.92
	for bot in bots:
		bot.set_objective(hill_position, true)
	if combat_hud:
		combat_hud.show_notification("THE HILL %s" % ("IS ACTIVE" if initial else "HAS MOVED"), 3.0)

func _update_lan_hill(delta: float) -> void:
	hill_move_timer -= delta
	if hill_move_timer <= 0.0:
		_move_lan_hill()
	if team_deathmatch:
		var occupancy := [0, 0]
		for entity in entities.values():
			if entity.alive and entity.team_id in [0, 1] and _inside_hill(entity.global_position):
				occupancy[entity.team_id] += 1
		var controlling_team := -1
		if occupancy[0] > 0 and occupancy[1] == 0:
			controlling_team = 0
		elif occupancy[1] > 0 and occupancy[0] == 0:
			controlling_team = 1
		if controlling_team == 0:
			lan_hill_scores.x += delta
			match_scores[0] = int(lan_hill_scores.x)
		elif controlling_team == 1:
			lan_hill_scores.y += delta
			match_scores[1] = int(lan_hill_scores.y)
		if controlling_team >= 0 and int(match_scores.get(controlling_team, 0)) >= score_target:
			_finish_match(controlling_team)
		elif sudden_death and int(match_scores.get(0, 0)) != int(match_scores.get(1, 0)):
			_finish_match(0 if int(match_scores.get(0, 0)) > int(match_scores.get(1, 0)) else 1)
	else:
		var occupants: Array[int] = []
		for raw_id in entities:
			var entity: Node = entities[raw_id]
			if entity.alive and _inside_hill(entity.global_position):
				occupants.append(int(raw_id))
		if occupants.size() == 1:
			var holder_id := occupants[0]
			match_scores[holder_id] = float(match_scores.get(holder_id, 0.0)) + delta
			if int(match_scores[holder_id]) >= score_target:
				_finish_match(holder_id)
			elif sudden_death:
				var leaders := _leaders()
				if leaders.size() == 1:
					_finish_match(leaders[0])

func _set_lan_juggernaut(entity_id: int) -> void:
	lan_juggernaut_id = entity_id
	for id in entities:
		var entity: Node = entities[id]
		if entity.has_method("set_mode_juggernaut"):
			entity.set_mode_juggernaut(int(id) == entity_id)
	current_juggernaut = entities.get(entity_id)
	if current_juggernaut:
		_update_juggernaut_marker(current_juggernaut)
	_refresh_lan_juggernaut_targets()
	if combat_hud:
		combat_hud.show_notification("%s IS THE JUGGERNAUT" % _entity_display_name(entity_id).to_upper(), 3.0)

func _refresh_lan_juggernaut_targets() -> void:
	var combatants: Array[CharacterBody3D] = []
	for entity in entities.values():
		if entity is CharacterBody3D:
			combatants.append(entity)
	for bot in bots:
		if bot == current_juggernaut:
			bot.set_target_candidates(combatants)
		else:
			var targets: Array[CharacterBody3D] = []
			if current_juggernaut is CharacterBody3D:
				targets.append(current_juggernaut)
			bot.set_target_candidates(targets)
	_append_attack_dog_targets()

func _set_lan_infected(entity_id: int) -> void:
	if not entities.has(entity_id):
		return
	var entity: Node = entities[entity_id]
	entity.team_id = 1
	match_scores[1] = int(match_scores.get(1, 0))
	if entity.has_method("set_mode_infected"):
		entity.set_mode_infected(true)
	_refresh_bot_targets()
	if combat_hud:
		combat_hud.show_notification("%s HAS BEEN INFECTED" % _entity_display_name(entity_id).to_upper(), 3.0)

func _lan_survivor_count() -> int:
	var count := 0
	for entity in entities.values():
		if entity.team_id == 0:
			count += 1
	return count

func _lan_special_state() -> Dictionary:
	return {
		"juggernaut": lan_juggernaut_id,
		"hill_position": hill_position,
		"hill_timer": hill_move_timer,
		"survivors": _lan_survivor_count(),
		"training_props": _training_prop_snapshot(),
		"player_portals": server_player_portals
	}

func _training_prop_snapshot() -> Dictionary:
	var result := {}
	for candidate in get_tree().get_nodes_in_group("training_physics_props"):
		if candidate is RigidBody3D:
			result[candidate.name] = {"transform": candidate.global_transform, "linear_velocity": candidate.linear_velocity, "angular_velocity": candidate.angular_velocity}
	return result

func _apply_lan_special_state(state: Dictionary) -> void:
	_apply_training_prop_snapshot(state.get("training_props", {}))
	_apply_player_portal_snapshot(state.get("player_portals", {}))
	if king_mode:
		hill_position = state.get("hill_position", hill_position)
		hill_move_timer = float(state.get("hill_timer", hill_move_timer))
		if not hill_root:
			_build_hill_placeholder()
		hill_root.position = hill_position - Vector3.UP * 0.92
	elif juggernaut_mode:
		var holder_id := int(state.get("juggernaut", 0))
		if holder_id != lan_juggernaut_id and entities.has(holder_id):
			lan_juggernaut_id = holder_id
			current_juggernaut = entities[holder_id]

func _apply_player_portal_snapshot(states: Dictionary) -> void:
	if multiplayer.is_server():
		return
	for raw_entity_id in states:
		var entity_id := int(raw_entity_id)
		if local_players_by_entity.has(entity_id) or not entities.has(entity_id):
			continue
		var placements: Dictionary = states[raw_entity_id]
		for index in [0, 1]:
			if placements.has(index):
				_show_remote_player_portal(entity_id, index, placements[index])
			elif placements.has(str(index)):
				_show_remote_player_portal(entity_id, index, placements[str(index)])
			elif remote_player_portal_managers.has(entity_id):
				var manager: Node = remote_player_portal_managers[entity_id]
				manager.remove_portal(index)
	for raw_entity_id in remote_player_portal_managers.keys():
		var entity_id := int(raw_entity_id)
		if not states.has(entity_id) and not states.has(str(entity_id)):
			_clear_remote_player_portals(entity_id)

func _apply_training_prop_snapshot(states: Dictionary) -> void:
	if multiplayer.is_server() or states.is_empty():
		return
	for candidate in get_tree().get_nodes_in_group("training_physics_props"):
		if candidate is not RigidBody3D or not states.has(candidate.name):
			continue
		var prop_state: Dictionary = states[candidate.name]
		candidate.global_transform = prop_state.get("transform", candidate.global_transform)
		candidate.linear_velocity = prop_state.get("linear_velocity", Vector3.ZERO)
		candidate.angular_velocity = prop_state.get("angular_velocity", Vector3.ZERO)

func _spawn_network_humans() -> void:
	var ids := NetworkSession.players.keys()
	ids.sort()
	var local_peer := multiplayer.get_unique_id()
	for index in ids.size():
		var entity_id: int = ids[index]
		_spawn_human(entity_id, index, local_peer)

func _spawn_human(entity_id: int, index: int, local_peer: int) -> void:
	if entities.has(entity_id) or not NetworkSession.players.has(entity_id):
		return
	var record: Dictionary = NetworkSession.players[entity_id]
	var owner_peer_id := int(record.get("peer_id", 0))
	var team := entity_id
	if infection_mode:
		team = 0
	elif team_deathmatch:
		team = int(record["team"])
	var spawn := _spawn_for(team, index)
	if owner_peer_id == local_peer:
		var player_controller_script = load(PLAYER_CONTROLLER_PATH)
		var controller = player_controller_script.new()
		controller.name = "LocalPlayer_%d" % int(record.get("local_index", 0))
		controller.display_name = str(record["name"])
		controller.local_player_index = int(record.get("local_index", 0))
		controller.position = spawn
		controller.team_id = team
		controller.lan_peer_id = owner_peer_id
		controller.entity_id = entity_id
		add_child(controller)
		controller.enable_combat_health()
		controller.died.connect(_on_local_player_died.bind(entity_id))
		controller.respawn_skip_requested.connect(_on_local_respawn_skip_requested.bind(entity_id))
		local_players.append(controller)
		local_players_by_entity[entity_id] = controller
		if local_player == null:
			local_player = controller
			player = controller
		entities[entity_id] = controller
	else:
		var avatar := NetworkAvatar.new()
		avatar.setup(entity_id, owner_peer_id, record["name"], team, str(record.get("model_id", "soldier")))
		avatar.position = spawn
		add_child(avatar)
		avatar.died.connect(_on_network_avatar_died)
		entities[entity_id] = avatar
	match_scores[entity_id if not team_deathmatch else team] = int(match_scores.get(entity_id if not team_deathmatch else team, 0))
	killstreaks[entity_id] = 0
	streak_inventories[entity_id] = []
	leaderboard_kills[entity_id] = 0
	leaderboard_deaths[entity_id] = 0
	leaderboard_points[entity_id] = 0
	multi_kill_counts[entity_id] = 0
	multi_kill_deadlines[entity_id] = 0
	server_weapon_by_peer[entity_id] = "ak47"
	server_grenades[entity_id] = 3
	server_axes[entity_id] = 1

func _assign_local_input_devices() -> void:
	var joypads := Input.get_connected_joypads()
	local_players.sort_custom(func(a: CharacterBody3D, b: CharacterBody3D) -> bool: return a.local_player_index < b.local_player_index)
	for index in local_players.size():
		var device := -1
		if local_players.size() > 1:
			if joypads.size() >= local_players.size():
				device = joypads[index]
			elif index == 0:
				device = -2
			elif index - 1 < joypads.size():
				device = joypads[index - 1]
			else:
				device = -3
		local_players[index].configure_local_input(device, index)
		var entity_id: int = local_players[index].entity_id
		if inventory_menus.has(entity_id):
			inventory_menus[entity_id].input_device = device

func _on_split_joy_connection_changed(_device: int, _connected: bool) -> void:
	_assign_local_input_devices()

func _spawn_server_bots() -> void:
	var count := NetworkSession.get_expected_bot_count()
	for index in count:
		_spawn_one_server_bot(index)
	_refresh_bot_targets()

func _spawn_one_server_bot(index: int) -> void:
	var bot := CombatBot.new()
	var team := 0 if infection_mode else (_least_populated_team() if team_deathmatch else bot_serial)
	var infected := infection_mode and team == 1
	var bot_weapon_ids := ContentRegistry.get_bot_loadout_weapon_ids()
	var bot_weapon := str(bot_weapon_ids[index % bot_weapon_ids.size()])
	bot.setup(null, waypoints, "infected" if infected else bot_weapon, team, NetworkSession.config["bot_difficulty"])
	if index == 0 or index == 3:
		bot.enable_portal_gun()
	bot.name = "LANBot_%d" % bot_serial
	bot.display_name = CombatantNames.random_unique(_used_lan_combatant_names())
	bot.position = _spawn_for(team, index + NetworkSession.players.size())
	bot.set("entity_id", bot_serial)
	add_child(bot)
	bot.set_mode_infected(infected)
	bot.killed.connect(_on_server_bot_killed)
	bots.append(bot)
	entities[bot_serial] = bot
	match_scores[bot_serial if not team_deathmatch else team] = 0
	killstreaks[bot_serial] = 0
	streak_inventories[bot_serial] = []
	leaderboard_kills[bot_serial] = 0
	leaderboard_deaths[bot_serial] = 0
	leaderboard_points[bot_serial] = 0
	multi_kill_counts[bot_serial] = 0
	multi_kill_deadlines[bot_serial] = 0
	bot_serial += 1

func _refresh_bot_targets() -> void:
	if not multiplayer.is_server():
		return
	var combatants: Array[CharacterBody3D] = []
	for entity in entities.values():
		if entity is CharacterBody3D:
			combatants.append(entity)
	for bot in bots:
		bot.set_target_candidates(combatants)
	_append_attack_dog_targets()

func _build_match_hud() -> void:
	var combat_hud_script = load(COMBAT_HUD_PATH)
	combat_hud = combat_hud_script.new()
	add_child(combat_hud)
	combat_hud.result_primary_pressed.connect(_result_return_to_lobby)
	combat_hud.result_secondary_pressed.connect(_result_return_to_main_menu)
	if king_mode and team_deathmatch:
		combat_hud.set_team_labels("BLUE", "RED")
	elif king_mode:
		combat_hud.set_team_labels("LEADER", "YOU")
	elif infection_mode:
		combat_hud.set_team_labels("SURVIVORS", "INFECTED")
	elif juggernaut_mode:
		combat_hud.set_team_labels("LEADER", "YOU")
	elif team_deathmatch:
		combat_hud.set_team_labels("BLUE", "RED")
	else:
		combat_hud.set_team_labels("LEADER", "YOU")
	combat_hud.set_score(0, 0, score_target)
	var empty_streak_inventory: Array[String] = []
	combat_hud.set_streak_inventory(empty_streak_inventory)
	timer_label = Label.new()
	timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	timer_label.position = Vector2(-170, 22)
	timer_label.size = Vector2(150, 34)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label.add_theme_font_size_override("font_size", 20)
	timer_label.modulate = Color("#f3ce4f")
	combat_hud.add_child(timer_label)
	if local_player:
		local_player.health_changed.connect(combat_hud.set_health)
		local_player.damaged.connect(combat_hud.show_damage)
		local_player.vehicle_status_changed.connect(combat_hud.set_vehicle_status)
		combat_hud.set_health(local_player.health, local_player.max_health)
	if not local_player:
		return
	var settings_menu_script = load(SETTINGS_MENU_PATH)
	var settings: CanvasLayer = settings_menu_script.new()
	add_child(settings)
	settings.setup(local_player)
	for controller in local_players:
		var inventory_menu_script = load(INVENTORY_MENU_PATH)
		var menu: CanvasLayer = inventory_menu_script.new()
		menu.name = "InventoryMenu_%d" % controller.entity_id
		add_child(menu)
		menu.setup(controller.rifle, true, controller.input_device)
		menu.menu_visibility_changed.connect(_on_lan_loadout_menu_visibility_changed.bind(controller))
		inventory_menus[controller.entity_id] = menu
		if controller == local_player:
			inventory_menu = menu

func _on_lan_loadout_menu_visibility_changed(open: bool, controller: CharacterBody3D) -> void:
	controller.gameplay_input_blocked = open
	controller.set_physics_process(not open and not loadout_intermission_active)
	controller.set_weapon_views_enabled(not open and controller.alive)

func _begin_lan_loadout_intermission() -> void:
	loadout_intermission_active = true
	loadout_intermission_remaining = LOADOUT_INTERMISSION_DURATION
	match_active = false
	for menu in inventory_menus.values():
		menu.begin_intermission(loadout_intermission_remaining)
	for entity in entities.values():
		entity.set_physics_process(false)

func _update_lan_loadout_intermission(delta: float) -> void:
	loadout_intermission_remaining = maxf(loadout_intermission_remaining - delta, 0.0)
	for menu in inventory_menus.values():
		menu.set_intermission_remaining(loadout_intermission_remaining)
	if loadout_intermission_remaining <= 0.0:
		_finish_lan_loadout_intermission()

func _finish_lan_loadout_intermission() -> void:
	loadout_intermission_active = false
	for menu in inventory_menus.values():
		menu.finish_intermission()
	_reset_local_lan_loadout_ammo()
	for entity in entities.values():
		entity.set_physics_process(true)
	for controller in local_players:
		controller.set_weapon_views_enabled(controller.alive)
	match_active = true
	if combat_hud:
		combat_hud.show_notification("MATCH LIVE", 2.0)

func _reset_local_lan_loadout_ammo() -> void:
	for controller in local_players:
		controller.rifle.reset_loadout_ammo()
		controller.offhand_rifle.reset_loadout_ammo()

func _apply_pending_local_lan_loadout(controller: CharacterBody3D = local_player) -> void:
	if not controller:
		return
	var menu: CanvasLayer = inventory_menus.get(controller.entity_id)
	if menu:
		menu.apply_pending_loadout()
	controller.rifle.reset_loadout_ammo()
	controller.offhand_rifle.reset_loadout_ammo()

func _build_match_communications() -> void:
	var communications_script = load(MATCH_COMMUNICATIONS_PATH)
	match_communications = communications_script.new()
	match_communications.name = "MatchCommunications"
	match_communications.setup(self)
	add_child(match_communications)

func _send_local_state() -> void:
	for controller in local_players:
		if not controller.alive:
			continue
		var state := {"position": controller.global_position, "yaw": controller.rotation.y, "pitch": controller.head.rotation.x, "velocity": controller.velocity, "crouching": controller.crouching, "aiming": controller.rifle.is_aiming, "weapon": controller.rifle.current_weapon_id}
		if multiplayer.is_server():
			_accept_player_state(controller.entity_id, state)
		else:
			_submit_player_state.rpc_id(1, controller.entity_id, state)

@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _submit_player_state(entity_id: int, state: Dictionary) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_accept_player_state(entity_id, state)

func _accept_player_state(entity_id: int, state: Dictionary) -> void:
	if not entities.has(entity_id):
		return
	var entity: Node3D = entities[entity_id]
	if local_players_by_entity.has(entity_id):
		return
	var requested: Vector3 = state.get("position", entity.global_position)
	var distance := entity.global_position.distance_to(requested)
	if distance > 4.0:
		requested = entity.global_position.move_toward(requested, 4.0)
	state["position"] = requested
	entity.apply_snapshot(state)

func lan_physics_utility_begin(entity_id: int, utility: String, origin: Vector3, direction: Vector3) -> void:
	if multiplayer.is_server():
		_server_begin_physics_utility(entity_id, utility, origin, direction)
	else:
		_request_physics_utility_begin.rpc_id(1, entity_id, utility, origin, direction)

func lan_ground_pound(entity_id: int, position: Vector3) -> void:
	if multiplayer.is_server():
		_server_ground_pound(entity_id, position)
	else:
		_request_ground_pound.rpc_id(1, entity_id, position)

@rpc("any_peer", "call_remote", "reliable")
func _request_ground_pound(entity_id: int, position: Vector3) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_ground_pound(entity_id, position)

func _server_ground_pound(entity_id: int, position: Vector3) -> void:
	if not entities.has(entity_id):
		return
	var attacker: Node3D = entities[entity_id]
	var perks = attacker.get("active_perks")
	var now := Time.get_ticks_msec()
	if attacker.get("alive") != true or perks is not Array or "shockwave_ground_pound" not in perks or now < int(server_ground_pound_times.get(entity_id, 0)):
		return
	if attacker.global_position.distance_to(position) > 2.5:
		return
	server_ground_pound_times[entity_id] = now + 5000
	for candidate in get_tree().get_nodes_in_group("combatants") + get_tree().get_nodes_in_group("vehicles") + get_tree().get_nodes_in_group("city_damageables"):
		if candidate == attacker or candidate is not Node3D or not is_instance_valid(candidate):
			continue
		var offset: Vector3 = candidate.global_position - position
		var distance := offset.length()
		if distance > 7.0:
			continue
		var strength := 1.0 - distance / 7.0
		var direction := Vector3(offset.x, 0.0, offset.z).normalized()
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
		if candidate is CharacterBody3D:
			apply_lan_character_velocity(candidate, direction * lerpf(5.0, 15.0, strength) + Vector3.UP * lerpf(4.0, 9.0, strength), false)
		if candidate.has_method("set_physics_kill_credit"):
			candidate.set_physics_kill_credit(attacker)
		elif candidate.has_method("set_portal_fall_credit"):
			candidate.set_portal_fall_credit(attacker)
		if candidate.has_method("receive_zone_hit"):
			candidate.receive_zone_hit(lerpf(10.0, 35.0, strength), "explosion", candidate.global_position, direction, attacker)

func lan_physics_utility_release(entity_id: int, direction: Vector3) -> void:
	if multiplayer.is_server():
		_server_release_physics_utility(entity_id, direction)
	else:
		_request_physics_utility_release.rpc_id(1, entity_id, direction)

@rpc("any_peer", "call_remote", "reliable")
func _request_physics_utility_begin(entity_id: int, utility: String, origin: Vector3, direction: Vector3) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_begin_physics_utility(entity_id, utility, origin, direction)

@rpc("any_peer", "call_remote", "reliable")
func _request_physics_utility_release(entity_id: int, direction: Vector3) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_release_physics_utility(entity_id, direction)

func _server_begin_physics_utility(entity_id: int, utility: String, origin: Vector3, direction: Vector3) -> void:
	if not entities.has(entity_id) or utility != "force":
		return
	var user: Node3D = entities[entity_id]
	if not user.alive or str(user.get("physics_utility_id")) != utility:
		return
	var safe_origin := user.global_position + Vector3.UP * 0.6
	if safe_origin.distance_to(origin) <= 2.0:
		safe_origin = origin
	var max_range := 22.0
	var query := PhysicsRayQueryParameters3D.create(safe_origin, safe_origin + direction.normalized() * max_range)
	query.collision_mask = 1 | 2 | 4 | 8
	query.collide_with_areas = true
	query.exclude = [user.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var hit_node: Node = result.collider as Node
	var damage_owner = hit_node.get("damage_owner") if hit_node else null
	var target_node: Node3D = damage_owner as Node3D if damage_owner is Node3D else hit_node as Node3D
	var dynamic := target_node is CharacterBody3D or target_node is RigidBody3D or (target_node and target_node.is_in_group("vehicles"))
	if not dynamic:
		return
	server_physics_utilities[entity_id] = {"utility": utility, "target": target_node if dynamic else null, "anchor": result.position, "time": 0.0}
	if target_node and target_node.has_method("set_physics_kill_credit"):
		target_node.set_physics_kill_credit(user)

func _server_release_physics_utility(entity_id: int, direction: Vector3) -> void:
	if not server_physics_utilities.has(entity_id):
		return
	var record: Dictionary = server_physics_utilities[entity_id]
	var target_node: Node3D = record.get("target")
	if str(record.get("utility", "")) == "force" and is_instance_valid(target_node):
		_set_server_physics_velocity(target_node, direction.normalized() * 48.0 * _server_force_mass_factor(target_node))
		if target_node is RigidBody3D and not target_node.is_in_group("physics_projectiles") and entities.has(entity_id):
			var existing := target_node.get_node_or_null("ForceImpactDamage")
			if existing and existing.has_method("configure"):
				existing.configure(target_node, entities[entity_id])
			else:
				var impact_damage := ForceImpactDamage.new()
				impact_damage.name = "ForceImpactDamage"
				impact_damage.configure(target_node, entities[entity_id])
				target_node.add_child(impact_damage)
	server_physics_utilities.erase(entity_id)

func _server_force_mass_factor(target_node: Node3D) -> float:
	if target_node.is_in_group("vehicles"):
		return 0.38
	if target_node is RigidBody3D:
		return clampf(2.0 / maxf(target_node.mass, 0.25), 0.25, 1.35)
	return 1.0

func _update_server_physics_utilities(delta: float) -> void:
	for raw_id in server_physics_utilities.keys():
		var entity_id := int(raw_id)
		if not entities.has(entity_id):
			server_physics_utilities.erase(raw_id)
			continue
		var user: Node3D = entities[entity_id]
		var record: Dictionary = server_physics_utilities[raw_id]
		record["time"] = float(record.get("time", 0.0)) + delta
		if not user.alive or float(record["time"]) > 5.0:
			server_physics_utilities.erase(raw_id)
			continue
		var target_node: Node3D = record.get("target")
		var anchor: Vector3 = target_node.global_position if is_instance_valid(target_node) else record.get("anchor", user.global_position)
		if user.global_position.distance_to(anchor) > 42.0:
			server_physics_utilities.erase(raw_id)
			continue
		if is_instance_valid(target_node):
			var hold_point := _server_force_view_origin(user) + _server_force_aim_direction(user) * 4.0
			var desired := ((hold_point - target_node.global_position) / 0.08).limit_length(90.0)
			_set_server_physics_velocity(target_node, desired * (0.38 if target_node.is_in_group("vehicles") else 1.0))
			if target_node.is_in_group("combatants"):
				var face_point := Vector3(user.global_position.x, target_node.global_position.y, user.global_position.z)
				if target_node.global_position.distance_squared_to(face_point) > 0.001:
					target_node.look_at(face_point, Vector3.UP)

func _server_force_view_origin(user: Node3D) -> Vector3:
	var user_head = user.get("head")
	if user_head is Node3D:
		return user_head.global_position
	var view_height := 0.2 if user.get("crouching") == true else 0.68
	return user.global_position + Vector3.UP * view_height

func _server_force_aim_direction(user: Node3D) -> Vector3:
	var pitch := 0.0
	var user_head = user.get("head")
	if user_head is Node3D:
		pitch = user_head.rotation.x
	elif user.get("target_aim_pitch") != null:
		pitch = float(user.get("target_aim_pitch"))
	var aim_basis := user.global_transform.basis * Basis(Vector3.RIGHT, pitch)
	return (-aim_basis.z).normalized()

func _set_server_physics_velocity(target_node: Node3D, value: Vector3) -> void:
	if target_node is RigidBody3D:
		target_node.linear_velocity = value
	elif target_node is CharacterBody3D:
		apply_lan_character_velocity(target_node, value, true)

func apply_lan_character_velocity(target: CharacterBody3D, value: Vector3, replace := false) -> void:
	if not is_instance_valid(target) or not value.is_finite():
		return
	if replace:
		target.velocity = value
	else:
		target.velocity += value
	# A NetworkAvatar is only the host's authoritative representation. Forward
	# physical motion to the controller that actually simulates the remote human.
	if target.get("last_snapshot_velocity") != null:
		var represented_velocity: Vector3 = target.get("last_snapshot_velocity")
		target.set("last_snapshot_velocity", value if replace else represented_velocity + value)
	if not multiplayer.is_server():
		return
	var target_id := _entity_id_for(target)
	if target_id <= 0 or target_id >= 1000 or local_players_by_entity.has(target_id):
		return
	var owner_peer_id := NetworkSession.get_owner_peer_id(target_id)
	if owner_peer_id > 0:
		_receive_character_velocity.rpc_id(owner_peer_id, target_id, value, replace)

@rpc("authority", "call_remote", "unreliable_ordered", 6)
func _receive_character_velocity(entity_id: int, value: Vector3, replace: bool) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if not controller or not controller.alive or not value.is_finite():
		return
	if replace:
		controller.velocity = value
	else:
		controller.velocity += value

func forward_lan_physics_credit(target_id: int, attacker: Node) -> void:
	if not multiplayer.is_server() or target_id <= 0 or target_id >= 1000 or local_players_by_entity.has(target_id):
		return
	var attacker_id := _entity_id_for(attacker)
	var owner_peer_id := NetworkSession.get_owner_peer_id(target_id)
	if attacker_id > 0 and owner_peer_id > 0:
		_receive_physics_credit.rpc_id(owner_peer_id, target_id, attacker_id)

@rpc("authority", "call_remote", "reliable")
func _receive_physics_credit(target_id: int, attacker_id: int) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(target_id)
	var attacker: Node = entities.get(attacker_id)
	if controller and attacker:
		controller.set_physics_kill_credit(attacker)

func _publish_snapshot() -> void:
	for entity_id in entities:
		var entity: Node = entities[entity_id]
		if not is_instance_valid(entity):
			continue
		var state := {"position": entity.global_position, "yaw": entity.rotation.y, "velocity": entity.velocity, "alive": entity.alive, "health": entity.health, "team": entity.team_id, "display_name": str(entity.get("display_name")) if entity.get("display_name") != null else "", "mode_juggernaut": entity.get("mode_juggernaut") == true, "mode_infected": entity.get("mode_infected") == true, "crouching": entity.get("crouching") == true, "tbagging": entity.get("tbagging") == true, "perks": entity.get("active_perks") if entity.get("active_perks") != null else [], "jetpack": entity.get("jetpack_owned") == true, "coil_gun": entity.get("coil_gun_owned") == true, "suicide_vest": entity.get("suicide_vest_owned") == true, "suicide_vest_triggering": entity.get("suicide_vest_triggering") == true, "physics_utility": str(entity.get("physics_utility_id")) if entity.get("physics_utility_id") != null else "", "ricochet_time": float(entity.get("ricochet_time")) if entity.get("ricochet_time") != null else 0.0, "grenades": entity.get("grenades_remaining") if entity.get("grenades_remaining") != null else int(server_grenades.get(entity_id, 3)), "grenade_type": str(entity.get("grenade_type")) if entity.get("grenade_type") != null else "normal", "axes": entity.get("axes_remaining") if entity.get("axes_remaining") != null else int(server_axes.get(entity_id, 1)), "pitch": entity.get("target_aim_pitch") if entity.get("target_aim_pitch") != null else 0.0, "aiming": _entity_is_aiming(entity), "weapon": _entity_weapon_id(entity)}
		_receive_entity_snapshot.rpc(entity_id, state)
	_receive_attack_dog_snapshot.rpc(_attack_dog_snapshot())
	_receive_world_snapshot.rpc(match_scores, killstreaks, leaderboard_kills, leaderboard_deaths, leaderboard_points, remaining_time, sudden_death, _pickup_snapshot(), _vehicle_snapshot(), _lan_special_state(), _city_actor_snapshot())

func _entity_weapon_id(entity: Node) -> String:
	var weapon_type_value = entity.get("weapon_type")
	if weapon_type_value != null:
		return str(weapon_type_value)
	var represented_weapon = entity.get("equipped_weapon_id")
	if represented_weapon != null:
		return str(represented_weapon)
	var entity_rifle = entity.get("rifle")
	if entity_rifle != null:
		return str(entity_rifle.get("current_weapon_id"))
	return "none"

func _entity_is_aiming(entity: Node) -> bool:
	var bot_aiming = entity.get("is_aiming")
	if bot_aiming != null:
		return bot_aiming == true
	var represented_aiming = entity.get("aiming")
	if represented_aiming != null:
		return represented_aiming == true
	var entity_rifle = entity.get("rifle")
	return entity_rifle != null and entity_rifle.get("is_aiming") == true

func _attack_dog_snapshot() -> Dictionary:
	var states := {}
	for dog in attack_dogs:
		if is_instance_valid(dog):
			states[dog.dog_id] = dog.snapshot_state()
	return states

@rpc("authority", "call_remote", "unreliable_ordered", 5)
func _receive_attack_dog_snapshot(states: Dictionary) -> void:
	for dog_id_value in states:
		var dog_id := int(dog_id_value)
		var state: Dictionary = states[dog_id_value]
		if not network_attack_dogs.has(dog_id):
			var owner_id := int(state.get("owner", 0))
			var dog := AttackDog.new()
			dog.setup(dog_id, owner_id, entities.get(owner_id), int(state.get("team", 0)), false, waypoints)
			dog.position = state.get("position", Vector3.ZERO)
			add_child(dog)
			network_attack_dogs[dog_id] = dog
			attack_dogs.append(dog)
		network_attack_dogs[dog_id].apply_snapshot(state)
	for existing_id in network_attack_dogs.keys():
		if not states.has(existing_id):
			var removed: Node = network_attack_dogs[existing_id]
			_remove_attack_dog_from_targets(removed)
			attack_dogs.erase(removed)
			if is_instance_valid(removed):
				removed.queue_free()
			network_attack_dogs.erase(existing_id)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_entity_snapshot(entity_id: int, state: Dictionary) -> void:
	if not entities.has(entity_id):
		_spawn_client_bot(entity_id, state)
	if not entities.has(entity_id):
		return
	var entity: Node = entities[entity_id]
	if local_players_by_entity.has(entity_id):
		_apply_local_authoritative_state(state, local_players_by_entity[entity_id])
	elif entity.has_method("apply_snapshot"):
		entity.apply_snapshot(state)

@rpc("authority", "call_remote", "unreliable_ordered", 4)
func _receive_world_snapshot(scores: Dictionary, streak_states: Dictionary, kill_states: Dictionary, death_states: Dictionary, point_states: Dictionary, time_left: float, overtime: bool, pickup_states: Dictionary, vehicle_states: Dictionary, special_state: Dictionary, city_actor_states: Dictionary) -> void:
	match_scores = scores
	killstreaks = streak_states
	leaderboard_kills = kill_states
	leaderboard_deaths = death_states
	leaderboard_points = point_states
	remaining_time = time_left
	sudden_death = overtime
	_sync_client_pickups(pickup_states)
	_sync_client_vehicles(vehicle_states)
	_apply_lan_special_state(special_state)
	_apply_city_actor_snapshot(city_actor_states)

func _city_map() -> Node:
	return get_node_or_null("CityDistrict")

func _city_actor_snapshot() -> Dictionary:
	var city := _city_map()
	return city.dynamic_actor_snapshot() if city and city.has_method("dynamic_actor_snapshot") else {}

func _apply_city_actor_snapshot(states: Dictionary) -> void:
	var city := _city_map()
	if city and city.has_method("apply_dynamic_actor_snapshot"):
		city.apply_dynamic_actor_snapshot(states)

func send_city_vehicle_impact(entity_id: int, push_velocity: Vector3) -> void:
	if multiplayer.is_server() and entity_id > 0:
		if local_players_by_entity.has(entity_id):
			_receive_city_vehicle_impact(entity_id, push_velocity)
		else:
			_receive_city_vehicle_impact.rpc_id(NetworkSession.get_owner_peer_id(entity_id), entity_id, push_velocity)

func lan_player_placed_portal(entity_id: int, index: int, portal_transform: Transform3D) -> void:
	if entity_id <= 0 or index < 0 or index > 1:
		return
	if multiplayer.is_server():
		_server_place_player_portal(entity_id, index, portal_transform)
	else:
		_request_player_portal.rpc_id(1, entity_id, index, portal_transform)

@rpc("any_peer", "call_remote", "reliable")
func _request_player_portal(entity_id: int, index: int, portal_transform: Transform3D) -> void:
	if not multiplayer.is_server() or not NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		return
	_server_place_player_portal(entity_id, index, portal_transform)

func _server_place_player_portal(entity_id: int, index: int, portal_transform: Transform3D) -> void:
	if not entities.has(entity_id) or index < 0 or index > 1:
		return
	var owner: Node3D = entities[entity_id]
	if owner.get("alive") != true or not _valid_portal_transform(portal_transform):
		return
	if owner.global_position.distance_to(portal_transform.origin) > PortalManager.PORTAL_RANGE + 6.0:
		return
	var placements: Dictionary = server_player_portals.get(entity_id, {})
	placements[index] = portal_transform
	server_player_portals[entity_id] = placements
	if not local_players_by_entity.has(entity_id):
		_show_remote_player_portal(entity_id, index, portal_transform)
	_remote_player_portal.rpc(entity_id, index, portal_transform)

func _valid_portal_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite() and absf(value.basis.determinant()) > 0.001

@rpc("authority", "call_remote", "reliable")
func _remote_player_portal(entity_id: int, index: int, portal_transform: Transform3D) -> void:
	if local_players_by_entity.has(entity_id):
		return
	_show_remote_player_portal(entity_id, index, portal_transform)

func _show_remote_player_portal(entity_id: int, index: int, portal_transform: Transform3D) -> void:
	if not entities.has(entity_id) or index < 0 or index > 1 or not _valid_portal_transform(portal_transform):
		return
	var manager: Node3D = remote_player_portal_managers.get(entity_id)
	if not is_instance_valid(manager):
		var viewer := Camera3D.new()
		viewer.name = "RemotePlayerPortalViewer"
		viewer.position = Vector3(0.0, 0.68, 0.0)
		viewer.current = false
		entities[entity_id].add_child(viewer)
		manager = PortalManager.new()
		manager.name = "RemotePlayerPortalManager_%d" % entity_id
		add_child(manager)
		manager.setup(viewer, entities[entity_id])
		remote_player_portal_managers[entity_id] = manager
	var existing: Area3D = manager.portals[index] if is_instance_valid(manager.portals[index]) else null
	if existing and existing.global_transform.is_equal_approx(portal_transform):
		return
	manager.place_portal_transform(index, portal_transform)

func _clear_player_portals(entity_id: int) -> void:
	server_player_portals.erase(entity_id)
	_clear_remote_player_portals(entity_id)
	if multiplayer.is_server():
		_clear_player_portals_remote.rpc(entity_id)

@rpc("authority", "call_remote", "reliable")
func _clear_player_portals_remote(entity_id: int) -> void:
	_clear_remote_player_portals(entity_id)
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if controller and controller.rifle:
		controller.rifle.clear_portals()

func _clear_remote_player_portals(entity_id: int) -> void:
	var manager: Node = remote_player_portal_managers.get(entity_id)
	if is_instance_valid(manager):
		manager.queue_free()
	remote_player_portal_managers.erase(entity_id)

func request_portal_travel(body: Node3D, entry_position: Vector3, destination: Vector3, outgoing_velocity: Vector3, outgoing_basis: Basis, portal_owner: Node) -> void:
	if body.is_in_group("vehicles"):
		var network_id_value = body.get("network_id")
		if network_id_value == null:
			return
		var vehicle_id := int(network_id_value)
		if vehicle_id <= 0:
			return
		if multiplayer.is_server():
			_apply_portal_vehicle_travel(vehicle_id, entry_position, destination, outgoing_velocity, outgoing_basis)
		else:
			_request_portal_vehicle_travel.rpc_id(1, vehicle_id, entry_position, destination, outgoing_velocity, outgoing_basis)
		return
	# Portals also accept loose rigid bodies, including death debris. Those are
	# teleported locally by PortalManager and do not have a network entity ID.
	var entity_id_value = body.get("entity_id")
	if entity_id_value == null:
		return
	var target_id := int(entity_id_value)
	if target_id <= 0:
		return
	var portal_owner_id := _entity_id_for(portal_owner)
	if multiplayer.is_server():
		_apply_portal_travel(target_id, entry_position, destination, outgoing_velocity, portal_owner_id)
	else:
		_request_portal_travel.rpc_id(1, target_id, entry_position, destination, outgoing_velocity, portal_owner_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_portal_vehicle_travel(vehicle_id: int, entry_position: Vector3, destination: Vector3, outgoing_velocity: Vector3, outgoing_basis: Basis) -> void:
	if multiplayer.is_server():
		_apply_portal_vehicle_travel(vehicle_id, entry_position, destination, outgoing_velocity, outgoing_basis)

func _apply_portal_vehicle_travel(vehicle_id: int, entry_position: Vector3, destination: Vector3, outgoing_velocity: Vector3, outgoing_basis: Basis) -> void:
	var vehicle: Node3D = _server_vehicle_by_network_id(vehicle_id)
	if not vehicle or not destination.is_finite() or not outgoing_velocity.is_finite():
		return
	# Large chassis can touch the portal while their origin is still several meters
	# away, so use a wider stale-event tolerance than character traversal.
	if vehicle.global_position.distance_to(entry_position) > 7.0:
		return
	vehicle.global_position = destination
	vehicle.global_basis = outgoing_basis.orthonormalized()
	vehicle.set("velocity", outgoing_velocity.limit_length(45.0))
	if vehicle.has_method("begin_portal_travel"):
		vehicle.begin_portal_travel(outgoing_velocity.limit_length(45.0), outgoing_basis)

@rpc("any_peer", "call_remote", "reliable")
func _request_portal_travel(target_id: int, entry_position: Vector3, destination: Vector3, outgoing_velocity: Vector3, portal_owner_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# Either the portal owner or the traveler may detect the overlap first. A
	# replicated portal therefore accepts its traveler's owning peer, provided
	# the claimed entry matches a portal the host knows belongs to that owner.
	var owns_target := NetworkSession.peer_owns_entity(sender_id, target_id)
	var owns_portal := NetworkSession.peer_owns_entity(sender_id, portal_owner_id)
	if not owns_target and not owns_portal:
		return
	if not _server_portal_entry_matches(portal_owner_id, entry_position):
		return
	_apply_portal_travel(target_id, entry_position, destination, outgoing_velocity, portal_owner_id)

func _server_portal_entry_matches(portal_owner_id: int, entry_position: Vector3) -> bool:
	var player_placements: Dictionary = server_player_portals.get(portal_owner_id, {})
	for portal_transform in player_placements.values():
		var known_transform: Transform3D = portal_transform
		if known_transform.origin.distance_to(entry_position) <= 1.5:
			return true
	if entities.has(portal_owner_id):
		var manager = entities[portal_owner_id].get("portal_manager")
		if is_instance_valid(manager):
			for portal in manager.portals:
				if is_instance_valid(portal) and portal.global_position.distance_to(entry_position) <= 1.5:
					return true
	return false

func _apply_portal_travel(target_id: int, entry_position: Vector3, destination: Vector3, outgoing_velocity: Vector3, portal_owner_id: int) -> void:
	if not entities.has(target_id) or not destination.is_finite() or not outgoing_velocity.is_finite():
		return
	var entity: Node3D = entities[target_id]
	# Portal owners detect traversal using the target's replicated body. Allow for
	# snapshot interpolation and a full character capsule, but reject stale entry
	# events after that target has already moved away from the portal.
	if entity.global_position.distance_to(entry_position) > 4.0:
		return
	var safe_velocity := outgoing_velocity.limit_length(45.0)
	if entities.has(portal_owner_id) and entity.has_method("set_portal_fall_credit"):
		entity.set_portal_fall_credit(entities[portal_owner_id])
	entity.global_position = destination
	entity.set("velocity", safe_velocity)
	if entity.get("target_position") != null:
		entity.set("target_position", destination)
	if entity.get("last_snapshot_velocity") != null:
		entity.set("last_snapshot_velocity", safe_velocity)
	if target_id < 1000 and not local_players_by_entity.has(target_id):
		_receive_portal_travel.rpc_id(NetworkSession.get_owner_peer_id(target_id), target_id, destination, safe_velocity)

@rpc("authority", "call_remote", "reliable")
func _receive_portal_travel(entity_id: int, destination: Vector3, outgoing_velocity: Vector3) -> void:
	var target: CharacterBody3D = local_players_by_entity.get(entity_id)
	if not target or not target.alive:
		return
	target.global_position = destination
	target.velocity = outgoing_velocity

@rpc("authority", "call_remote", "reliable")
func _receive_city_vehicle_impact(entity_id: int, push_velocity: Vector3) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if controller and controller.alive:
		# Health remains server-authoritative; this RPC applies only the immediate
		# physical shove so the struck client feels the impact without snapshot lag.
		controller.apply_vehicle_impact(0.0, push_velocity, null)

@rpc("authority", "call_remote", "reliable")
func _remove_network_entity(entity_id: int) -> void:
	_clear_remote_player_portals(entity_id)
	server_player_portals.erase(entity_id)
	if remote_bot_portal_managers.has(entity_id):
		var manager: Node = remote_bot_portal_managers[entity_id]
		if is_instance_valid(manager):
			manager.queue_free()
		remote_bot_portal_managers.erase(entity_id)
	if entities.has(entity_id):
		entities[entity_id].queue_free()
		entities.erase(entity_id)

func _spawn_client_bot(entity_id: int, state: Dictionary) -> void:
	if entity_id < 1000 or multiplayer.is_server():
		return
	var team := int(state.get("team", _team_from_snapshot(entity_id)))
	var avatar := NetworkAvatar.new()
	avatar.setup(entity_id, 0, str(state.get("display_name", "BOT %02d" % (entity_id - 999))), team)
	avatar.position = state.get("position", Vector3.ZERO)
	add_child(avatar)
	entities[entity_id] = avatar

func _used_lan_combatant_names() -> Dictionary:
	var names: Array = []
	for record in NetworkSession.players.values():
		names.append(record.get("name", ""))
	for entity in entities.values():
		var entity_name = entity.get("display_name")
		if entity_name != null and not str(entity_name).is_empty():
			names.append(entity_name)
	return CombatantNames.used_name_set(names)

func _on_session_roster_changed(_snapshot: Dictionary) -> void:
	if NetworkSession.phase != "match":
		return
	var ids := NetworkSession.players.keys()
	ids.sort()
	for index in ids.size():
		_spawn_human(int(ids[index]), index, multiplayer.get_unique_id())
	for entity_id in entities.keys():
		if int(entity_id) < 1000 and not NetworkSession.players.has(entity_id):
			var departed: Node = entities[entity_id]
			if multiplayer.is_server():
				_clear_player_portals(int(entity_id))
			else:
				_clear_remote_player_portals(int(entity_id))
			if departed.current_vehicle:
				departed.current_vehicle.leave_seat(departed, true)
			departed.queue_free()
			entities.erase(entity_id)
	if multiplayer.is_server():
		_ensure_server_bot_count()
		if juggernaut_mode and lan_juggernaut_id != 0:
			_refresh_lan_juggernaut_targets()
		else:
			_refresh_bot_targets()

func _ensure_server_bot_count() -> void:
	var desired := NetworkSession.get_expected_bot_count()
	while bots.size() > desired:
		var bot: Node = bots.pop_back()
		var id := _entity_id_for(bot)
		entities.erase(id)
		_remove_network_entity.rpc(id)
		bot.queue_free()
	while bots.size() < desired:
		_spawn_one_server_bot(bots.size())

func request_network_hit(attacker_id: int, target_id: int, amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3) -> void:
	var attacker: CharacterBody3D = local_players_by_entity.get(attacker_id)
	var weapon_id: String = attacker.get_last_fired_weapon_id() if attacker else "ak47"
	if multiplayer.is_server():
		_apply_hit_claim(attacker_id, target_id, amount, zone, hit_position, hit_normal, weapon_id)
	else:
		_claim_hit.rpc_id(1, attacker_id, target_id, clampf(amount, 0.0, 10000.0), zone, hit_position, hit_normal, weapon_id)

func lan_apply_prop_bullet_impulse(attacker_id: int, prop_name: String, impulse: Vector3, hit_position: Vector3) -> void:
	var attacker: CharacterBody3D = local_players_by_entity.get(attacker_id)
	var weapon_id: String = attacker.get_last_fired_weapon_id() if attacker else "ak47"
	if multiplayer.is_server():
		_apply_prop_bullet_impulse_claim(attacker_id, prop_name, impulse, hit_position, weapon_id)
	else:
		_claim_prop_bullet_impulse.rpc_id(1, attacker_id, prop_name, impulse, hit_position, weapon_id)

@rpc("any_peer", "call_remote", "reliable")
func _claim_prop_bullet_impulse(attacker_id: int, prop_name: String, impulse: Vector3, hit_position: Vector3, weapon_id: String) -> void:
	if not multiplayer.is_server() or not NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), attacker_id):
		return
	_register_server_shot(attacker_id, weapon_id)
	_apply_prop_bullet_impulse_claim(attacker_id, prop_name, impulse, hit_position, weapon_id)

func _apply_prop_bullet_impulse_claim(attacker_id: int, prop_name: String, impulse: Vector3, hit_position: Vector3, weapon_id: String) -> void:
	if not entities.has(attacker_id) or entities[attacker_id].get("alive") != true or weapon_id not in CombatRules.PROP_IMPULSE_BY_WEAPON:
		return
	if str(server_weapon_by_peer.get(attacker_id, "")) != weapon_id or Time.get_ticks_msec() - int(server_shot_time.get(attacker_id, 0)) > 750:
		return
	var prop: RigidBody3D
	for candidate in get_tree().get_nodes_in_group("training_physics_props"):
		if candidate is RigidBody3D and candidate.name == prop_name:
			prop = candidate
			break
	if not is_instance_valid(prop) or not impulse.is_finite() or not hit_position.is_finite():
		return
	var allowed_range := float(ContentRegistry.resolve_weapon(weapon_id)["range"]) + 4.0
	var allowed_impulse := float(CombatRules.PROP_IMPULSE_BY_WEAPON[weapon_id]) * 1.05
	if entities[attacker_id].global_position.distance_to(prop.global_position) > allowed_range or hit_position.distance_to(prop.global_position) > 4.0 or impulse.length() > allowed_impulse:
		return
	prop.sleeping = false
	prop.apply_impulse(impulse, hit_position - prop.global_position)

@rpc("any_peer", "call_remote", "reliable")
func _claim_hit(attacker_id: int, target_id: int, amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if NetworkSession.peer_owns_entity(peer_id, attacker_id):
			_register_server_shot(attacker_id, weapon_id)
			_apply_hit_claim(attacker_id, target_id, amount, zone, hit_position, hit_normal, weapon_id)

func _apply_hit_claim(attacker_id: int, target_id: int, amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if not entities.has(attacker_id) or not entities.has(target_id) or attacker_id == target_id:
		return
	var attacker: Node = entities[attacker_id]
	var target: Node = entities[target_id]
	if not attacker.alive or not target.alive:
		return
	if not ContentRegistry.has_weapon(weapon_id):
		return
	if str(server_weapon_by_peer.get(attacker_id, "")) != weapon_id or Time.get_ticks_msec() - int(server_shot_time.get(attacker_id, 0)) > 750:
		return
	var profile: Dictionary = ContentRegistry.resolve_weapon(weapon_id)
	var allowed_range := float(profile["range"]) + 3.0
	if attacker.global_position.distance_to(target.global_position) > allowed_range:
		return
	var zone_multiplier := 2.0 if zone == "head" else (0.75 if zone in ["limbs", "arm_l", "arm_r", "leg_l", "leg_r"] else 1.0)
	var allowed_damage := float(profile["damage"]) * zone_multiplier * 1.3
	if weapon_id in ["knife", "coil_gun"]:
		allowed_damage = 10000.0
	if amount > allowed_damage + 0.1:
		return
	var health_before := float(target.get("health"))
	var counts_as_gun_kill := weapon_id != "knife"
	if counts_as_gun_kill:
		target.set_meta("gun_streak_kill", true)
	target.receive_zone_hit(maxf(amount, 0.0), zone, hit_position, hit_normal, attacker)
	if counts_as_gun_kill and is_instance_valid(target):
		target.remove_meta("gun_streak_kill")
	var target_perks = target.get("active_perks")
	if float(target.get("health")) < health_before and target_perks is Array and "juggernog" in target_perks:
		_confirm_juggernog_hit_for(attacker_id)

func _confirm_juggernog_hit_for(attacker_id: int) -> void:
	if local_players_by_entity.has(attacker_id):
		_confirm_juggernog_hit(attacker_id)
	elif attacker_id > 0 and attacker_id < 1000:
		_confirm_juggernog_hit.rpc_id(NetworkSession.get_owner_peer_id(attacker_id), attacker_id)

@rpc("authority", "call_remote", "reliable")
func _confirm_juggernog_hit(entity_id: int) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if controller:
		controller.show_juggernog_hit()

func request_network_vehicle_hit(attacker_id: int, vehicle_id: int, amount: float, hit_position: Vector3, hit_normal: Vector3) -> void:
	var attacker: CharacterBody3D = local_players_by_entity.get(attacker_id)
	var weapon_id: String = attacker.get_last_fired_weapon_id() if attacker else "ak47"
	if multiplayer.is_server():
		_apply_vehicle_hit_claim(attacker_id, vehicle_id, amount, hit_position, hit_normal, weapon_id)
	else:
		_claim_vehicle_hit.rpc_id(1, attacker_id, vehicle_id, clampf(amount, 0.0, 10000.0), hit_position, hit_normal, weapon_id)

@rpc("any_peer", "call_remote", "reliable")
func _claim_vehicle_hit(attacker_id: int, vehicle_id: int, amount: float, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if NetworkSession.peer_owns_entity(peer_id, attacker_id):
			_register_server_shot(attacker_id, weapon_id)
			_apply_vehicle_hit_claim(attacker_id, vehicle_id, amount, hit_position, hit_normal, weapon_id)

func _apply_vehicle_hit_claim(attacker_id: int, vehicle_id: int, amount: float, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if not entities.has(attacker_id) or not ContentRegistry.has_weapon(weapon_id):
		return
	if str(server_weapon_by_peer.get(attacker_id, "")) != weapon_id or Time.get_ticks_msec() - int(server_shot_time.get(attacker_id, 0)) > 750:
		return
	var vehicle := _server_vehicle_by_network_id(vehicle_id)
	if not vehicle or not vehicle.alive:
		return
	var profile: Dictionary = ContentRegistry.resolve_weapon(weapon_id)
	if entities[attacker_id].global_position.distance_to(vehicle.global_position) > float(profile["range"]) + 5.0:
		return
	var allowed_damage := 10000.0 if weapon_id == "coil_gun" else float(profile["damage"]) * 1.3
	if amount <= allowed_damage + 0.1:
		vehicle.receive_zone_hit(maxf(amount, 0.0), "vehicle", hit_position, hit_normal, entities[attacker_id])

func request_city_actor_hit(attacker_id: int, actor_id: int, amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3) -> void:
	var attacker: CharacterBody3D = local_players_by_entity.get(attacker_id)
	var weapon_id: String = attacker.get_last_fired_weapon_id() if attacker else "ak47"
	if multiplayer.is_server():
		_apply_city_actor_hit_claim(attacker_id, actor_id, amount, zone, hit_position, hit_normal, weapon_id)
	else:
		_claim_city_actor_hit.rpc_id(1, attacker_id, actor_id, clampf(amount, 0.0, 10000.0), zone, hit_position, hit_normal, weapon_id)

@rpc("any_peer", "call_remote", "reliable")
func _claim_city_actor_hit(attacker_id: int, actor_id: int, amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if NetworkSession.peer_owns_entity(peer_id, attacker_id):
			_register_server_shot(attacker_id, weapon_id)
			_apply_city_actor_hit_claim(attacker_id, actor_id, amount, zone, hit_position, hit_normal, weapon_id)

func _apply_city_actor_hit_claim(attacker_id: int, actor_id: int, amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if not entities.has(attacker_id) or not ContentRegistry.has_weapon(weapon_id):
		return
	if str(server_weapon_by_peer.get(attacker_id, "")) != weapon_id or Time.get_ticks_msec() - int(server_shot_time.get(attacker_id, 0)) > 750:
		return
	var city := _city_map()
	var target: Node = city.get_dynamic_actor(actor_id) if city else null
	if not target or target.get("alive") != true:
		return
	var profile: Dictionary = ContentRegistry.resolve_weapon(weapon_id)
	if entities[attacker_id].global_position.distance_to(target.global_position) > float(profile["range"]) + 5.0:
		return
	var zone_multiplier := 2.0 if zone == "head" else (0.75 if zone in ["limbs", "arm_l", "arm_r", "leg_l", "leg_r"] else 1.0)
	var allowed_damage := float(profile["damage"]) * zone_multiplier * 1.3
	if weapon_id in ["knife", "coil_gun"]:
		allowed_damage = 10000.0
	if amount <= allowed_damage + 0.1:
		target.receive_zone_hit(maxf(amount, 0.0), zone, hit_position, hit_normal, entities[attacker_id])

func request_attack_dog_hit(attacker_id: int, dog_id: int, amount: float, hit_position: Vector3, hit_normal: Vector3) -> void:
	var attacker: CharacterBody3D = local_players_by_entity.get(attacker_id)
	var weapon_id: String = attacker.get_last_fired_weapon_id() if attacker else "ak47"
	if multiplayer.is_server():
		_apply_attack_dog_hit_claim(attacker_id, dog_id, amount, hit_position, hit_normal, weapon_id)
	else:
		_claim_attack_dog_hit.rpc_id(1, attacker_id, dog_id, clampf(amount, 0.0, 10000.0), hit_position, hit_normal, weapon_id)

@rpc("any_peer", "call_remote", "reliable")
func _claim_attack_dog_hit(attacker_id: int, dog_id: int, amount: float, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if NetworkSession.peer_owns_entity(peer_id, attacker_id):
			_register_server_shot(attacker_id, weapon_id)
			_apply_attack_dog_hit_claim(attacker_id, dog_id, amount, hit_position, hit_normal, weapon_id)

func _apply_attack_dog_hit_claim(attacker_id: int, dog_id: int, amount: float, hit_position: Vector3, hit_normal: Vector3, weapon_id: String) -> void:
	if not entities.has(attacker_id) or not network_attack_dogs.has(dog_id) or not ContentRegistry.has_weapon(weapon_id):
		return
	if str(server_weapon_by_peer.get(attacker_id, "")) != weapon_id or Time.get_ticks_msec() - int(server_shot_time.get(attacker_id, 0)) > 750:
		return
	var attacker: Node = entities[attacker_id]
	var dog: Node = network_attack_dogs[dog_id]
	if dog.get("alive") != true:
		return
	var profile: Dictionary = ContentRegistry.resolve_weapon(weapon_id)
	if attacker.global_position.distance_to(dog.global_position) > float(profile["range"]) + 3.0:
		return
	var zone_multiplier := 1.5 if hit_position.y > dog.global_position.y + 0.5 else 1.0
	var allowed_damage := float(profile["damage"]) * zone_multiplier * 1.3
	if weapon_id in ["knife", "coil_gun"]:
		allowed_damage = 10000.0
	if amount <= allowed_damage + 0.1:
		dog.receive_zone_hit(maxf(amount, 0.0), "body", hit_position, hit_normal, attacker)

func lan_local_shot(entity_id: int, weapon_id: String) -> void:
	if not local_players_by_entity.has(entity_id):
		return
	if multiplayer.is_server():
		_register_server_shot(entity_id, weapon_id, true)
	else:
		_report_shot.rpc_id(1, entity_id, weapon_id)

@rpc("any_peer", "call_remote", "reliable")
func _report_shot(entity_id: int, weapon_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if NetworkSession.peer_owns_entity(peer_id, entity_id):
		_register_server_shot(entity_id, weapon_id, true)

func _register_server_shot(peer_id: int, weapon_id: String, force_broadcast := false) -> void:
	if not multiplayer.is_server() or not entities.has(peer_id) or not ContentRegistry.has_weapon(weapon_id):
		return
	if weapon_id == "coil_gun" and entities[peer_id].get("coil_gun_owned") != true:
		return
	var now := Time.get_ticks_msec()
	var already_registered := str(server_weapon_by_peer.get(peer_id, "")) == weapon_id and now - int(server_shot_time.get(peer_id, 0)) < 100
	if force_broadcast:
		var shot_serial := int(server_shot_serial.get(peer_id, 0)) + 1
		server_shot_serial[peer_id] = shot_serial
		server_collateral_state[peer_id] = {"serial": shot_serial, "kills": 0, "awarded": false}
	server_weapon_by_peer[peer_id] = weapon_id
	server_shot_time[peer_id] = now
	var city := _city_map()
	if city:
		var shooter: Node3D = entities[peer_id]
		var range := float(ContentRegistry.resolve_weapon(weapon_id)["range"])
		city.alert_civilians(shooter.global_position, shooter.global_position - shooter.global_transform.basis.z * range)
	if force_broadcast or not already_registered:
		_remote_shot.rpc(peer_id, weapon_id)
		# call_remote RPCs do not execute on the authority itself. Mirror the
		# presentation locally so the host sees and hears client gunfire too.
		_remote_shot(peer_id, weapon_id)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _remote_shot(entity_id: int, weapon_id: String) -> void:
	if not local_players_by_entity.has(entity_id) and entities.has(entity_id):
		entities[entity_id].play_remote_shot(weapon_id)

func bot_fired_weapon(bot: Node, weapon_id: String) -> void:
	if not multiplayer.is_server():
		return
	var bot_id := _entity_id_for(bot)
	if bot_id >= 1000:
		_remote_bot_shot.rpc(bot_id, weapon_id)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _remote_bot_shot(bot_id: int, weapon_id: String) -> void:
	if entities.has(bot_id) and entities[bot_id].has_method("play_remote_shot"):
		entities[bot_id].play_remote_shot(weapon_id)

func bot_fired_coil_gun(bot: Node, target_positions: Array[Vector3]) -> void:
	if not multiplayer.is_server():
		return
	var bot_id := _entity_id_for(bot)
	if bot_id != 0:
		_remote_bot_coil.rpc(bot_id, target_positions)

func indirect_hit_confirmed(owner: Node, destroyed: bool) -> void:
	if not multiplayer.is_server():
		return
	var owner_id := _entity_id_for(owner)
	if local_players_by_entity.has(owner_id):
		_confirm_indirect_hitmarker(owner_id, destroyed)
	elif owner_id > 0 and owner_id < 1000:
		_confirm_indirect_hitmarker.rpc_id(NetworkSession.get_owner_peer_id(owner_id), owner_id, destroyed)

@rpc("authority", "call_remote", "reliable")
func _confirm_indirect_hitmarker(entity_id: int, destroyed: bool) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if controller:
		controller.show_indirect_hitmarker(destroyed)

func bot_throw_grenade(bot: Node, start: Vector3, launch_velocity: Vector3) -> bool:
	if not multiplayer.is_server():
		return false
	var bot_id := _entity_id_for(bot)
	if bot_id < 1000 or not entities.has(bot_id) or entities[bot_id] != bot or bot.alive != true:
		return false
	if bot.grenades_remaining <= 0 or bot.global_position.distance_to(start) > 4.0 or launch_velocity.length() > 35.0:
		return false
	bot.grenades_remaining -= 1
	server_grenades[bot_id] = bot.grenades_remaining
	var projectile_id := projectile_serial
	projectile_serial += 1
	var grenade_kind := str(bot.get("grenade_type")) if bot.get("grenade_type") != null else "normal"
	_spawn_network_grenade(projectile_id, bot_id, start, launch_velocity, grenade_kind, false)
	_spawn_grenade_remote.rpc(projectile_id, bot_id, start, launch_velocity, grenade_kind)
	return true

func bot_throw_axe(bot: Node, start: Vector3, launch_velocity: Vector3, spin_axis: Vector3) -> bool:
	if not multiplayer.is_server():
		return false
	var bot_id := _entity_id_for(bot)
	if bot_id < 1000 or not entities.has(bot_id) or entities[bot_id] != bot or bot.alive != true:
		return false
	if bot.axes_remaining <= 0 or bot.global_position.distance_to(start) > 4.0 or launch_velocity.length() > 50.0:
		return false
	bot.axes_remaining -= 1
	server_axes[bot_id] = bot.axes_remaining
	var projectile_id := projectile_serial
	projectile_serial += 1
	_spawn_network_axe(projectile_id, bot_id, start, launch_velocity, spin_axis, false)
	_spawn_axe_remote.rpc(projectile_id, bot_id, start, launch_velocity, spin_axis)
	return true

func bot_placed_portal(bot: Node, index: int, portal_transform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	var bot_id := _entity_id_for(bot)
	if bot_id != 0:
		_remote_bot_portal.rpc(bot_id, index, portal_transform)

@rpc("authority", "call_remote", "reliable")
func _remote_bot_portal(bot_id: int, index: int, portal_transform: Transform3D) -> void:
	if not entities.has(bot_id) or index < 0 or index > 1:
		return
	var manager: Node3D = remote_bot_portal_managers.get(bot_id)
	if not is_instance_valid(manager):
		var viewer := Camera3D.new()
		viewer.name = "RemoteBotPortalViewer"
		viewer.position = Vector3(0, 1.05, 0)
		viewer.current = false
		entities[bot_id].add_child(viewer)
		manager = PortalManager.new()
		manager.name = "RemoteBotPortalManager_%d" % bot_id
		add_child(manager)
		manager.setup(viewer, entities[bot_id])
		remote_bot_portal_managers[bot_id] = manager
	manager.place_portal_transform(index, portal_transform)

@rpc("authority", "call_remote", "reliable")
func _remote_bot_coil(bot_id: int, target_positions: Array[Vector3]) -> void:
	if entities.has(bot_id) and entities[bot_id].has_method("play_remote_coil"):
		entities[bot_id].play_remote_coil(target_positions)

func lan_throw_grenade(entity_id: int, start: Vector3, launch_velocity: Vector3) -> void:
	if not local_players_by_entity.has(entity_id):
		return
	if multiplayer.is_server():
		_server_spawn_grenade(entity_id, start, launch_velocity)
	else:
		_request_grenade.rpc_id(1, entity_id, start, launch_velocity)

@rpc("any_peer", "call_remote", "reliable")
func _request_grenade(entity_id: int, start: Vector3, launch_velocity: Vector3) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_spawn_grenade(entity_id, start, launch_velocity)

func _server_spawn_grenade(owner_id: int, start: Vector3, launch_velocity: Vector3) -> void:
	if not entities.has(owner_id) or entities[owner_id].global_position.distance_to(start) > 4.0:
		return
	if int(server_grenades.get(owner_id, 3)) <= 0 or Time.get_ticks_msec() - int(server_throw_time.get(owner_id, 0)) < 600 or launch_velocity.length() > 35.0:
		return
	server_grenades[owner_id] = int(server_grenades.get(owner_id, 3)) - 1
	server_throw_time[owner_id] = Time.get_ticks_msec()
	if entities[owner_id].get("grenades_remaining") != null:
		entities[owner_id].grenades_remaining = server_grenades[owner_id]
	var projectile_id := projectile_serial
	projectile_serial += 1
	var grenade_kind := str(entities[owner_id].get("grenade_type")) if entities[owner_id].get("grenade_type") != null else "normal"
	_spawn_network_grenade(projectile_id, owner_id, start, launch_velocity, grenade_kind, false)
	_spawn_grenade_remote.rpc(projectile_id, owner_id, start, launch_velocity, grenade_kind)

@rpc("authority", "call_remote", "reliable")
func _spawn_grenade_remote(projectile_id: int, owner_id: int, start: Vector3, launch_velocity: Vector3, grenade_kind: String) -> void:
	_spawn_network_grenade(projectile_id, owner_id, start, launch_velocity, grenade_kind, true)

func _spawn_network_grenade(projectile_id: int, owner_id: int, start: Vector3, launch_velocity: Vector3, grenade_kind: String, cosmetic: bool) -> void:
	if not entities.has(owner_id):
		return
	var grenade := GrenadeProjectile.new()
	grenade.configure(grenade_kind)
	grenade.name = "NetGrenade_%d" % projectile_id
	grenade.network_cosmetic = cosmetic
	grenade.set_meta("network_projectile_id", projectile_id)
	grenade.set_meta("network_projectile_kind", "grenade")
	add_child(grenade)
	var exclusions: Array[PhysicsBody3D] = []
	if entities[owner_id] is PhysicsBody3D:
		exclusions.append(entities[owner_id])
	grenade.launch(entities[owner_id], start, launch_velocity, exclusions)

func lan_throw_axe(entity_id: int, start: Vector3, launch_velocity: Vector3, spin_axis: Vector3) -> void:
	if not local_players_by_entity.has(entity_id):
		return
	if multiplayer.is_server():
		_server_spawn_axe(entity_id, start, launch_velocity, spin_axis)
	else:
		_request_axe.rpc_id(1, entity_id, start, launch_velocity, spin_axis)

@rpc("any_peer", "call_remote", "reliable")
func _request_axe(entity_id: int, start: Vector3, launch_velocity: Vector3, spin_axis: Vector3) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_spawn_axe(entity_id, start, launch_velocity, spin_axis)

func _server_spawn_axe(owner_id: int, start: Vector3, launch_velocity: Vector3, spin_axis: Vector3) -> void:
	if not entities.has(owner_id) or entities[owner_id].global_position.distance_to(start) > 4.0:
		return
	var available_axes := int(entities[owner_id].get("axes_remaining")) if entities[owner_id].get("axes_remaining") != null else int(server_axes.get(owner_id, 1))
	if available_axes <= 0 or Time.get_ticks_msec() - int(server_throw_time.get(owner_id, 0)) < 700 or launch_velocity.length() > 50.0:
		return
	server_axes[owner_id] = available_axes - 1
	server_throw_time[owner_id] = Time.get_ticks_msec()
	if entities[owner_id].get("axes_remaining") != null:
		entities[owner_id].axes_remaining = server_axes[owner_id]
	var projectile_id := projectile_serial
	projectile_serial += 1
	_spawn_network_axe(projectile_id, owner_id, start, launch_velocity, spin_axis, false)
	_spawn_axe_remote.rpc(projectile_id, owner_id, start, launch_velocity, spin_axis)

@rpc("authority", "call_remote", "reliable")
func _spawn_axe_remote(projectile_id: int, owner_id: int, start: Vector3, launch_velocity: Vector3, spin_axis: Vector3) -> void:
	_spawn_network_axe(projectile_id, owner_id, start, launch_velocity, spin_axis, true)

func _spawn_network_axe(projectile_id: int, owner_id: int, start: Vector3, launch_velocity: Vector3, spin_axis: Vector3, cosmetic: bool) -> void:
	if not entities.has(owner_id):
		return
	var axe := ThrowingAxe.new()
	axe.name = "NetAxe_%d" % projectile_id
	axe.network_cosmetic = cosmetic
	axe.set_meta("network_projectile_id", projectile_id)
	axe.set_meta("network_projectile_kind", "axe")
	add_child(axe)
	var exclusions: Array[PhysicsBody3D] = []
	if entities[owner_id] is PhysicsBody3D:
		exclusions.append(entities[owner_id])
	axe.launch(entities[owner_id], start, launch_velocity, spin_axis, exclusions)

func lan_projectile_blast_impulse(projectile: RigidBody3D, impulse_velocity: Vector3) -> void:
	if not multiplayer.is_server() or not projectile.has_meta("network_projectile_id"):
		return
	_remote_projectile_blast_impulse.rpc(int(projectile.get_meta("network_projectile_id")), str(projectile.get_meta("network_projectile_kind", "")), impulse_velocity)

@rpc("authority", "call_remote", "reliable")
func _remote_projectile_blast_impulse(projectile_id: int, projectile_kind: String, impulse_velocity: Vector3) -> void:
	for candidate in get_tree().get_nodes_in_group("physics_projectiles"):
		if int(candidate.get_meta("network_projectile_id", -1)) != projectile_id or str(candidate.get_meta("network_projectile_kind", "")) != projectile_kind:
			continue
		if candidate.has_method("apply_explosion_impulse"):
			candidate.apply_explosion_impulse(impulse_velocity)
		elif candidate is RigidBody3D:
			candidate.freeze = false
			candidate.sleeping = false
			candidate.linear_velocity += impulse_velocity
		return

func lan_toggle_vehicle(entity_id: int) -> void:
	if not local_players_by_entity.has(entity_id):
		return
	if multiplayer.is_server():
		_server_toggle_vehicle(entity_id)
	else:
		_request_vehicle_toggle.rpc_id(1, entity_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_vehicle_toggle(entity_id: int) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_toggle_vehicle(entity_id)

func _server_toggle_vehicle(peer_id: int) -> void:
	if not entities.has(peer_id) or not entities[peer_id].alive:
		return
	var actor: Node = entities[peer_id]
	if actor.current_vehicle:
		actor.current_vehicle.leave_seat(actor)
		return
	var nearest: Node
	var nearest_distance := 3.2 * 3.2
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if not is_instance_valid(vehicle) or not vehicle.alive or vehicle.get_open_seat_for(actor).is_empty():
			continue
		var distance: float = (actor as Node3D).global_position.distance_squared_to(vehicle.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = vehicle
	if nearest:
		nearest.request_seat(actor)

func _send_vehicle_input() -> void:
	for controller in local_players:
		if not controller.current_vehicle or controller.vehicle_seat != "driver":
			continue
		var movement: Vector2 = controller.control_vector()
		var value := Vector3(-movement.y, movement.x, 1.0 if controller.control_pressed("jump") else 0.0)
		if multiplayer.is_server():
			controller.current_vehicle.set_network_driver_input(value)
		else:
			_submit_vehicle_input.rpc_id(1, controller.entity_id, value)

@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _submit_vehicle_input(entity_id: int, value: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if NetworkSession.peer_owns_entity(peer_id, entity_id) and entities.has(entity_id) and entities[entity_id].current_vehicle:
		entities[entity_id].current_vehicle.set_network_driver_input(value)

func _on_local_player_died(attacker: Node, victim_id: int) -> void:
	var attacker_id := int(attacker.get("entity_id")) if attacker and attacker.get("entity_id") != null else 0
	if multiplayer.is_server():
		_handle_death(victim_id, attacker_id)
	else:
		_report_local_death.rpc_id(1, victim_id, attacker_id)

func _on_local_respawn_skip_requested(entity_id: int) -> void:
	var controller: Node = local_players_by_entity.get(entity_id)
	if not controller or controller.alive:
		return
	if multiplayer.is_server():
		_accept_respawn_skip(entity_id)
	else:
		_request_respawn_skip.rpc_id(1, entity_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_respawn_skip(entity_id: int) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_accept_respawn_skip(entity_id)

func _accept_respawn_skip(entity_id: int) -> void:
	if NetworkSession.players.has(entity_id) and server_respawns_pending.has(entity_id) and entities.has(entity_id):
		server_respawn_skip_requests[entity_id] = true

@rpc("any_peer", "call_remote", "reliable")
func _report_local_death(victim_id: int, attacker_id: int) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), victim_id):
		_handle_death(victim_id, attacker_id)

func _on_network_avatar_died(victim: Node, attacker_id: int) -> void:
	if multiplayer.is_server():
		_handle_death(victim.entity_id, attacker_id)

func _on_server_bot_killed(bot: Node, attacker: Node) -> void:
	var attacker_id := _entity_id_for(attacker)
	_handle_death(_entity_id_for(bot), attacker_id)

func _drop_lan_carried_powerups(victim: Node) -> void:
	var records: Array = victim.get_meta("death_powerup_drops", [])
	victim.remove_meta("death_powerup_drops")
	if records.is_empty():
		var counts: Dictionary = victim.get_meta("powerup_handoff_counts", {})
		if victim.get("jetpack_owned") == true:
			records.append({"kind": "jetpack", "handoffs": int(counts.get("jetpack", 0))})
		if victim.get("coil_gun_owned") == true:
			records.append({"kind": "coil_gun", "handoffs": int(counts.get("coil_gun", 0))})
		if victim.get("suicide_vest_owned") == true and victim.get("suicide_vest_triggering") != true:
			records.append({"kind": "suicide_vest", "handoffs": int(counts.get("suicide_vest", 0))})
		if float(victim.get("ricochet_time")) > 0.0:
			records.append({"kind": "ricochet", "handoffs": int(counts.get("ricochet", 0))})
		if str(victim.get("physics_utility_id")) == "force":
			records.append({"kind": "force", "handoffs": int(counts.get("force", 0))})
		var grenade_kind := str(victim.get("grenade_type")) if victim.get("grenade_type") != null else "normal"
		if grenade_kind in ["gravity_bomb", "sticky_bomb"]:
			records.append({"kind": grenade_kind, "handoffs": int(counts.get(grenade_kind, 0))})
	victim.remove_meta("powerup_handoff_counts")
	var victim_position := (victim as Node3D).global_position
	for index in records.size():
		var record: Dictionary = records[index] if records[index] is Dictionary else {"kind": str(records[index]), "handoffs": 0}
		var handoffs := maxi(0, int(record.get("handoffs", 0)))
		if randf() > pow(POWERUP_HANDOFF_DROP_DECAY, handoffs):
			continue
		var angle := TAU * float(index) / float(maxi(records.size(), 1))
		var position: Vector3 = victim_position + Vector3(cos(angle) * 0.65, 0.25, sin(angle) * 0.65)
		_spawn_authoritative_pickup(str(record.get("kind", "")), position, {"death_drop": true, "handoff_count": handoffs + 1})

func _handle_death(victim_id: int, attacker_id: int) -> void:
	if not match_active or result_pending:
		return
	var victim: Node = entities.get(victim_id)
	_clear_player_portals(victim_id)
	var dismembered_limbs: Array[String] = []
	if victim != null:
		var victim_limbs = victim.get("last_dismembered_limbs")
		if victim_limbs is Array:
			for limb in victim_limbs:
				dismembered_limbs.append(str(limb))
	var was_headshot := "head" in dismembered_limbs
	var hit_position: Vector3 = victim.get("last_hit_position") if victim != null else Vector3.ZERO
	var hit_normal: Vector3 = victim.get("last_hit_normal") if victim != null else Vector3.UP
	_record_lan_leaderboard_elimination(victim_id, attacker_id)
	_entity_died.rpc(victim_id, dismembered_limbs, hit_position, hit_normal, attacker_id)
	_show_kill_feed_event(attacker_id, victim_id, was_headshot)
	if victim != null:
		_drop_lan_carried_powerups(victim)
		_maybe_spawn_lan_perk_drop(victim.global_position)
	killstreaks[victim_id] = 0
	multi_kill_counts[victim_id] = 0
	multi_kill_deadlines[victim_id] = 0
	var teamkill := _apply_lan_teamkill_penalty(victim_id, attacker_id)
	if local_players_by_entity.has(victim_id):
		_apply_local_death_feedback(attacker_id, local_players_by_entity[victim_id])
	if infection_mode:
		var was_survivor: bool = victim != null and victim.team_id == 0
		if was_survivor:
			_set_lan_infected(victim_id)
		if _lan_survivor_count() == 0:
			_finish_match(1)
			return
		_award_lan_streak(attacker_id, victim_id)
		_respawn_later(victim_id)
		return
	if juggernaut_mode:
		if attacker_id == lan_juggernaut_id and attacker_id != victim_id:
			match_scores[attacker_id] = int(match_scores.get(attacker_id, 0)) + 1
			_award_lan_streak(attacker_id, victim_id)
			if int(match_scores[attacker_id]) >= score_target:
				_finish_match(attacker_id)
				return
		if victim_id == lan_juggernaut_id:
			var next_holder := attacker_id if attacker_id != 0 and attacker_id != victim_id and entities.has(attacker_id) else _random_lan_living_id(victim_id)
			if next_holder != 0:
				_set_lan_juggernaut(next_holder)
		_respawn_later(victim_id)
		return
	if king_mode:
		_award_lan_streak(attacker_id, victim_id)
		_respawn_later(victim_id)
		return
	if attacker_id != 0 and attacker_id != victim_id and entities.has(attacker_id):
		if not teamkill:
			if local_players_by_entity.has(attacker_id):
				_show_local_elimination(attacker_id)
			elif attacker_id < 1000:
				_confirm_elimination.rpc_id(NetworkSession.get_owner_peer_id(attacker_id), attacker_id)
		var key: int = int(entities[attacker_id].team_id) if team_deathmatch else attacker_id
		var awarded_points := _award_lan_match_points(victim_id, attacker_id)
		awarded_points += _award_lan_collateral_bonus(victim_id, attacker_id)
		match_scores[key] = int(match_scores.get(key, 0)) + awarded_points
		_award_lan_streak(attacker_id, victim_id)
		if int(match_scores[key]) >= score_target:
			_finish_match(key)
			return
	if sudden_death and attacker_id != 0 and not teamkill:
		_finish_match(entities[attacker_id].team_id if team_deathmatch else attacker_id)
		return
	_respawn_later(victim_id)

func _award_lan_match_points(victim_id: int, attacker_id: int) -> int:
	if mode_id not in ["ffa", "tdm"] or not entities.has(victim_id) or not entities.has(attacker_id):
		return 0
	if attacker_id == victim_id or entities[attacker_id].team_id == entities[victim_id].team_id:
		return 0
	var now := Time.get_ticks_msec()
	var chain := int(multi_kill_counts.get(attacker_id, 0)) + 1 if now <= int(multi_kill_deadlines.get(attacker_id, 0)) else 1
	multi_kill_counts[attacker_id] = chain
	multi_kill_deadlines[attacker_id] = now + MULTI_KILL_WINDOW_MSEC
	var points := BASE_KILL_POINTS + (MULTI_KILL_BONUS if chain >= 2 and not _is_lan_collateral_followup(attacker_id) else 0)
	leaderboard_points[attacker_id] = int(leaderboard_points.get(attacker_id, 0)) + points
	if local_players_by_entity.has(attacker_id):
		_receive_score_award(attacker_id, points, _multi_kill_callout(chain))
	elif attacker_id < 1000:
		_receive_score_award.rpc_id(NetworkSession.get_owner_peer_id(attacker_id), attacker_id, points, _multi_kill_callout(chain))
	return points

func _is_lan_collateral_followup(attacker_id: int) -> bool:
	if str(server_weapon_by_peer.get(attacker_id, "")) != "sniper":
		return false
	if Time.get_ticks_msec() - int(server_shot_time.get(attacker_id, 0)) > 750:
		return false
	var state: Dictionary = server_collateral_state.get(attacker_id, {})
	return not state.is_empty() and int(state.get("serial", -1)) == int(server_shot_serial.get(attacker_id, 0)) and int(state.get("kills", 0)) >= 1

func _apply_lan_teamkill_penalty(victim_id: int, attacker_id: int) -> bool:
	if attacker_id == 0 or attacker_id == victim_id or not entities.has(victim_id) or not entities.has(attacker_id):
		return false
	if entities[attacker_id].team_id != entities[victim_id].team_id:
		return false
	leaderboard_points[attacker_id] = int(leaderboard_points.get(attacker_id, 0)) - TEAMKILL_PENALTY
	multi_kill_counts[attacker_id] = 0
	multi_kill_deadlines[attacker_id] = 0
	if team_deathmatch:
		var team := int(entities[attacker_id].team_id)
		match_scores[team] = int(match_scores.get(team, 0)) - TEAMKILL_PENALTY
	if local_players_by_entity.has(attacker_id):
		_receive_score_award(attacker_id, -TEAMKILL_PENALTY, "TEAMKILL")
	elif attacker_id < 1000:
		_receive_score_award.rpc_id(NetworkSession.get_owner_peer_id(attacker_id), attacker_id, -TEAMKILL_PENALTY, "TEAMKILL")
	return true

func _award_lan_collateral_bonus(victim_id: int, attacker_id: int) -> int:
	if mode_id not in ["ffa", "tdm"] or not entities.has(victim_id) or not entities.has(attacker_id):
		return 0
	if str(server_weapon_by_peer.get(attacker_id, "")) != "sniper" or Time.get_ticks_msec() - int(server_shot_time.get(attacker_id, 0)) > 750:
		return 0
	if entities[attacker_id].team_id == entities[victim_id].team_id:
		return 0
	var state: Dictionary = server_collateral_state.get(attacker_id, {})
	if state.is_empty() or int(state.get("serial", -1)) != int(server_shot_serial.get(attacker_id, 0)):
		return 0
	state["kills"] = int(state.get("kills", 0)) + 1
	if int(state["kills"]) < 2 or bool(state.get("awarded", false)):
		server_collateral_state[attacker_id] = state
		return 0
	state["awarded"] = true
	server_collateral_state[attacker_id] = state
	leaderboard_points[attacker_id] = int(leaderboard_points.get(attacker_id, 0)) + COLLATERAL_BONUS
	if local_players_by_entity.has(attacker_id):
		_receive_score_award(attacker_id, COLLATERAL_BONUS, "COLLATERAL")
	elif attacker_id < 1000:
		_receive_score_award.rpc_id(NetworkSession.get_owner_peer_id(attacker_id), attacker_id, COLLATERAL_BONUS, "COLLATERAL")
	return COLLATERAL_BONUS

func award_collateral_bonus(_attacker: Node, _kill_count: int) -> void:
	# LAN collateral scoring is resolved by the host after authoritative deaths.
	pass

@rpc("authority", "call_remote", "reliable")
func _receive_score_award(entity_id: int, points: int, callout: String) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if controller:
		controller.show_score_award(points, callout)

func _award_lan_streak(attacker_id: int, victim_id: int) -> void:
	if attacker_id == 0 or attacker_id == victim_id or not entities.has(attacker_id):
		return
	if entities.has(victim_id) and entities[attacker_id].team_id == entities[victim_id].team_id:
		return
	if entities.has(victim_id) and not bool(entities[victim_id].get_meta("gun_streak_kill", false)):
		return
	if entities.has(victim_id) and bool(entities[victim_id].get_meta("killstreak_exempt_death", false)):
		return
	var attacker: Node = entities[attacker_id]
	var attacker_perks = attacker.get("active_perks")
	if attacker_perks is not Array or not attacker.has_method("apply_perk"):
		return
	if local_players_by_entity.has(attacker_id):
		_show_local_elimination(attacker_id)
	elif attacker_id < 1000:
		_confirm_elimination.rpc_id(NetworkSession.get_owner_peer_id(attacker_id), attacker_id)
	killstreaks[attacker_id] = int(killstreaks.get(attacker_id, 0)) + 1
	var streak := int(killstreaks[attacker_id])
	if attacker.has_method("on_confirmed_kill"):
		attacker.on_confirmed_kill()
	if "scavenger" in attacker_perks and attacker_id < 1000 and not local_players_by_entity.has(attacker_id):
		_receive_scavenger_restock.rpc_id(NetworkSession.get_owner_peer_id(attacker_id), attacker_id)
	server_grenades[attacker_id] = int(attacker.get("grenades_remaining")) if attacker.get("grenades_remaining") != null else int(server_grenades.get(attacker_id, 3))
	if streak in PERK_MILESTONES:
		var reward := PerkCatalog.random_unowned(attacker_perks)
		if not reward.is_empty() and attacker.apply_perk(str(reward["id"])):
			server_grenades[attacker_id] = int(attacker.get("grenades_remaining")) if attacker.get("grenades_remaining") != null else int(server_grenades.get(attacker_id, 3))
			var message := "%s ACTIVATED" % str(reward["name"]).to_upper()
			_notify_lan_reward(attacker_id, message, true)
	match streak:
		3:
			_grant_lan_streak(attacker_id, "ammo_drop")
		6:
			var target_position: Vector3 = entities[victim_id].global_position if entities.has(victim_id) else attacker.global_position
			_grant_lan_streak(attacker_id, "airstrike", target_position)
		10:
			_grant_lan_streak(attacker_id, "attack_dogs")
		35:
			_grant_lan_streak(attacker_id, "nuke")

func _grant_lan_streak(owner_id: int, reward_id: String, bot_target: Vector3 = Vector3.ZERO) -> void:
	if owner_id < 1000:
		var inventory: Array = streak_inventories.get(owner_id, [])
		inventory.append(reward_id)
		streak_inventories[owner_id] = inventory
		_sync_lan_streak_inventory(owner_id)
		_notify_lan_reward(owner_id, "%s EARNED — PRESS ~ TO DEPLOY" % reward_id.replace("_", " ").to_upper(), false, true)
		return
	if not _deploy_lan_streak(owner_id, reward_id, bot_target) and reward_id == "nuke":
		_wait_to_deploy_lan_bot_nuke(owner_id)

func use_local_killstreak(entity_id := 0) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id, local_player)
	if not controller or not controller.alive:
		return
	var origin: Vector3 = controller.camera.global_position
	var direction: Vector3 = -controller.camera.global_transform.basis.z
	if multiplayer.is_server():
		_server_use_killstreak(controller.entity_id, origin, direction)
	else:
		_request_use_killstreak.rpc_id(1, controller.entity_id, origin, direction)

@rpc("any_peer", "call_remote", "reliable")
func _request_use_killstreak(entity_id: int, origin: Vector3, direction: Vector3) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_use_killstreak(entity_id, origin, direction)

func _server_use_killstreak(owner_id: int, origin: Vector3, direction: Vector3) -> void:
	if not entities.has(owner_id) or entities[owner_id].alive != true:
		return
	var inventory: Array = streak_inventories.get(owner_id, [])
	if inventory.is_empty() or origin.distance_to(entities[owner_id].global_position) > 5.0 or direction.length_squared() < 0.5:
		return
	var reward_id := str(inventory[0])
	if reward_id == "nuke" and _nuke_in_progress():
		_notify_lan_reward(owner_id, "NUKE ALREADY INBOUND — REWARD HELD")
		return
	if not _deploy_lan_streak(owner_id, reward_id, _lan_streak_target(entities[owner_id], origin, direction.normalized())):
		return
	inventory.pop_front()
	streak_inventories[owner_id] = inventory
	_sync_lan_streak_inventory(owner_id)

func _deploy_lan_streak(owner_id: int, reward_id: String, target_position: Vector3 = Vector3.ZERO) -> bool:
	if not entities.has(owner_id):
		return false
	var owner: Node3D = entities[owner_id]
	match reward_id:
		"ammo_drop":
			var drop_angle := randf() * TAU
			var drop_position: Vector3 = _ground_pickup_position(owner.global_position + Vector3(cos(drop_angle) * 2.6, -0.95, sin(drop_angle) * 2.6))
			_spawn_authoritative_pickup("ammo_drop", drop_position, {})
			_notify_lan_reward(owner_id, "AMMO DROP CALLED IN", false, true)
		"airstrike":
			_spawn_lan_strike(owner_id, target_position, "airstrike")
		"attack_dogs":
			_spawn_lan_attack_dog_pack(owner_id)
		"nuke":
			return _spawn_lan_strike(owner_id, owner.global_position, "nuke")
	return true

func _wait_to_deploy_lan_bot_nuke(owner_id: int) -> void:
	while entities.has(owner_id) and is_inside_tree():
		while _nuke_in_progress() and entities.has(owner_id):
			await get_tree().create_timer(0.5, true, false, true).timeout
		if not entities.has(owner_id):
			return
		if _deploy_lan_streak(owner_id, "nuke", entities[owner_id].global_position):
			return
		await get_tree().create_timer(0.25, true, false, true).timeout

func _lan_streak_target(owner: Node3D, origin: Vector3, direction: Vector3) -> Vector3:
	var endpoint: Vector3 = origin + direction * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1)
	query.exclude = [owner.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", endpoint)

func _sync_lan_streak_inventory(owner_id: int) -> void:
	var inventory: Array = streak_inventories.get(owner_id, [])
	if local_players_by_entity.has(owner_id):
		_receive_streak_inventory(owner_id, inventory)
	elif owner_id < 1000:
		_receive_streak_inventory.rpc_id(NetworkSession.get_owner_peer_id(owner_id), owner_id, inventory)

@rpc("authority", "call_remote", "reliable")
func _receive_streak_inventory(entity_id: int, rewards: Array) -> void:
	if not combat_hud or not local_players_by_entity.has(entity_id):
		return
	var typed_rewards: Array[String] = []
	for reward in rewards:
		typed_rewards.append(str(reward))
	if local_players_by_entity[entity_id] == local_player:
		combat_hud.set_streak_inventory(typed_rewards)

func _maybe_spawn_lan_perk_drop(position: Vector3) -> void:
	if multiplayer.is_server() and randf() <= RANDOM_PERK_DROP_CHANCE:
		_spawn_authoritative_pickup("perk", position, PerkCatalog.random_perk())

func _notify_lan_reward(owner_id: int, message: String, play_reward_sound := false, streak_callout := false) -> void:
	if local_players_by_entity.has(owner_id):
		_receive_lan_reward(owner_id, message, play_reward_sound, streak_callout)
	elif owner_id < 1000:
		_receive_lan_reward.rpc_id(NetworkSession.get_owner_peer_id(owner_id), owner_id, message, play_reward_sound, streak_callout)

@rpc("authority", "call_remote", "reliable")
func _receive_lan_reward(entity_id: int, message: String, play_sound := false, streak_callout := false) -> void:
	if combat_hud:
		var display_message := message if local_players_by_entity.get(entity_id) == local_player else "%s: %s" % [_entity_display_name(entity_id), message]
		if streak_callout:
			combat_hud.show_streak_callout(display_message, 5.0)
		else:
			combat_hud.show_notification(display_message, 4.0)
		if play_sound:
			combat_hud.play_reward_sound()

@rpc("authority", "call_remote", "reliable")
func _receive_scavenger_restock(entity_id: int) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if controller and controller.alive:
		controller.apply_scavenger_restock()

func _spawn_lan_strike(owner_id: int, position: Vector3, strike_type: String) -> bool:
	if not multiplayer.is_server() or not entities.has(owner_id):
		return false
	var strike := KillstreakStrike.new()
	add_child(strike)
	if not strike.activate(entities[owner_id], position, strike_type, false):
		return false
	_play_lan_strike.rpc(owner_id, position, strike_type)
	_notify_lan_reward(owner_id, "%s CALLED IN" % strike_type.to_upper(), false, true)
	return true

@rpc("authority", "call_remote", "reliable")
func _play_lan_strike(owner_id: int, position: Vector3, strike_type: String) -> void:
	var strike := KillstreakStrike.new()
	add_child(strike)
	strike.activate(entities.get(owner_id), position, strike_type, true)

func _spawn_lan_attack_dog_pack(owner_id: int) -> void:
	if not multiplayer.is_server() or not entities.has(owner_id):
		return
	var previous_count := attack_dogs.size()
	super._spawn_attack_dog_pack(entities[owner_id], owner_id, false)
	for index in range(previous_count, attack_dogs.size()):
		var dog: Node = attack_dogs[index]
		network_attack_dogs[dog.dog_id] = dog
	if local_players_by_entity.has(owner_id):
		_notify_attack_dogs(owner_id)
	elif owner_id < 1000:
		_notify_attack_dogs.rpc_id(NetworkSession.get_owner_peer_id(owner_id), owner_id)

@rpc("authority", "call_remote", "reliable")
func _notify_attack_dogs(_entity_id: int) -> void:
	if combat_hud:
		combat_hud.show_streak_callout("10 KILLSTREAK — ATTACK DOGS DEPLOYED", 5.0)

func _on_attack_dog_killed(dog: Node, _attacker: Node) -> void:
	_remove_attack_dog_from_targets(dog)
	await get_tree().create_timer(4.0).timeout
	attack_dogs.erase(dog)
	network_attack_dogs.erase(int(dog.get("dog_id")))
	if is_instance_valid(dog):
		dog.queue_free()

func _on_attack_dog_expired(dog: Node) -> void:
	_remove_attack_dog_from_targets(dog)
	attack_dogs.erase(dog)
	network_attack_dogs.erase(int(dog.get("dog_id")))
	if is_instance_valid(dog):
		dog.queue_free()

func _random_lan_living_id(excluded_id: int) -> int:
	var candidates: Array[int] = []
	for id in entities:
		if int(id) != excluded_id and entities[id].alive:
			candidates.append(int(id))
	return candidates.pick_random() if not candidates.is_empty() else 0

@rpc("authority", "call_remote", "reliable")
func _entity_died(entity_id: int, dismembered_limbs: Array[String], hit_position: Vector3, hit_normal: Vector3, attacker_id: int) -> void:
	var was_headshot := "head" in dismembered_limbs
	_show_kill_feed_event(attacker_id, entity_id, was_headshot)
	if not dismembered_limbs.is_empty():
		_show_network_dismemberment(entity_id, dismembered_limbs, hit_position, hit_normal)
	if local_players_by_entity.has(entity_id):
		_apply_local_death_feedback(attacker_id, local_players_by_entity[entity_id])
	elif entities.has(entity_id) and entities[entity_id].has_method("play_death"):
		entities[entity_id].play_death()

func _show_network_dismemberment(entity_id: int, limbs: Array[String], hit_position: Vector3, hit_normal: Vector3) -> void:
	if not entities.has(entity_id):
		return
	var entity: Node = entities[entity_id]
	if entity.has_method("show_network_dismemberment"):
		entity.show_network_dismemberment(limbs, hit_position, hit_normal)
		return
	var rig = entity.get("soldier_rig")
	if rig != null and rig.has_method("remove_limbs"):
		rig.remove_limbs(limbs)

@rpc("authority", "call_remote", "reliable")
func _confirm_elimination(entity_id: int) -> void:
	_show_local_elimination(entity_id)

func _show_local_elimination(entity_id: int) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if not controller:
		return
	controller.hud.show_hitmarker(true)
	controller.hud.show_elimination()
	if controller == local_player:
		combat_hud.show_notification("ELIMINATION", 1.5)

func _apply_local_death_feedback(attacker_id := 0, controller: CharacterBody3D = null) -> void:
	if controller == null:
		controller = local_player
	if not controller:
		return
	if controller != local_player:
		controller.alive = false
		controller.health = 0.0
		controller.velocity = Vector3.ZERO
		controller._cancel_axe_throw(false)
		controller.set_death_presentation_active(true)
		controller.health_changed.emit(0.0, controller.max_health)
		return
	if local_death_feedback_active:
		if not is_instance_valid(deathcam) and entities.has(attacker_id):
			_start_deathcam(entities[attacker_id], _attacker_display_name(attacker_id))
		return
	local_death_feedback_active = true
	controller.alive = false
	controller.health = 0.0
	controller.velocity = Vector3.ZERO
	controller._cancel_axe_throw(false)
	controller.set_death_presentation_active(true)
	controller.health_changed.emit(0.0, controller.max_health)
	controller.damaged.emit(999.0, controller.global_position)
	if controller.death_voice_audio and not controller.death_voice_audio.playing:
		controller._play_death_voice()
	var killer_name := _attacker_display_name(attacker_id)
	if not entities.has(attacker_id) or not _start_deathcam(entities[attacker_id], killer_name):
		combat_hud.show_death_screen(killer_name, 3.0)

func _attacker_display_name(attacker_id: int) -> String:
	return _entity_display_name(attacker_id, "ENVIRONMENT")

func _entity_display_name(entity_id: int, fallback := "UNKNOWN CONTACT") -> String:
	if entity_id == 0:
		return fallback
	if NetworkSession.players.has(entity_id):
		return str(NetworkSession.players[entity_id].get("name", "PLAYER"))
	if entities.has(entity_id):
		var entity: Node = entities[entity_id]
		var display = entity.get("display_name")
		if display != null and not str(display).is_empty():
			return str(display)
		return str(entity.name).replace("_", " ")
	return fallback

func _show_kill_feed_event(attacker_id: int, victim_id: int, was_headshot: bool) -> void:
	if combat_hud:
		combat_hud.add_kill_feed(_entity_display_name(attacker_id, "ENVIRONMENT"), _entity_display_name(victim_id), was_headshot)

func _respawn_later(entity_id: int) -> void:
	if server_respawns_pending.has(entity_id):
		return
	server_respawns_pending[entity_id] = true
	server_respawn_skip_requests.erase(entity_id)
	if NetworkSession.players.has(entity_id):
		var deadline := Time.get_ticks_msec() + 3000
		while match_active and entities.has(entity_id) and not bool(server_respawn_skip_requests.get(entity_id, false)) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	else:
		# Bots always serve the complete respawn cooldown.
		await get_tree().create_timer(3.0).timeout
	server_respawns_pending.erase(entity_id)
	server_respawn_skip_requests.erase(entity_id)
	if not match_active or not entities.has(entity_id):
		return
	var entity: Node = entities[entity_id]
	killstreaks[entity_id] = 0
	server_grenades[entity_id] = 3
	server_axes[entity_id] = 1
	entity.respawn_at(_best_network_spawn(entity.team_id, entity))
	if local_players_by_entity.has(entity_id):
		var controller: CharacterBody3D = local_players_by_entity[entity_id]
		controller.set_weapon_views_enabled(true)
		_apply_pending_local_lan_loadout(controller)
		if controller == local_player:
			_stop_deathcam()
			local_death_feedback_active = false
			combat_hud.hide_death_screen()

func _resolve_time_limit() -> void:
	if infection_mode:
		_finish_match(0 if _lan_survivor_count() > 0 else 1)
		return
	var leaders := _leaders()
	if leaders.size() == 1:
		_finish_match(leaders[0])
	else:
		sudden_death = true
		if combat_hud:
			combat_hud.show_message("SUDDEN DEATH")

func _finish_match(winner_key: int) -> void:
	if result_pending:
		return
	result_pending = true
	match_active = false
	_match_finished.rpc(winner_key)
	if NetworkSession.is_dedicated_server:
		DedicatedServer.notify_match_completed(winner_key)
		return
	var local_key: int = int(local_player.team_id) if team_deathmatch else local_player.entity_id
	_present_lan_match_result(winner_key, local_key)

@rpc("authority", "call_remote", "reliable")
func _match_finished(winner_key: int) -> void:
	match_active = false
	result_pending = true
	if not local_player or not combat_hud:
		return
	var local_key: int = int(local_player.team_id) if team_deathmatch else local_player.entity_id
	_present_lan_match_result(winner_key, local_key)

func _present_lan_match_result(winner_key: int, local_key: int) -> void:
	_stop_deathcam()
	combat_hud.hide_death_screen()
	var victory := winner_key == local_key
	var mode_name := str(NetworkSession.config.get("mode", "ffa")).replace("_", " ").to_upper()
	var map_name := str(NetworkSession.config.get("map", "training arena")).replace("_", " ").to_upper()
	if local_player:
		local_player.set_physics_process(false)
		local_player.set_process_input(false)
		local_player.set_process_unhandled_input(false)
		if local_player.touch_controls:
			local_player.touch_controls.set_controls_enabled(false)
		if local_player.rifle:
			local_player.set_weapon_views_enabled(false)
	combat_hud.show_match_result(
		victory,
		"NETWORK AFTER ACTION  //  %s" % mode_name,
		"%02d   —   %02d" % [combat_hud.player_score_value, combat_hud.bot_score_value],
		"CONTRACT COMPLETE" if victory else "HOSTILE FORCE PREVAILED",
		["MODE  %s" % mode_name, "MAP  %s" % map_name, "BEST STREAK  %02d" % hud_best_streak],
		"REPLAY",
		"HOME"
	)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _result_return_to_lobby() -> void:
	_stop_deathcam()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkSession.is_host:
		NetworkSession.return_everyone_to_lobby()
	else:
		NetworkSession.leave_session(true)

func _result_return_to_main_menu() -> void:
	_stop_deathcam()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkSession.leave_session(false)
	get_tree().call_deferred("change_scene_to_file", "res://root.tscn")

func _update_match_hud() -> void:
	if not combat_hud or not local_player:
		return
	if king_mode:
		if team_deathmatch:
			combat_hud.set_score(int(match_scores.get(0, 0)), int(match_scores.get(1, 0)), score_target)
		else:
			var leader_score := 0
			for value in match_scores.values():
				leader_score = maxi(leader_score, int(value))
			combat_hud.set_score(leader_score, int(match_scores.get(local_player.entity_id, 0)), score_target)
		combat_hud.set_mode_caption("HILL MOVES IN %02d" % maxi(0, int(ceil(hill_move_timer))))
	elif infection_mode:
		var survivors := _lan_survivor_count()
		combat_hud.set_score(survivors, entities.size() - survivors, maxi(entities.size(), 1))
		combat_hud.set_mode_caption("SURVIVE UNTIL  %02d:%02d" % [maxi(0, int(ceil(remaining_time))) / 60, maxi(0, int(ceil(remaining_time))) % 60])
	elif team_deathmatch:
		combat_hud.set_score(int(match_scores.get(0, 0)), int(match_scores.get(1, 0)), score_target)
	else:
		var leader_score := 0
		for value in match_scores.values():
			leader_score = maxi(leader_score, int(value))
		combat_hud.set_score(leader_score, int(match_scores.get(local_player.entity_id, 0)), score_target)
	var seconds := maxi(0, int(ceil(remaining_time)))
	timer_label.text = "SUDDEN DEATH" if sudden_death else "%02d:%02d" % [seconds / 60, seconds % 60]
	var local_streak := int(killstreaks.get(local_player.entity_id, 0))
	hud_best_streak = maxi(hud_best_streak, local_streak)
	if local_streak != hud_last_streak:
		hud_last_streak = local_streak
		combat_hud.set_killstreak(local_streak, _lan_next_reward_text(local_streak))
	var perk_names: Array[String] = []
	for perk_id in local_player.active_perks:
		perk_names.append(PerkCatalog.name_for(perk_id))
	if perk_names != hud_last_perks:
		hud_last_perks = perk_names.duplicate()
		combat_hud.set_perks(perk_names)

func _record_lan_leaderboard_elimination(victim_id: int, attacker_id: int) -> void:
	if victim_id == 0 or not entities.has(victim_id):
		return
	leaderboard_deaths[victim_id] = int(leaderboard_deaths.get(victim_id, 0)) + 1
	if attacker_id == 0 or attacker_id == victim_id or not entities.has(attacker_id):
		return
	if entities[attacker_id].team_id == entities[victim_id].team_id:
		return
	leaderboard_kills[attacker_id] = int(leaderboard_kills.get(attacker_id, 0)) + 1

func _update_lan_leaderboard() -> void:
	var rows: Array[Dictionary] = []
	var local_id: int = int(local_player.entity_id)
	for raw_id in entities:
		var entity_id := int(raw_id)
		var entity: Node = entities[raw_id]
		if not is_instance_valid(entity):
			continue
		var score := int(leaderboard_kills.get(entity_id, 0))
		if mode_id in ["ffa", "tdm"]:
			score = int(leaderboard_points.get(entity_id, 0))
		elif king_mode:
			score = int(match_scores.get(entity_id if not team_deathmatch else int(entity.team_id), 0))
		var status := ""
		if infection_mode:
			status = "SURVIVOR" if entity.team_id == 0 else "INFECTED"
		elif juggernaut_mode and entity_id == lan_juggernaut_id:
			status = "JUGGERNAUT"
		elif team_deathmatch:
			status = "BLUE" if entity.team_id == 0 else "RED"
		rows.append({
			"name": _entity_display_name(entity_id),
			"score": score,
			"kills": int(leaderboard_kills.get(entity_id, 0)),
			"deaths": int(leaderboard_deaths.get(entity_id, 0)),
			"team": int(entity.team_id) if team_deathmatch else -1,
			"local": entity_id == local_id,
			"status": status
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		if int(a["kills"]) != int(b["kills"]):
			return int(a["kills"]) > int(b["kills"])
		return str(a["name"]) < str(b["name"])
	)
	var mode_name := (("FFA" if not team_deathmatch else "TDM") + " KING OF THE HILL") if king_mode else str(NetworkSession.config.get("mode", "ffa")).replace("_", " ").to_upper()
	var caption := "FIRST TO %02d" % score_target
	if team_deathmatch:
		caption = "BLUE %02d  —  %02d RED" % [int(match_scores.get(0, 0)), int(match_scores.get(1, 0))]
	if infection_mode:
		var survivors := _lan_survivor_count()
		caption = "SURVIVORS %02d  —  %02d INFECTED" % [survivors, entities.size() - survivors]
	combat_hud.set_leaderboard(mode_name + " LEADERBOARD", caption, rows)

func _lan_next_reward_text(streak: int) -> String:
	for threshold in [3, 6, 10, 35]:
		if streak < threshold:
			return "%d %s" % [threshold, STREAK_REWARDS[threshold]]
	return "MAX STREAK"

func _apply_local_authoritative_state(state: Dictionary, controller: CharacterBody3D) -> void:
	var was_alive: bool = controller.alive
	var previous_health: float = controller.health
	var authoritative_health := float(state.get("health", controller.health))
	controller.alive = state.get("alive", controller.alive) == true
	controller.team_id = int(state.get("team", controller.team_id))
	controller.set_mode_juggernaut(state.get("mode_juggernaut", false) == true)
	controller.set_mode_infected(state.get("mode_infected", false) == true)
	controller.health = authoritative_health
	controller.health_changed.emit(controller.health, controller.max_health)
	if controller.health < previous_health and was_alive:
		controller.damaged.emit(previous_health - controller.health, state.get("damage_source", controller.global_position))
	if was_alive and not controller.alive:
		_apply_local_death_feedback(0, controller)
	elif not was_alive and controller.alive:
		controller.respawn_at(state.get("position", controller.global_position))
		controller.set_weapon_views_enabled(true)
		_apply_pending_local_lan_loadout(controller)
		if controller == local_player:
			_stop_deathcam()
			local_death_feedback_active = false
			combat_hud.hide_death_screen()
	var authoritative_perks: Array = state.get("perks", [])
	for perk_id in authoritative_perks:
		if perk_id not in controller.active_perks:
			controller.apply_perk(perk_id)
	if authoritative_perks.is_empty() and not controller.active_perks.is_empty():
		controller.reset_combat_perks()
	var has_jetpack: bool = state.get("jetpack", false) == true
	if has_jetpack and not controller.jetpack_owned:
		controller.acquire_jetpack()
	elif not has_jetpack and controller.jetpack_owned:
		controller._remove_jetpack()
	var has_coil: bool = state.get("coil_gun", false) == true
	if has_coil and not controller.coil_gun_owned:
		controller.acquire_coil_gun()
	elif not has_coil and controller.coil_gun_owned:
		controller._remove_coil_gun()
	var has_vest: bool = state.get("suicide_vest", false) == true
	if has_vest and not controller.suicide_vest_owned and not controller.suicide_vest_triggering:
		controller.acquire_suicide_vest()
		if controller == local_player:
			combat_hud.show_notification("C4 EQUIPPED — FIRE TO DETONATE", 4.0)
	elif not has_vest and controller.suicide_vest_owned:
		controller.suicide_vest_owned = false
	var utility_id := str(state.get("physics_utility", ""))
	if utility_id != controller.physics_utility_id:
		if utility_id.is_empty():
			controller.clear_physics_utility()
		else:
			controller.acquire_physics_utility(utility_id)
	controller.ricochet_time = float(state.get("ricochet_time", controller.ricochet_time))
	controller.grenades_remaining = int(state.get("grenades", controller.grenades_remaining))
	controller.grenade_type = str(state.get("grenade_type", "normal"))
	controller.axes_remaining = int(state.get("axes", controller.axes_remaining))
	controller.hud.set_grenade_count(controller.grenades_remaining)
	controller.hud.set_grenade_type(controller.grenade_type)
	controller.hud.set_axe_count(controller.axes_remaining)

func _update_server_pickups(delta: float) -> void:
	if not _has_pickup_type("jetpack"):
		jetpack_spawn_timer -= delta
		if jetpack_spawn_timer <= 0.0 and not waypoints.is_empty():
			_spawn_authoritative_pickup("jetpack", _pickup_position(), {})
			jetpack_spawn_timer = INF
	if not _has_pickup_type("coil_gun"):
		coil_gun_spawn_timer -= delta
		if coil_gun_spawn_timer <= 0.0 and not waypoints.is_empty():
			_spawn_authoritative_pickup("coil_gun", _pickup_position(), {})
			coil_gun_spawn_timer = INF
	if not _has_pickup_type("suicide_vest"):
		suicide_vest_spawn_timer -= delta
		if suicide_vest_spawn_timer <= 0.0 and not waypoints.is_empty():
			_spawn_authoritative_pickup("suicide_vest", _pickup_position(), {})
			suicide_vest_spawn_timer = INF
	for kind in physics_pickup_timers:
		if _has_pickup_type(kind):
			continue
		physics_pickup_timers[kind] = float(physics_pickup_timers[kind]) - delta
		if float(physics_pickup_timers[kind]) <= 0.0 and not waypoints.is_empty():
			_spawn_authoritative_pickup(kind, _pickup_position(), {})
			physics_pickup_timers[kind] = INF

func _pickup_position() -> Vector3:
	return _powerup_spawn_position()

func _spawn_authoritative_pickup(kind: String, position: Vector3, data: Dictionary) -> void:
	var id := pickup_serial
	pickup_serial += 1
	var pickup := _make_pickup(kind, data)
	if not pickup:
		return
	pickup.set_meta("powerup_handoff_count", int(data.get("handoff_count", 0)))
	pickup.name = "NetPickup_%d" % id
	pickup.position = position
	add_child(pickup)
	network_pickups[id] = {"node": pickup, "kind": kind, "position": position, "data": data.duplicate(true)}
	if kind == "perk":
		pickup.collected.connect(_on_perk_pickup_collected.bind(id))
	elif kind in ["ricochet", "force", "gravity_bomb", "sticky_bomb"]:
		pickup.collected.connect(_on_physics_network_pickup_collected.bind(id))
	else:
		pickup.collected.connect(_on_simple_pickup_collected.bind(id, kind))

func _make_pickup(kind: String, data: Dictionary) -> Area3D:
	if kind == "perk":
		var perk := PerkPickup.new()
		perk.configure(str(data.get("id", "sleight_of_hand")), str(data.get("name", "Sleight of Hand")))
		return perk
	if kind == "jetpack":
		return JetpackPickup.new()
	if kind == "coil_gun":
		return CoilGunPickup.new()
	if kind == "suicide_vest":
		return SuicideVestPickup.new()
	if kind == "ammo_drop":
		return AmmoDropPickup.new()
	if kind in ["ricochet", "force", "gravity_bomb", "sticky_bomb"]:
		var physics_pickup := PhysicsPowerupPickup.new()
		physics_pickup.configure(kind)
		return physics_pickup
	return null

func _on_physics_network_pickup_collected(kind: String, collector: Node, id: int) -> void:
	var collector_id := _entity_id_for(collector)
	if collector_id != 0:
		if kind in ["gravity_bomb", "sticky_bomb"]:
			server_grenades[collector_id] = int(collector.get("grenades_remaining"))
		var names := {"ricochet": "RICOCHET ACTIVE", "force": "FORCE MANIPULATOR EQUIPPED", "gravity_bomb": "GRAVITY BOMBS EQUIPPED", "sticky_bomb": "STICKY BOMBS EQUIPPED"}
		_notify_lan_reward(collector_id, str(names[kind]), true)
	_finish_pickup_collection(id, kind)

func _on_perk_pickup_collected(_perk_id: String, perk_name: String, collector: Node, id: int) -> void:
	var collector_id := _entity_id_for(collector)
	if collector_id != 0:
		_notify_lan_reward(collector_id, "%s ACQUIRED" % perk_name.to_upper(), true)
	_finish_pickup_collection(id, "perk")

func _on_simple_pickup_collected(collector: Node, id: int, kind: String) -> void:
	var collector_id := _entity_id_for(collector)
	if kind == "ammo_drop":
		if collector_id != 0:
			server_grenades[collector_id] = int(collector.get("grenades_remaining")) if collector.get("grenades_remaining") != null else 3
			server_axes[collector_id] = int(collector.get("axes_remaining")) if collector.get("axes_remaining") != null else 1
			if collector_id < 1000 and not local_players_by_entity.has(collector_id):
				_receive_ammo_drop.rpc_id(NetworkSession.get_owner_peer_id(collector_id), collector_id)
	if collector_id != 0:
		var pickup_names := {"jetpack": "JETPACK ACQUIRED", "coil_gun": "COIL GUN ACQUIRED", "suicide_vest": "C4 EQUIPPED", "ammo_drop": "AMMO DROP COLLECTED — FULLY RESTOCKED"}
		if pickup_names.has(kind):
			_notify_lan_reward(collector_id, str(pickup_names[kind]), true)
	_finish_pickup_collection(id, kind)

@rpc("authority", "call_remote", "reliable")
func _receive_ammo_drop(entity_id: int) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if controller:
		controller.collect_ammo_drop()

func _finish_pickup_collection(id: int, kind: String) -> void:
	if not network_pickups.has(id):
		return
	network_pickups.erase(id)
	if kind == "jetpack":
		jetpack_spawn_timer = _powerup_interval(16.0, 30.0)
	elif kind == "coil_gun":
		coil_gun_spawn_timer = _powerup_interval(22.0, 40.0)
	elif kind == "suicide_vest":
		suicide_vest_spawn_timer = _powerup_interval(35.0, 65.0)
	elif kind in ["ricochet", "force", "gravity_bomb", "sticky_bomb"]:
		physics_pickup_timers[kind] = _powerup_interval(35.0, 55.0)

func lan_trigger_suicide_vest(entity_id: int) -> void:
	var controller: CharacterBody3D = local_players_by_entity.get(entity_id)
	if not controller or not controller.suicide_vest_owned or controller.suicide_vest_triggering:
		return
	if multiplayer.is_server():
		_server_trigger_suicide_vest(entity_id)
	else:
		_request_suicide_vest.rpc_id(1, entity_id)

func bot_trigger_suicide_vest(bot: Node) -> void:
	if not multiplayer.is_server() or not is_instance_valid(bot):
		return
	var bot_id := _entity_id_for(bot)
	if bot_id != 0:
		_server_trigger_suicide_vest(bot_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_suicide_vest(entity_id: int) -> void:
	if multiplayer.is_server() and NetworkSession.peer_owns_entity(multiplayer.get_remote_sender_id(), entity_id):
		_server_trigger_suicide_vest(entity_id)

func _server_trigger_suicide_vest(entity_id: int) -> void:
	if not entities.has(entity_id):
		return
	var wearer: Node3D = entities[entity_id]
	if not wearer.alive or wearer.get("suicide_vest_owned") != true or wearer.get("suicide_vest_triggering") == true:
		return
	_spawn_network_vest_charge(entity_id, wearer, true)
	_start_suicide_vest_charge_remote.rpc(entity_id)

@rpc("authority", "call_remote", "reliable")
func _start_suicide_vest_charge_remote(entity_id: int) -> void:
	if entities.has(entity_id):
		_spawn_network_vest_charge(entity_id, entities[entity_id], false)

func _spawn_network_vest_charge(entity_id: int, wearer: Node3D, authoritative: bool) -> void:
	wearer.set("suicide_vest_owned", false)
	wearer.set("suicide_vest_triggering", true)
	var charge := SuicideVestCharge.new()
	add_child(charge)
	charge.detonated.connect(_on_network_vest_detonated.bind(entity_id))
	charge.arm(wearer, authoritative)

func _on_network_vest_detonated(entity_id: int) -> void:
	if entities.has(entity_id):
		var entity: Node = entities[entity_id]
		if entity.has_method("_remove_suicide_vest"):
			entity._remove_suicide_vest()
		else:
			entity.set("suicide_vest_triggering", false)

func _has_pickup_type(kind: String) -> bool:
	for record in network_pickups.values():
		if record["kind"] == kind:
			return true
	return false

func _pickup_snapshot() -> Dictionary:
	var result := {}
	for id in network_pickups:
		var record: Dictionary = network_pickups[id]
		if is_instance_valid(record["node"]):
			result[id] = {"kind": record["kind"], "position": record["node"].global_position, "data": record["data"]}
	return result

func _register_server_vehicles() -> void:
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if not is_instance_valid(vehicle):
			continue
		vehicle.network_mode = true
		var instance_id := vehicle.get_instance_id()
		if not vehicle_ids.has(instance_id):
			vehicle_ids[instance_id] = vehicle_serial
			vehicle.network_id = vehicle_serial
			vehicle_serial += 1

func _server_vehicle_by_network_id(id: int) -> Node:
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if is_instance_valid(vehicle) and vehicle.network_id == id:
			return vehicle
	return null

func _vehicle_snapshot() -> Dictionary:
	var result := {}
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if not is_instance_valid(vehicle):
			continue
		var instance_id := vehicle.get_instance_id()
		if not vehicle_ids.has(instance_id):
			continue
		var id: int = vehicle_ids[instance_id]
		var city_actor_id := int(vehicle.get("actor_id")) if vehicle.get("actor_id") != null else 0
		result[id] = {"transform": vehicle.global_transform, "velocity": vehicle.velocity, "health": vehicle.health, "alive": vehicle.alive, "speed": vehicle.current_speed, "driver": _entity_id_for(vehicle.driver), "passenger": _entity_id_for(vehicle.passenger), "city_actor": city_actor_id}
	return result

func _sync_client_vehicles(states: Dictionary) -> void:
	if multiplayer.is_server():
		return
	for raw_id in states:
		var id := int(raw_id)
		var state: Dictionary = states[raw_id]
		if not client_vehicles.has(id):
			var city_actor_id := int(state.get("city_actor", 0))
			var vehicle: Node = null
			var city := _city_map()
			if city_actor_id != 0 and city:
				vehicle = city.get_dynamic_actor(city_actor_id)
			if not vehicle:
				vehicle = CombatVehicle.new()
				vehicle.name = "NetVehicle_%d" % id
				add_child(vehicle)
			vehicle.network_mode = true
			vehicle.network_id = id
			client_vehicles[id] = vehicle
		var replica: Node = client_vehicles[id]
		replica.global_transform = state["transform"]
		replica.velocity = state.get("velocity", Vector3.ZERO)
		replica.health = float(state.get("health", replica.health))
		replica.alive = state.get("alive", replica.alive) == true
		replica.current_speed = float(state.get("speed", 0.0))
		_apply_client_seat(replica, "driver", int(state.get("driver", 0)))
		_apply_client_seat(replica, "passenger", int(state.get("passenger", 0)))
	for id in client_vehicles.keys():
		if not states.has(id) and not states.has(str(id)):
			var vehicle: Node = client_vehicles[id]
			_detach_client_seat(vehicle, "driver")
			_detach_client_seat(vehicle, "passenger")
			if vehicle.get("actor_id") == null:
				vehicle.queue_free()
			client_vehicles.erase(id)

func _apply_client_seat(vehicle: Node, seat: String, entity_id: int) -> void:
	var current: Node = vehicle.driver if seat == "driver" else vehicle.passenger
	var desired: Node = entities.get(entity_id) if entity_id != 0 else null
	if current == desired:
		return
	if current:
		current.leave_vehicle(current.global_position, true)
		vehicle._remove_occupant_visual(seat)
	if seat == "driver":
		vehicle.driver = desired
	else:
		vehicle.passenger = desired
	if desired:
		desired.enter_vehicle(vehicle, seat)
		vehicle._create_occupant_visual(seat, desired)
		if seat == "driver":
			vehicle._start_engine()

func _detach_client_seat(vehicle: Node, seat: String) -> void:
	_apply_client_seat(vehicle, seat, 0)

func _sync_client_pickups(states: Dictionary) -> void:
	if multiplayer.is_server():
		return
	for raw_id in states:
		var id := int(raw_id)
		if network_pickups.has(id):
			continue
		var state: Dictionary = states[raw_id]
		var pickup := _make_pickup(state["kind"], state.get("data", {}))
		if not pickup:
			continue
		pickup.position = state["position"]
		add_child(pickup)
		pickup.monitoring = false
		pickup.collision_mask = 0
		network_pickups[id] = {"node": pickup, "kind": state["kind"], "position": state["position"], "data": state.get("data", {})}
	for id in network_pickups.keys():
		if not states.has(id) and not states.has(str(id)):
			var record: Dictionary = network_pickups[id]
			if is_instance_valid(record["node"]):
				record["node"].queue_free()
			network_pickups.erase(id)

func _spawn_for(team: int, index: int) -> Vector3:
	if infection_mode and not waypoints.is_empty():
		var waypoint_index := posmod(index * 7 + team * 3, waypoints.size())
		var cycle := index / waypoints.size()
		var angle := float(index) * 2.399
		return waypoints[waypoint_index] + Vector3(cos(angle), 0.0, sin(angle)) * minf(float(cycle) * 0.65, 1.3)
	var koth_spawns := _highrise_koth_spawn_points()
	var pool: Array = koth_spawns if not koth_spawns.is_empty() else ((player_spawns + bot_spawns) if not team_deathmatch else (player_spawns if team == 0 else bot_spawns))
	var result: Vector3 = pool[index % pool.size()]
	var cycle := index / pool.size()
	if cycle > 0:
		var angle := float(index) * 2.399
		result += Vector3(cos(angle), 0.0, sin(angle)) * float(cycle) * 2.2
	return result

func _best_network_spawn(team: int, respawning: Node) -> Vector3:
	var koth_spawns := _highrise_koth_spawn_points()
	var pool: Array = koth_spawns if not koth_spawns.is_empty() else (waypoints if infection_mode and not waypoints.is_empty() else ((player_spawns + bot_spawns) if not team_deathmatch else (player_spawns if team == 0 else bot_spawns)))
	var best: Vector3 = pool[0]
	var best_distance := -1.0
	for candidate_value in pool:
		var candidate: Vector3 = candidate_value
		var nearest := INF
		for entity in entities.values():
			if entity != respawning and entity.alive and entity.team_id != team:
				nearest = minf(nearest, candidate.distance_to(entity.global_position))
		if nearest > best_distance:
			best_distance = nearest
			best = candidate
	return best

func _least_populated_team() -> int:
	var counts := [0, 0]
	for entity in entities.values():
		if entity.team_id in [0, 1]:
			counts[entity.team_id] += 1
	return 0 if counts[0] <= counts[1] else 1

func _team_from_snapshot(_entity_id: int) -> int:
	return _least_populated_team() if team_deathmatch else _entity_id

func _entity_id_for(entity: Node) -> int:
	if not entity:
		return 0
	for entity_id in entities:
		if entities[entity_id] == entity:
			return int(entity_id)
	if entity.get("owner_entity_id") != null:
		return int(entity.get("owner_entity_id"))
	return 0

func _leaders() -> Array[int]:
	var leaders: Array[int] = []
	var high := -1
	for key in match_scores:
		var score := int(match_scores[key])
		if score > high:
			high = score
			leaders = [int(key)]
		elif score == high:
			leaders.append(int(key))
	return leaders
