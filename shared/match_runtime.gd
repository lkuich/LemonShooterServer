extends Node3D

const CombatBot = preload("res://scripts/combat_bot.gd")
const CombatVehicle = preload("res://scripts/combat_vehicle.gd")
const PerkPickup = preload("res://scripts/perk_pickup.gd")
const JetpackPickup = preload("res://scripts/jetpack_pickup.gd")
const CoilGunPickup = preload("res://scripts/coil_gun_pickup.gd")
const SuicideVestPickup = preload("res://scripts/suicide_vest_pickup.gd")
const PhysicsPowerupPickup = preload("res://scripts/physics_powerup_pickup.gd")
const AttackDog = preload("res://scripts/attack_dog.gd")
const CityMap = preload("res://scripts/city_map.gd")
const MysteryBox = preload("res://scripts/mystery_box.gd")
const CombatantNames = preload("res://scripts/combatant_names.gd")
const PerkCatalog = preload("res://scripts/perk_catalog.gd")
const AmmoDropPickup = preload("res://scripts/ammo_drop_pickup.gd")
const KillstreakStrike = preload("res://scripts/killstreak_strike.gd")
const MAP_SURFACE_MATERIALS_PATH := "res://scripts/map_surface_materials.gd"
const WAREHOUSE_MAP_PATH := "res://maps/warehouse_mobile.glb"
const WAREHOUSE_SERVER_PATH := "res://maps/warehouse_server.scn"
const SUBURBAN_TEST_SITE_PATH := "res://maps/suburban_test_site/suburban_test_site.tscn"
const SUBURBAN_SERVER_PATH := "res://maps/suburban_test_site/suburban_server.scn"
const PLAYER_CONTROLLER_PATH := "res://scripts/player_controller.gd"
const COMBAT_HUD_PATH := "res://scripts/combat_hud.gd"
const SETTINGS_MENU_PATH := "res://scripts/settings_menu.gd"
const INVENTORY_MENU_PATH := "res://scripts/inventory_menu.gd"
const DEATHCAM_CONTROLLER_PATH := "res://scripts/deathcam_controller.gd"
const MUSIC_TRACK_PATHS := [
	"res://sounds/music/Bulletproof Club.mp3",
	"res://sounds/music/Bulletproof Pulse.mp3",
	"res://sounds/music/GlassJawLanding.mp3",
	"res://sounds/music/GlassJawLanding2.mp3"
]
const TWIN_BASTION_SCALE := 0.41
const HIGHRISE_SCALE := 0.58
const HILL_RADIUS := 6.0
const HILL_MOVE_INTERVAL := 25.0
const HILL_SCORE_TARGET := 100
const INFECTION_DURATION := 180.0
const INFECTION_COMBATANT_CAP := 50
const JUGGERNAUT_SCORE_TARGET := 15
const DEFAULT_MATCH_DURATION := 10.0 * 60.0
const FFA_SPAWN_RING_RADIUS := 2.2
const FFA_SPAWN_RING_SLOTS := 6
const POWERUP_HANDOFF_DROP_DECAY := 0.65

var player: CharacterBody3D
var bots: Array[CharacterBody3D] = []
var player_spawns := [Vector3(0, 1.0, 27), Vector3(-17, 1.0, 25), Vector3(17, 1.0, 25)]
var bot_spawns := [Vector3(-18, 1.0, -27), Vector3(-9, 1.0, -29), Vector3(0, 1.0, -27), Vector3(9, 1.0, -29), Vector3(18, 1.0, -27)]
var waypoints: Array[Vector3] = []
var powerup_spawn_points: Array[Vector3] = []
var community_ffa_spawns: Array[Vector3] = []
var community_hill_points: Array[Vector3] = []
var community_vehicle_points: Array[Vector3] = []
var powerup_spawn_cursor := 0
var combat_hud: CanvasLayer
var player_score := 0
var bot_score := 0
var ffa_scores := {}
var hill_scores := {}
var leaderboard_kills := {}
var leaderboard_deaths := {}
var leaderboard_points := {}
var juggernaut_scores := {}
var score_target := 20
var team_deathmatch := false
var match_active := true
var loadout_intermission_active := false
var loadout_intermission_remaining := 0.0
var inventory_menu: CanvasLayer
var music_player: AudioStreamPlayer
var music_tracks: Array[AudioStream] = []
var current_track := -1
var music_track_queue: Array[int] = []
var vehicles: Array[CharacterBody3D] = []
var player_killstreak := 0
var player_best_killstreak := 0
var active_perk_names: Array[String] = []
var perk_pickups: Array[Area3D] = []
var jetpack_pickup: Area3D
var jetpack_spawn_timer := 0.0
var coil_gun_pickup: Area3D
var coil_gun_spawn_timer := 0.0
var suicide_vest_pickup: Area3D
var suicide_vest_spawn_timer := 0.0
var physics_pickups: Dictionary = {}
var physics_pickup_timers := {"ricochet": 0.0, "force": 0.0, "gravity_bomb": 0.0, "sticky_bomb": 0.0}
var mode_id := "bots"
var juggernaut_mode := false
var infection_mode := false
var king_mode := false
var current_juggernaut: Node
var juggernaut_marker: Node3D
var hill_root: Node3D
var hill_position := Vector3.ZERO
var hill_move_timer := 0.0
var hill_score_fraction := Vector2.ZERO
var infection_time_left := INFECTION_DURATION
var match_time_left := DEFAULT_MATCH_DURATION
var sudden_death := false
var attack_dogs: Array[CharacterBody3D] = []
var attack_dog_serial := 1
var combatant_streaks: Dictionary = {}
var player_streak_inventory: Array[String] = []
var multi_kill_counts: Dictionary = {}
var multi_kill_deadlines: Dictionary = {}
var last_scored_sniper_shot: Dictionary = {}
var deathcam: Node
var player_respawn_skip_requested := false

const PERK_MILESTONES := [2, 4, 6, 8, 12]
const RANDOM_PERK_DROP_CHANCE := 0.24
const STREAK_REWARDS := {3: "Ammo Drop", 6: "Airstrike", 10: "Attack Dogs", 35: "Nuke"}
const LOADOUT_INTERMISSION_DURATION := 5.0
const BASE_KILL_POINTS := 10
const MULTI_KILL_BONUS := 10
const COLLATERAL_BONUS := 10
const TEAMKILL_PENALTY := 10
const MULTI_KILL_WINDOW_MSEC := 2000
const VEHICLE_RESPAWN_DELAY := 15.0
const VEHICLE_RESPAWN_RETRY_DELAY := 2.0

func _ready() -> void:
	_configure_special_mode()
	_ensure_audio_buses()
	_build_world()
	_build_arena()
	_build_waypoints()
	_spawn_player()
	_spawn_mystery_box()
	_spawn_bots()
	_initialize_special_mode()
	_update_leaderboard()
	jetpack_spawn_timer = _powerup_interval(18.0, 35.0)
	coil_gun_spawn_timer = _powerup_interval(28.0, 50.0)
	suicide_vest_spawn_timer = _powerup_interval(35.0, 65.0)
	physics_pickup_timers = {
		"ricochet": _powerup_interval(20.0, 35.0),
		"force": _powerup_interval(32.0, 50.0),
		"gravity_bomb": _powerup_interval(26.0, 44.0),
		"sticky_bomb": _powerup_interval(34.0, 52.0)
	}
	if GameSession.bot_map_id not in ["highrise", "suburban_test_site"] and not (infection_mode and GameSession.bot_map_id == "city"):
		call_deferred("_spawn_initial_vehicles")
	_start_music()
	_begin_loadout_intermission()

func _process(delta: float) -> void:
	if loadout_intermission_active:
		_update_loadout_intermission(delta)
		return
	if combat_hud and player and combat_hud.is_leaderboard_visible():
		_update_leaderboard()
	if not match_active or not player:
		return
	_update_special_mode(delta)
	if not match_active:
		return
	if infection_mode:
		return
	_update_match_timer(delta)
	if not match_active:
		return
	if not player.jetpack_owned and not is_instance_valid(jetpack_pickup):
		jetpack_spawn_timer -= delta
		if jetpack_spawn_timer <= 0.0:
			_spawn_jetpack_pickup()
	var coil_gun_in_loadout: bool = player.rifle.primary_weapon_id == "coil_gun"
	if not player.coil_gun_owned and not coil_gun_in_loadout and not is_instance_valid(coil_gun_pickup):
		coil_gun_spawn_timer -= delta
		if coil_gun_spawn_timer <= 0.0:
			_spawn_coil_gun_pickup()
	if not player.suicide_vest_owned and not player.suicide_vest_triggering and not is_instance_valid(suicide_vest_pickup):
		suicide_vest_spawn_timer -= delta
		if suicide_vest_spawn_timer <= 0.0:
			_spawn_suicide_vest_pickup()
	for kind in physics_pickup_timers:
		if is_instance_valid(physics_pickups.get(kind)):
			continue
		physics_pickup_timers[kind] = float(physics_pickup_timers[kind]) - delta
		if float(physics_pickup_timers[kind]) <= 0.0:
			_spawn_physics_pickup(kind)

func _powerup_interval(minimum: float, maximum: float) -> float:
	var multiplier := float({"scarce": 1.8, "standard": 1.0, "aggressive": 0.6, "mayhem": 0.32}.get(GameSession.powerup_spawn_rate_id, 1.0))
	return randf_range(minimum, maximum) * multiplier

func _powerup_spawn_position() -> Vector3:
	if GameSession.bot_map_id == "training_arena" and not powerup_spawn_points.is_empty():
		var position := powerup_spawn_points[powerup_spawn_cursor % powerup_spawn_points.size()]
		powerup_spawn_cursor += 1
		return position
	return waypoints.pick_random()

func _configure_special_mode() -> void:
	mode_id = GameSession.game_mode_id
	juggernaut_mode = mode_id == "juggernaut"
	infection_mode = mode_id == "infection"
	king_mode = mode_id == "koth"
	team_deathmatch = mode_id in ["tdm", "infection"] or (king_mode and GameSession.koth_team_mode == "tdm")
	if juggernaut_mode:
		score_target = JUGGERNAUT_SCORE_TARGET
	elif king_mode:
		score_target = HILL_SCORE_TARGET
	elif infection_mode:
		score_target = 6
	elif mode_id == "tdm":
		score_target = clampi(GameSession.tdm_score_limit, 500, 10000)
	else:
		score_target = 30 if team_deathmatch else GameSession.get_ffa_score_limit()
	match_time_left = float(clampi(GameSession.tdm_time_limit_minutes, 5, 20)) * 60.0 if mode_id == "tdm" else DEFAULT_MATCH_DURATION

func _update_match_timer(delta: float) -> void:
	if not sudden_death:
		match_time_left = maxf(match_time_left - delta, 0.0)
	combat_hud.set_match_timer(int(ceil(match_time_left)), sudden_death)
	if not sudden_death and match_time_left <= 0.0:
		_resolve_match_time_limit()

func _resolve_match_time_limit() -> void:
	if player_score > bot_score:
		_end_match(true)
	elif bot_score > player_score:
		_end_match(false)
	else:
		sudden_death = true
		combat_hud.set_match_timer(0, true)
		combat_hud.show_notification("SUDDEN DEATH — NEXT SCORE WINS", 4.0)

func _check_score_victory() -> bool:
	if sudden_death and player_score != bot_score:
		_end_match(player_score > bot_score)
		return true
	if player_score >= score_target:
		_end_match(true)
		return true
	if bot_score >= score_target:
		_end_match(false)
		return true
	return false

func _initialize_special_mode() -> void:
	if juggernaut_mode:
		_assign_juggernaut(player)
		combat_hud.show_notification("YOU ARE THE JUGGERNAUT — KILLS SCORE WHILE YOU HOLD THE ROLE", 5.0)
	elif infection_mode:
		infection_time_left = INFECTION_DURATION
		_refresh_infection_targets()
		_update_infection_hud()
		combat_hud.show_notification("SURVIVE THE INFECTION FOR 3 MINUTES", 5.0)
	elif king_mode:
		_build_hill_placeholder()
		_move_hill(true)

func _update_special_mode(delta: float) -> void:
	if king_mode:
		_update_hill(delta)
	elif infection_mode:
		infection_time_left = maxf(infection_time_left - delta, 0.0)
		_update_infection_hud()
		if infection_time_left <= 0.0:
			_end_match(player.team_id == 0)

func _build_hill_placeholder() -> void:
	hill_root = Node3D.new()
	hill_root.name = "MovingHill"
	add_child(hill_root)
	if DedicatedServer.active:
		return
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = HILL_RADIUS
	mesh.bottom_radius = HILL_RADIUS
	mesh.height = 0.14
	mesh.radial_segments = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.85, 1.0, 0.32)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color("#39c8ef")
	material.emission_energy_multiplier = 2.2
	mesh.material = material
	ring.mesh = mesh
	hill_root.add_child(ring)
	var label := Label3D.new()
	label.text = "MOVING HILL"
	label.position.y = 2.3
	label.font_size = 42
	label.modulate = Color("#73e4ff")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hill_root.add_child(label)

func _move_hill(initial := false) -> void:
	if waypoints.is_empty():
		return
	var candidates := _hill_candidates(initial)
	hill_position = (candidates if not candidates.is_empty() else waypoints).pick_random()
	hill_root.position = hill_position - Vector3.UP * 0.92
	hill_move_timer = HILL_MOVE_INTERVAL
	for bot in bots:
		bot.set_objective(hill_position, true)
	combat_hud.show_notification("THE HILL %s" % ("IS ACTIVE" if initial else "HAS MOVED"), 3.0)

func _update_hill(delta: float) -> void:
	hill_move_timer -= delta
	if hill_move_timer <= 0.0:
		_move_hill()
	var status := "CAPTURE THE HILL"
	if team_deathmatch:
		var occupancy := [0, 0]
		for combatant in _all_combatants():
			if combatant.alive and combatant.team_id in [0, 1] and _inside_hill(combatant.global_position):
				occupancy[combatant.team_id] += 1
		var controlling_team := -1
		if occupancy[0] > 0 and occupancy[1] == 0:
			controlling_team = 0
		elif occupancy[1] > 0 and occupancy[0] == 0:
			controlling_team = 1
		if controlling_team >= 0:
			if controlling_team == 0:
				hill_score_fraction.x += delta
				player_score = int(hill_score_fraction.x)
			else:
				hill_score_fraction.y += delta
				bot_score = int(hill_score_fraction.y)
		status = "CONTESTED" if occupancy[0] > 0 and occupancy[1] > 0 else ("BLUE CONTROLS" if controlling_team == 0 else ("RED CONTROLS" if controlling_team == 1 else status))
	else:
		var occupants: Array[CharacterBody3D] = []
		for combatant in _all_combatants():
			if combatant.alive and _inside_hill(combatant.global_position):
				occupants.append(combatant)
		if occupants.size() == 1:
			var holder := occupants[0]
			var holder_id := holder.get_instance_id()
			hill_scores[holder_id] = float(hill_scores.get(holder_id, 0.0)) + delta
			status = "%s CONTROLS" % str(holder.display_name).to_upper()
		elif occupants.size() > 1:
			status = "CONTESTED"
		player_score = int(hill_scores.get(player.get_instance_id(), 0.0))
		bot_score = 0
		for bot in bots:
			if is_instance_valid(bot):
				bot_score = maxi(bot_score, int(hill_scores.get(bot.get_instance_id(), 0.0)))
	combat_hud.set_score(player_score, bot_score, score_target)
	combat_hud.set_mode_caption("%s  •  HILL MOVES IN %02d" % [status, int(ceil(hill_move_timer))])
	_check_score_victory()

func _hill_candidates(initial: bool) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	var source_points := community_hill_points if not community_hill_points.is_empty() else waypoints
	for point in source_points:
		if initial or point.distance_to(hill_position) > 12.0:
			candidates.append(point)
	if GameSession.bot_map_id != "highrise" or candidates.is_empty():
		return candidates
	# Highrise KOTH is an ascent mode: every objective is on the roof while all
	# combatants enter from the ground floor.
	var rooftop_candidates: Array[Vector3] = []
	for point in candidates:
		if point.y >= 12.0:
			rooftop_candidates.append(point)
	return rooftop_candidates if not rooftop_candidates.is_empty() else candidates

func _highrise_koth_spawn_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not king_mode or GameSession.bot_map_id != "highrise":
		return result
	result.assign(player_spawns + bot_spawns)
	return result

func _inside_hill(position: Vector3) -> bool:
	return Vector2(position.x - hill_position.x, position.z - hill_position.z).length() <= HILL_RADIUS and absf(position.y - hill_position.y) <= 3.0

func _all_combatants() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = [player]
	result.append_array(bots)
	return result

func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)

func _build_world() -> void:
	if DedicatedServer.active:
		return
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	var map_environment = ContentRegistry.resolve_map(GameSession.bot_map_id).get("environment", {})
	var background_color := str(map_environment.get("sky_color", "#7895a2")) if map_environment is Dictionary else "#7895a2"
	environment.background_color = Color(background_color) if Color.html_is_valid(background_color) else Color("#7895a2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#aec1c7")
	environment.ambient_light_energy = clampf(float(map_environment.get("ambient_energy", 0.55)), 0.0, 2.0) if map_environment is Dictionary else 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

func _build_arena() -> void:
	var map_definition := ContentRegistry.resolve_map(GameSession.bot_map_id)
	if str(map_definition.get("provider", "")) == "pack":
		_build_community_arena(map_definition)
		return
	if GameSession.bot_map_id == "suburban_test_site":
		_build_suburban_test_site()
		return
	if GameSession.bot_map_id == "city":
		_build_city_arena()
		return
	if GameSession.bot_map_id == "warehouse":
		_build_warehouse_arena()
		return
	if GameSession.bot_map_id == "twin_bastion":
		_build_twin_bastion_arena()
		return
	if GameSession.bot_map_id == "highrise":
		_build_highrise_arena()
		return
	add_child(_box("ArenaFloor", Vector3(52, 0.4, 68), Vector3(0, -0.2, 0), Color("#57646a")))
	# Give the Portal Gun a broad overhead placement surface while retaining
	# enough vertical room for jetpack movement. The roof does not cast a shadow,
	# keeping the graybox arena readable under its existing outdoor lighting.
	var ceiling := _box("ArenaCeiling", Vector3(52, 0.4, 68), Vector3(0, 24.0, 0), Color("#71858e"))
	if not DedicatedServer.active:
		var ceiling_mesh := ceiling.get_child(0) as MeshInstance3D
		ceiling_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ceiling)
	add_child(_box("NorthWall", Vector3(52, 4, 0.6), Vector3(0, 2, -34), Color("#263238")))
	add_child(_box("SouthWall", Vector3(52, 4, 0.6), Vector3(0, 2, 34), Color("#263238")))
	add_child(_box("WestWall", Vector3(0.6, 4, 68), Vector3(-26, 2, 0), Color("#263238")))
	add_child(_box("EastWall", Vector3(0.6, 4, 68), Vector3(26, 2, 0), Color("#263238")))
	# Two broken dividers establish three lanes without sealing off flanks.
	for x in [-8.5, 8.5]:
		for z in [-21.0, -7.0, 8.0, 22.0]:
			add_child(_box("LaneDivider", Vector3(1.0, 3.0, 8.0), Vector3(x, 1.5, z), Color("#35444b")))
	# Central landmark and offset cover create short and medium sightlines.
	add_child(_box("CenterTower", Vector3(6, 4.2, 6), Vector3(0, 2.1, 0), Color("#9a7532")))
	for data in [
		[Vector3(-3.5, 0.65, -15), Vector3(4, 1.3, 1.5)], [Vector3(3.5, 0.65, 16), Vector3(4, 1.3, 1.5)]
	]:
		add_child(_box("Cover", data[1], data[0], Color("#6e7d83")))
	# Four elevated corner positions replace the old isolated cover blocks. Their
	# inward parapets are low enough to fire over while still protecting a
	# crouched player, and the open end walls make each ramp a usable entrance.
	for x in [-20.0, 20.0]:
		for z in [-22.0, 22.0]:
			_build_training_pillbox(Vector3(x, 4.0, z))
	for bridge_z in [-22.0, 22.0]:
		_build_training_pillbox_bridge(bridge_z)
	_build_training_physics_props()

func _build_community_arena(definition: Dictionary) -> void:
	var map_root := ContentRegistry.instantiate_pack_glb(
		str(definition.get("pack_id", "")),
		str(definition.get("asset", ""))
	)
	if not map_root:
		push_error("Community map '%s' could not be instantiated." % GameSession.bot_map_id)
		GameSession.bot_map_id = "training_arena"
		_build_arena()
		return
	map_root.name = "CommunityMap"
	add_child(map_root)
	_generate_community_map_collision(map_root)
	player_spawns = _definition_vectors(definition.get("team_a_spawns", []))
	bot_spawns = _definition_vectors(definition.get("team_b_spawns", []))
	waypoints = _definition_vectors(definition.get("waypoints", []))
	powerup_spawn_points = _definition_vectors(definition.get("pickups", []))
	community_ffa_spawns = _definition_vectors(definition.get("ffa_spawns", []))
	community_hill_points = _definition_vectors(definition.get("hills", []))
	community_vehicle_points = _definition_vectors(definition.get("vehicles", []))

func _generate_community_map_collision(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.create_trimesh_collision()
	for child in node.get_children():
		_generate_community_map_collision(child)

func _definition_vectors(values: Variant) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if values is not Array:
		return result
	for value in values:
		if value is Array and value.size() == 3:
			result.append(Vector3(float(value[0]), float(value[1]), float(value[2])))
	return result

func _build_training_physics_props() -> void:
	var specs := [
		["WestCrateA", "box", Vector3(1.2, 1.2, 1.2), Vector3(-15.0, 0.7, -12.0), 2.0, Color("#d69a4a")],
		["WestCrateB", "box", Vector3(0.9, 0.9, 0.9), Vector3(-13.8, 0.55, -12.0), 1.0, Color("#e0b663")],
		["EastCrateA", "box", Vector3(1.4, 1.0, 1.0), Vector3(15.0, 0.6, 12.0), 3.0, Color("#bd7e3e")],
		["EastCrateB", "box", Vector3(0.8, 1.6, 0.8), Vector3(13.6, 0.9, 12.0), 2.4, Color("#d6aa57")],
		["NorthBarrelA", "cylinder", Vector3(0.9, 1.5, 0.9), Vector3(-5.5, 0.85, -25.0), 2.5, Color("#d15d43")],
		["NorthBarrelB", "cylinder", Vector3(0.9, 1.5, 0.9), Vector3(5.5, 0.85, -25.0), 2.5, Color("#3e99b7")],
		["SouthBarrelA", "cylinder", Vector3(0.9, 1.5, 0.9), Vector3(-5.5, 0.85, 25.0), 2.5, Color("#e2b348")],
		["SouthBarrelB", "cylinder", Vector3(0.9, 1.5, 0.9), Vector3(5.5, 0.85, 25.0), 2.5, Color("#6674ba")],
		["CenterOrbA", "sphere", Vector3(1.0, 1.0, 1.0), Vector3(-5.0, 0.65, -4.0), 1.0, Color("#82e8ff")],
		["CenterOrbB", "sphere", Vector3(1.35, 1.35, 1.35), Vector3(5.0, 0.85, 4.0), 5.5, Color("#9a76df")],
		["WestLaneBeam", "box", Vector3(0.55, 0.55, 3.2), Vector3(-17.0, 0.45, 5.0), 3.5, Color("#7b8c91")],
		["EastLaneBeam", "box", Vector3(0.55, 0.55, 3.2), Vector3(17.0, 0.45, -5.0), 3.5, Color("#7b8c91")],
		["NWDeckCrate", "box", Vector3(1.0, 1.0, 1.0), Vector3(-20.0, 4.6, -22.0), 1.5, Color("#d69a4a")],
		["NEDeckOrb", "sphere", Vector3(1.0, 1.0, 1.0), Vector3(20.0, 4.6, -22.0), 1.2, Color("#82e8ff")],
		["SWDeckBarrel", "cylinder", Vector3(0.85, 1.4, 0.85), Vector3(-20.0, 4.75, 22.0), 2.2, Color("#d15d43")],
		["SEDeckCrate", "box", Vector3(1.1, 1.1, 1.1), Vector3(20.0, 4.65, 22.0), 1.8, Color("#e0b663")]
	]
	for spec in specs:
		_add_training_physics_prop(str(spec[0]), str(spec[1]), spec[2] as Vector3, spec[3] as Vector3, float(spec[4]), spec[5] as Color)

func _add_training_physics_prop(prop_name: String, shape_kind: String, size: Vector3, position: Vector3, prop_mass: float, color: Color) -> void:
	var body := RigidBody3D.new()
	body.name = "TrainingProp_%s" % prop_name
	body.position = position
	body.mass = prop_mass
	body.continuous_cd = true
	body.collision_layer = 1
	body.collision_mask = 1 | 2 | 4 | 16
	body.add_to_group("physics_objects")
	body.add_to_group("training_physics_props")
	var mesh_instance: MeshInstance3D
	if not DedicatedServer.active:
		mesh_instance = MeshInstance3D.new()
	var collision := CollisionShape3D.new()
	match shape_kind:
		"sphere":
			if mesh_instance:
				var mesh := SphereMesh.new()
				mesh.radius = size.x * 0.5
				mesh.height = size.y
				mesh_instance.mesh = mesh
			var shape := SphereShape3D.new()
			shape.radius = size.x * 0.5
			collision.shape = shape
		"cylinder":
			if mesh_instance:
				var mesh := CylinderMesh.new()
				mesh.top_radius = size.x * 0.5
				mesh.bottom_radius = size.z * 0.5
				mesh.height = size.y
				mesh_instance.mesh = mesh
			var shape := CylinderShape3D.new()
			shape.radius = size.x * 0.5
			shape.height = size.y
			collision.shape = shape
		_:
			if mesh_instance:
				var mesh := BoxMesh.new()
				mesh.size = size
				mesh_instance.mesh = mesh
			var shape := BoxShape3D.new()
			shape.size = size
			collision.shape = shape
	if mesh_instance:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = 0.16
		material.roughness = 0.64
		mesh_instance.material_override = material
		body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)

func _build_training_pillbox(platform_center: Vector3) -> void:
	var east_side := platform_center.x > 0.0
	var south_side := platform_center.z > 0.0
	var prefix := "SE" if east_side and south_side else ("NE" if east_side else ("SW" if south_side else "NW"))
	var platform_color := Color("#66757b")
	var bunker_color := Color("#303e44")
	var safety_color := Color("#b88936")
	var platform_y := platform_center.y
	powerup_spawn_points.append(Vector3(platform_center.x, platform_y + 0.35, platform_center.z))
	add_child(_box(prefix + "PillboxDeck", Vector3(10, 0.5, 12), Vector3(platform_center.x, platform_y - 0.25, platform_center.z), platform_color))
	# The rear wall hugs the arena boundary; the low front wall faces the main
	# lanes and provides the actual overlook toward combat below.
	var rear_x := platform_center.x + (4.7 if east_side else -4.7)
	var front_x := platform_center.x + (-4.7 if east_side else 4.7)
	add_child(_box(prefix + "PillboxRear", Vector3(0.6, 2.2, 12), Vector3(rear_x, platform_y + 1.1, platform_center.z), bunker_color))
	# Two parapet wings retain firing cover while leaving a centered doorway for
	# the east-west bridge that joins this pillbox to its opposite number.
	for z_offset in [-4.0, 4.0]:
		add_child(_box(prefix + "PillboxParapet", Vector3(0.6, 1.0, 4.0), Vector3(front_x, platform_y + 0.5, platform_center.z + z_offset), safety_color))
	var outer_z := platform_center.z + (5.7 if south_side else -5.7)
	var entry_z := platform_center.z + (-5.7 if south_side else 5.7)
	add_child(_box(prefix + "PillboxOuterWall", Vector3(10, 2.2, 0.6), Vector3(platform_center.x, platform_y + 1.1, outer_z), bunker_color))
	# Split the ramp-side wall around a four-metre entrance.
	for x_offset in [-3.5, 3.5]:
		add_child(_box(prefix + "PillboxEntryGuard", Vector3(3.0, 2.2, 0.6), Vector3(platform_center.x + x_offset, platform_y + 1.1, entry_z), bunker_color))
	add_child(_box(prefix + "PillboxRoof", Vector3(10.4, 0.4, 12.4), Vector3(platform_center.x, platform_y + 2.4, platform_center.z), bunker_color))
	# A slightly extended run carries the ramp through the deck edge so Jolt sees
	# one clean transition at the doorway. North ramps rise toward -Z; south
	# ramps mirror toward +Z.
	var ramp_angle := atan2(4.0, 12.0) * (-1.0 if south_side else 1.0)
	var ramp_center_z := platform_center.z + (-12.0 if south_side else 12.0)
	add_child(_ramp(prefix + "PillboxRamp", Vector3(4.0, 0.5, 13.2), Vector3(platform_center.x, 1.85, ramp_center_z), ramp_angle, safety_color))
	# Simple support legs make the open space beneath read as intentional rather
	# than as a floating slab, without blocking movement through it.
	for support_x in [-3.8, 3.8]:
		for support_z in [-4.8, 4.8]:
			add_child(_box(prefix + "PillboxSupport", Vector3(0.7, 4.0, 0.7), Vector3(platform_center.x + support_x, 2.0, platform_center.z + support_z), bunker_color))

func _build_training_pillbox_bridge(bridge_z: float) -> void:
	var prefix := "South" if bridge_z > 0.0 else "North"
	var deck_color := Color("#66757b")
	var safety_color := Color("#b88936")
	var structure_color := Color("#303e44")
	# The deck overlaps each pillbox by 30 cm so there is no collision gap at
	# either doorway. Low rails preserve clear views and shooting angles below.
	add_child(_box(prefix + "PillboxBridge", Vector3(30.6, 0.5, 4.0), Vector3(0.0, 3.75, bridge_z), deck_color))
	for rail_z in [-1.8, 1.8]:
		add_child(_box(prefix + "BridgeRail", Vector3(30.6, 0.8, 0.4), Vector3(0.0, 4.4, bridge_z + rail_z), safety_color))
	# Sparse supports keep the floor below playable and make the bridge silhouette
	# legible from the three ground lanes.
	for support_x in [-10.0, 0.0, 10.0]:
		add_child(_box(prefix + "BridgeSupport", Vector3(0.7, 4.0, 0.7), Vector3(support_x, 2.0, bridge_z), structure_color))

func _build_waypoints() -> void:
	if str(ContentRegistry.resolve_map(GameSession.bot_map_id).get("provider", "")) == "pack":
		return
	if GameSession.bot_map_id == "suburban_test_site":
		var map_root := get_node_or_null("SuburbanTestSite")
		if map_root:
			for node in map_root.find_children("*", "Marker3D", true, false):
				if node.is_in_group("navigation_waypoint"):
					waypoints.append((node as Marker3D).global_position)
		return
	if GameSession.bot_map_id == "city":
		waypoints.append_array(CityMap.navigation_points())
		return
	if GameSession.bot_map_id == "warehouse":
		for source_point in [
			Vector2(-15, -10), Vector2(-5, -10), Vector2(5, -10), Vector2(15, -10),
			Vector2(25, -10), Vector2(28, 0), Vector2(28, 10), Vector2(20, 20),
			Vector2(10, 25), Vector2(0, 30), Vector2(-10, 25), Vector2(-10, 15),
			Vector2(0, 15), Vector2(10, 10), Vector2(20, 5)
		]:
			waypoints.append(_warehouse_ground_point(source_point.x, source_point.y))
		return
	if GameSession.bot_map_id == "twin_bastion":
		waypoints.append_array([
			Vector3(-18, 1, -116), Vector3(0, 1, -108), Vector3(18, 1, -116),
			Vector3(-72, 1, -108), Vector3(-48, 1, -88), Vector3(-72, 1, -58),
			Vector3(-42, 1, -42), Vector3(-68, 1, -18), Vector3(-38, 1, -8),
			Vector3(-72, 1, 18), Vector3(-42, 1, 42), Vector3(-68, 1, 72),
			Vector3(-48, 1, 98), Vector3(-72, 1, 116),
			Vector3(72, 1, -108), Vector3(48, 1, -88), Vector3(72, 1, -58),
			Vector3(42, 1, -42), Vector3(68, 1, -18), Vector3(38, 1, -8),
			Vector3(72, 1, 18), Vector3(42, 1, 42), Vector3(68, 1, 72),
			Vector3(48, 1, 98), Vector3(72, 1, 116),
			Vector3(-20, 1, -72), Vector3(18, 1, -56), Vector3(-22, 1, -28),
			Vector3(22, 1, 28), Vector3(-18, 1, 56), Vector3(20, 1, 82),
			Vector3(-18, 1, 116), Vector3(0, 1, 108), Vector3(18, 1, 116)
		])
		for index in waypoints.size():
			waypoints[index] = Vector3(waypoints[index].x * TWIN_BASTION_SCALE, 1.0, waypoints[index].z * TWIN_BASTION_SCALE)
		return
	if GameSession.bot_map_id == "highrise":
		waypoints.append_array([
			# Ground floor and the west ascent.
			Vector3(-20, 1, 26), Vector3(0, 1, 24), Vector3(20, 1, 24),
			Vector3(-24, 1, 8), Vector3(0, 1, 0), Vector3(22, 1, -18),
			# Approach the ramp from its open low end before centering on it. This
			# prevents compact-map bots from trying to cut through the ramp's side.
			Vector3(-31, 1.0, 26), Vector3(-41, 1.0, 26),
			Vector3(-41, 1.6, 18), Vector3(-41, 2.8, 14), Vector3(-41, 4.0, 10),
			Vector3(-41, 5.2, 6), Vector3(-41, 6.4, 2),
			# Second floor circulation and the east ascent.
			Vector3(-32, 7, 0), Vector3(-12, 7, -18), Vector3(0, 7, 18),
			Vector3(14, 7, 10), Vector3(31, 7, 3), Vector3(43, 7.0, 3),
			Vector3(43, 7.6, -2), Vector3(43, 8.8, -6), Vector3(43, 10.0, -10),
			Vector3(43, 11.2, -14), Vector3(43, 12.4, -18), Vector3(43, 12.8, -22),
			# Rooftop main arena.
			Vector3(32, 13, -25), Vector3(-25, 13, -24), Vector3(0, 13, -25), Vector3(25, 13, -24),
			Vector3(-24, 13, 0), Vector3(-10, 13, 12), Vector3(10, 13, -12),
			Vector3(24, 13, 0), Vector3(-22, 13, 24), Vector3(0, 13, 24), Vector3(22, 13, 24)
		])
		for index in waypoints.size():
			waypoints[index] = Vector3(waypoints[index].x * HIGHRISE_SCALE, waypoints[index].y, waypoints[index].z * HIGHRISE_SCALE)
		return
	for x in [-18.0, 0.0, 18.0]:
		for z in [-27.0, -18.0, -9.0, 9.0, 18.0, 27.0]:
			# Corner points sat directly below the elevated decks, so bots could
			# choose them while upstairs and interpolate through the platform floor.
			if absf(x) > 15.0 and absf(z) > 15.0:
				continue
			waypoints.append(Vector3(x, 1.0, z))
	waypoints.append_array([Vector3(-12, 1, 0), Vector3(12, 1, 0), Vector3(-4, 1, -10), Vector3(4, 1, 10)])
	# Explicit ramp approaches and elevated positions let bots claim the new
	# pillboxes instead of only colliding with their support structure.
	for x in [-20.0, 20.0]:
		waypoints.append_array([
			Vector3(x, 1.0, -3.5), Vector3(x, 3.0, -10.0), Vector3(x, 5.0, -17.0), Vector3(x, 5.0, -22.0),
			Vector3(x, 1.0, 3.5), Vector3(x, 3.0, 10.0), Vector3(x, 5.0, 17.0), Vector3(x, 5.0, 22.0)
		])
	for bridge_z in [-22.0, 22.0]:
		for bridge_x in [-12.0, 0.0, 12.0]:
			waypoints.append(Vector3(bridge_x, 5.0, bridge_z))

func _build_warehouse_arena() -> void:
	var scene_path := WAREHOUSE_SERVER_PATH if DedicatedServer.active else WAREHOUSE_MAP_PATH
	var warehouse_map = load(scene_path)
	var map_instance: Node3D = warehouse_map.instantiate()
	map_instance.name = "WarehouseMap"
	add_child(map_instance)
	if not DedicatedServer.active:
		_create_map_collisions(map_instance)
	# A simple ground backup closes hairline seams without adding visual cost.
	add_child(_collision_box("WarehouseGroundFallback", Vector3(72, 0.3, 76), Vector3(-4.3, -0.18, 4.4)))
	player_spawns = [
		_warehouse_ground_point(-12, -10),
		_warehouse_ground_point(0, -10),
		_warehouse_ground_point(12, -10)
	]
	bot_spawns = [
		_warehouse_ground_point(-10, 25),
		_warehouse_ground_point(0, 30),
		_warehouse_ground_point(12, 25),
		_warehouse_ground_point(25, 10),
		_warehouse_ground_point(28, -8)
	]

func _build_suburban_test_site() -> void:
	var scene_path := SUBURBAN_SERVER_PATH if DedicatedServer.active else SUBURBAN_TEST_SITE_PATH
	var suburban_test_site = load(scene_path)
	var map_instance: Node3D = suburban_test_site.instantiate()
	map_instance.name = "SuburbanTestSite"
	add_child(map_instance)
	player_spawns.clear()
	bot_spawns.clear()
	for node in map_instance.find_children("*", "Marker3D", true, false):
		var marker := node as Marker3D
		if marker.is_in_group("team_a_spawn"):
			player_spawns.append(marker.global_position)
		elif marker.is_in_group("team_b_spawn"):
			bot_spawns.append(marker.global_position)

func _build_city_arena() -> void:
	var city := CityMap.new()
	city.name = "CityDistrict"
	add_child(city)
	player_spawns.assign(CityMap.PLAYER_SPAWNS)
	bot_spawns.assign(CityMap.BOT_SPAWNS)

func _build_twin_bastion_arena() -> void:
	var arena := Node3D.new()
	arena.name = "TwinBastionGeometry"
	arena.scale = Vector3(TWIN_BASTION_SCALE, 1.0, TWIN_BASTION_SCALE)
	add_child(arena)
	var concrete := Color("#59666b")
	var dark_concrete := Color("#303d42")
	var cover_color := Color("#718087")
	var relay_color := Color("#a77b32")
	var blue_base := Color("#355b70")
	var red_base := Color("#74443f")
	arena.add_child(_box("BastionFloor", Vector3(200, 0.4, 280), Vector3(0, -0.2, 0), concrete))
	arena.add_child(_box("NorthBoundary", Vector3(200, 5, 1), Vector3(0, 2.5, -140), dark_concrete))
	arena.add_child(_box("SouthBoundary", Vector3(200, 5, 1), Vector3(0, 2.5, 140), dark_concrete))
	arena.add_child(_box("WestBoundary", Vector3(1, 5, 280), Vector3(-100, 2.5, 0), dark_concrete))
	arena.add_child(_box("EastBoundary", Vector3(1, 5, 280), Vector3(100, 2.5, 0), dark_concrete))

	# Mirrored open courtyards. The split front walls leave a wide vehicle gate,
	# while side exits feed the two perimeter avenues.
	for side_value in [-1.0, 1.0]:
		var side := float(side_value)
		var base_z := side * 116.0
		var front_z := side * 98.0
		var base_color: Color = red_base if side < 0.0 else blue_base
		arena.add_child(_box("BaseRearWall", Vector3(72, 7, 2), Vector3(0, 3.5, side * 132.0), base_color))
		arena.add_child(_box("BaseWestWall", Vector3(2, 7, 34), Vector3(-36, 3.5, base_z), base_color))
		arena.add_child(_box("BaseEastWall", Vector3(2, 7, 34), Vector3(36, 3.5, base_z), base_color))
		arena.add_child(_box("BaseFrontWest", Vector3(22, 5, 2), Vector3(-25, 2.5, front_z), base_color))
		arena.add_child(_box("BaseFrontEast", Vector3(22, 5, 2), Vector3(25, 2.5, front_z), base_color))
		arena.add_child(_box("CommandBlock", Vector3(18, 4, 10), Vector3(0, 2, side * 122.0), dark_concrete))
		arena.add_child(_box("CourtyardCoverWest", Vector3(9, 2.2, 3), Vector3(-18, 1.1, side * 111.0), cover_color))
		arena.add_child(_box("CourtyardCoverEast", Vector3(9, 2.2, 3), Vector3(18, 1.1, side * 111.0), cover_color))

	# The relay breaks the longest central sightline without sealing the middle.
	arena.add_child(_box("RelayCore", Vector3(14, 8, 14), Vector3(0, 4, 0), relay_color))
	arena.add_child(_box("RelayWestWing", Vector3(18, 3, 4), Vector3(-16, 1.5, -8), dark_concrete))
	arena.add_child(_box("RelayEastWing", Vector3(18, 3, 4), Vector3(16, 1.5, 8), dark_concrete))
	arena.add_child(_box("RelayNorthShield", Vector3(5, 2.2, 12), Vector3(12, 1.1, -18), cover_color))
	arena.add_child(_box("RelaySouthShield", Vector3(5, 2.2, 12), Vector3(-12, 1.1, 18), cover_color))

	# Staggered mirrored cover defines infantry routes, leaving x=±70 clear as
	# broad Hummer lanes from one base to the other.
	for side_value in [-1.0, 1.0]:
		var side := float(side_value)
		for data in [
			[Vector3(22, 1.5, 78), Vector3(14, 3, 4)],
			[Vector3(48, 1.2, 62), Vector3(8, 2.4, 7)],
			[Vector3(20, 1.2, 44), Vector3(10, 2.4, 4)],
			[Vector3(52, 1.5, 25), Vector3(14, 3, 4)]
		]:
			var p: Vector3 = data[0]
			var size: Vector3 = data[1]
			arena.add_child(_box("RouteCover", size, Vector3(p.x, p.y, p.z * side), cover_color))
			arena.add_child(_box("RouteCoverMirror", size, Vector3(-p.x, p.y, -p.z * side), cover_color))
	# A few low median blocks force vehicle drivers to weave without choking lanes.
	for z in [-72.0, -34.0, 34.0, 72.0]:
		arena.add_child(_box("VehicleMedian", Vector3(8, 1.0, 3), Vector3(-70 if z < 0 else 70, 0.5, z), relay_color))

	player_spawns = [
		Vector3(-18 * TWIN_BASTION_SCALE, 1.0, 118 * TWIN_BASTION_SCALE),
		Vector3(0, 1.0, 110 * TWIN_BASTION_SCALE),
		Vector3(18 * TWIN_BASTION_SCALE, 1.0, 118 * TWIN_BASTION_SCALE)
	]
	bot_spawns = [
		Vector3(-24 * TWIN_BASTION_SCALE, 1.0, -116 * TWIN_BASTION_SCALE),
		Vector3(-12 * TWIN_BASTION_SCALE, 1.0, -108 * TWIN_BASTION_SCALE),
		Vector3(0, 1.0, -110 * TWIN_BASTION_SCALE),
		Vector3(12 * TWIN_BASTION_SCALE, 1.0, -108 * TWIN_BASTION_SCALE),
		Vector3(24 * TWIN_BASTION_SCALE, 1.0, -116 * TWIN_BASTION_SCALE)
	]

func _build_highrise_arena() -> void:
	var arena := Node3D.new()
	arena.name = "HighriseGeometry"
	add_child(arena)
	var concrete := Color("#4f5c62")
	var dark := Color("#263238")
	var glass := Color("#426473")
	var safety := Color("#d1a23c")
	var roof_cover := Color("#738188")
	arena.add_child(_highrise_box("HighriseGround", Vector3(72, 0.5, 72), Vector3(0, -0.25, 0), concrete))
	arena.add_child(_highrise_box("HighriseSecondFloor", Vector3(68, 0.5, 68), Vector3(0, 5.75, 0), concrete))
	arena.add_child(_highrise_box("HighriseRoof", Vector3(72, 0.6, 72), Vector3(0, 11.7, 0), dark))
	# Keep the overlapping landings flush with their floors. Their generous overlap
	# hides collision seams while preserving the compact exterior ramp footprint.
	arena.add_child(_highrise_box("GroundWestLanding", Vector3(16, 0.5, 40), Vector3(-37, -0.25, 10), concrete))
	# Upper landings begin at the ramp lips instead of covering the ascent and
	# forming a low ceiling over the player.
	arena.add_child(_highrise_box("SecondWestLanding", Vector3(16, 0.5, 8), Vector3(-37, 5.75, -5), concrete))
	arena.add_child(_highrise_box("SecondEastLanding", Vector3(16, 0.5, 32), Vector3(37, 5.75, 6), concrete))
	arena.add_child(_highrise_box("RoofEastLanding", Vector3(16, 0.6, 8), Vector3(37, 11.7, -25), dark))
	for x in [-32.0, 32.0]:
		for z in [-32.0, 32.0]:
			arena.add_child(_highrise_box("TowerColumn", Vector3(2.2, 12, 2.2), Vector3(x, 6, z), dark))
	# Simple lower-floor structure keeps the blockout readable and creates cover.
	arena.add_child(_highrise_box("GroundCore", Vector3(14, 5.5, 14), Vector3(0, 2.75, 0), dark))
	arena.add_child(_highrise_box("GroundWestOffice", Vector3(3, 4, 22), Vector3(-14, 2, -10), glass))
	arena.add_child(_highrise_box("GroundEastOffice", Vector3(3, 4, 18), Vector3(16, 2, 12), glass))
	arena.add_child(_highrise_box("SecondCore", Vector3(14, 5.5, 14), Vector3(0, 8.75, 0), dark))
	arena.add_child(_highrise_box("SecondDividerNorth", Vector3(24, 3, 2), Vector3(-15, 7.5, -19), glass))
	arena.add_child(_highrise_box("SecondDividerSouth", Vector3(24, 3, 2), Vector3(15, 7.5, 19), glass))
	# Exterior ramps are the explicit floor links used by players and bot routes.
	var ramp_angle := atan2(6.0, 20.0 * HIGHRISE_SCALE)
	# Extend both ramps through their floor slabs so the low ends emerge flush;
	# this avoids a vertical box edge that CharacterBody3D cannot step onto.
	arena.add_child(_ramp("WestRampToSecond", Vector3(14 * HIGHRISE_SCALE, 0.7, 24.5 * HIGHRISE_SCALE), Vector3(-41 * HIGHRISE_SCALE, 2.5, 10 * HIGHRISE_SCALE), ramp_angle, safety))
	arena.add_child(_ramp("EastRampToRoof", Vector3(14 * HIGHRISE_SCALE, 0.7, 24.5 * HIGHRISE_SCALE), Vector3(43 * HIGHRISE_SCALE, 8.5, -10 * HIGHRISE_SCALE), ramp_angle, safety))
	# Rooftop is the primary arena: a central service core, broken lanes, and a
	# low safety parapet that still permits jetpack escapes and risky knock-offs.
	arena.add_child(_highrise_box("RoofNorthParapet", Vector3(72, 2, 1), Vector3(0, 13, -35.5), safety))
	arena.add_child(_highrise_box("RoofSouthParapet", Vector3(72, 2, 1), Vector3(0, 13, 35.5), safety))
	arena.add_child(_highrise_box("RoofWestParapet", Vector3(1, 2, 72), Vector3(-35.5, 13, 0), safety))
	arena.add_child(_highrise_box("RoofEastParapetNorth", Vector3(1, 2, 4), Vector3(35.5, 13, -34), safety))
	arena.add_child(_highrise_box("RoofEastParapetCenter", Vector3(1, 2, 44), Vector3(35.5, 13, 5), safety))
	arena.add_child(_highrise_box("RoofServiceCore", Vector3(13, 5, 13), Vector3(0, 14.5, 0), glass))
	for data in [
		[Vector3(-22, 13, -15), Vector3(12, 2, 3)], [Vector3(20, 13, -18), Vector3(9, 2, 3)],
		[Vector3(-18, 13, 17), Vector3(8, 2, 4)], [Vector3(22, 13, 14), Vector3(12, 2, 3)],
		[Vector3(-8, 13, -26), Vector3(3, 2, 9)], [Vector3(9, 13, 25), Vector3(3, 2, 9)]
	]:
		arena.add_child(_highrise_box("RoofCover", data[1], data[0], roof_cover))
	# Both teams begin on the ground floor and must use the ascent routes once
	# combat or patrol goals move to the upper decks.
	player_spawns = [
		Vector3(-16 * HIGHRISE_SCALE, 1, 27 * HIGHRISE_SCALE),
		Vector3(0, 1, 27 * HIGHRISE_SCALE),
		Vector3(16 * HIGHRISE_SCALE, 1, 27 * HIGHRISE_SCALE)
	]
	bot_spawns = [
		Vector3(-20 * HIGHRISE_SCALE, 1, -27 * HIGHRISE_SCALE),
		Vector3(-10 * HIGHRISE_SCALE, 1, -25 * HIGHRISE_SCALE),
		Vector3(0, 1, -27 * HIGHRISE_SCALE),
		Vector3(10 * HIGHRISE_SCALE, 1, -25 * HIGHRISE_SCALE),
		Vector3(20 * HIGHRISE_SCALE, 1, -27 * HIGHRISE_SCALE)
	]

func _ramp(node_name: String, size: Vector3, pos: Vector3, angle: float, color: Color) -> StaticBody3D:
	var ramp := _box(node_name, size, pos, color)
	ramp.rotation.x = angle
	return ramp

func _highrise_box(node_name: String, size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var scaled_size := Vector3(size.x * HIGHRISE_SCALE, size.y, size.z * HIGHRISE_SCALE)
	var scaled_position := Vector3(pos.x * HIGHRISE_SCALE, pos.y, pos.z * HIGHRISE_SCALE)
	return _box(node_name, scaled_size, scaled_position, color)

func _warehouse_ground_point(source_x: float, source_y: float) -> Vector3:
	return Vector3(source_x, 1.0, -source_y)

func _create_map_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.create_trimesh_collision()
	for child in node.get_children():
		_create_map_collisions(child)

func _collision_box(node_name: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _spawn_player() -> void:
	var player_controller_script = load(PLAYER_CONTROLLER_PATH)
	player = player_controller_script.new()
	player.name = "Player"
	player.display_name = CombatantNames.random_unique()
	combatant_streaks[player.get_instance_id()] = 0
	var koth_spawns := _highrise_koth_spawn_points()
	player.position = koth_spawns.pick_random() if not koth_spawns.is_empty() else player_spawns[0]
	add_child(player)
	if GameSession.bot_map_id == "twin_bastion":
		player.look_at(Vector3(0, player.global_position.y, -120 * TWIN_BASTION_SCALE), Vector3.UP)
	player.enable_combat_health()
	if mode_id == "bots":
		ffa_scores[player.get_instance_id()] = 0
	if king_mode and not team_deathmatch:
		hill_scores[player.get_instance_id()] = 0.0
	leaderboard_kills[player.get_instance_id()] = 0
	leaderboard_deaths[player.get_instance_id()] = 0
	leaderboard_points[player.get_instance_id()] = 0
	multi_kill_counts[player.get_instance_id()] = 0
	multi_kill_deadlines[player.get_instance_id()] = 0
	juggernaut_scores[player.get_instance_id()] = 0
	var combat_hud_script = load(COMBAT_HUD_PATH)
	combat_hud = combat_hud_script.new()
	add_child(combat_hud)
	combat_hud.result_primary_pressed.connect(_restart_bot_match)
	combat_hud.result_secondary_pressed.connect(_return_to_main_menu)
	player.health_changed.connect(combat_hud.set_health)
	player.damaged.connect(combat_hud.show_damage)
	player.died.connect(_on_player_died)
	player.respawn_skip_requested.connect(_on_player_respawn_skip_requested)
	player.vehicle_status_changed.connect(combat_hud.set_vehicle_status)
	combat_hud.set_health(player.health, player.max_health)
	if king_mode and team_deathmatch:
		combat_hud.set_team_labels("BLUE", "RED")
	elif king_mode:
		combat_hud.set_team_labels("YOU", "TOP RIVAL")
	elif mode_id == "bots":
		combat_hud.set_team_labels("YOU", "TOP RIVAL")
	elif infection_mode:
		combat_hud.set_team_labels("SURVIVORS", "INFECTED")
	elif juggernaut_mode:
		combat_hud.set_team_labels("YOU", "BOTS")
	elif team_deathmatch:
		combat_hud.set_team_labels("BLUE", "RED")
	combat_hud.set_score(0, 0, score_target)
	if not infection_mode:
		combat_hud.set_match_timer(int(match_time_left))
	combat_hud.set_killstreak(0, _next_perk_reward_text())
	combat_hud.set_streak_inventory(player_streak_inventory)
	var settings_menu_script = load(SETTINGS_MENU_PATH)
	var settings = settings_menu_script.new()
	add_child(settings)
	settings.setup(player)
	var inventory_menu_script = load(INVENTORY_MENU_PATH)
	inventory_menu = inventory_menu_script.new()
	add_child(inventory_menu)
	inventory_menu.setup(player.rifle, true)
	inventory_menu.menu_visibility_changed.connect(_on_loadout_menu_visibility_changed)

func _on_loadout_menu_visibility_changed(open: bool) -> void:
	if not player:
		return
	player.gameplay_input_blocked = open
	player.set_physics_process(not open and not loadout_intermission_active)
	player.set_weapon_views_enabled(not open and player.alive)

func _begin_loadout_intermission() -> void:
	loadout_intermission_active = true
	loadout_intermission_remaining = LOADOUT_INTERMISSION_DURATION
	match_active = false
	if inventory_menu:
		inventory_menu.begin_intermission(loadout_intermission_remaining)
	if player:
		player.set_physics_process(false)
	for bot in bots:
		bot.set_physics_process(false)

func _update_loadout_intermission(delta: float) -> void:
	loadout_intermission_remaining = maxf(loadout_intermission_remaining - delta, 0.0)
	if inventory_menu:
		inventory_menu.set_intermission_remaining(loadout_intermission_remaining)
	if loadout_intermission_remaining <= 0.0:
		_finish_loadout_intermission()

func _finish_loadout_intermission() -> void:
	loadout_intermission_active = false
	if inventory_menu:
		inventory_menu.finish_intermission()
	_reset_player_loadout_ammo()
	if player:
		player.set_physics_process(true)
		player.set_weapon_views_enabled(player.alive)
	for bot in bots:
		bot.set_physics_process(true)
	match_active = true
	if combat_hud:
		combat_hud.show_notification("MATCH LIVE", 2.0)

func _reset_player_loadout_ammo() -> void:
	if not player:
		return
	player.rifle.reset_loadout_ammo()
	player.offhand_rifle.reset_loadout_ammo()

func _respawn_player_with_loadout(spawn: Vector3) -> void:
	_stop_deathcam()
	player.respawn_at(spawn)
	if inventory_menu:
		inventory_menu.apply_pending_loadout()
	_reset_player_loadout_ammo()

func _spawn_mystery_box() -> void:
	if not infection_mode or waypoints.is_empty():
		return
	var box := MysteryBox.new()
	var point: Vector3 = waypoints[waypoints.size() / 2]
	box.position = Vector3(point.x, point.y - 0.95, point.z)
	add_child(box)

func _spawn_bots() -> void:
	var infection_players := clampi(GameSession.infection_player_count, 5, INFECTION_COMBATANT_CAP)
	var ffa_players := clampi(GameSession.ffa_player_count, 5, INFECTION_COMBATANT_CAP)
	var tdm_players := clampi(GameSession.tdm_player_count, 4, 48)
	tdm_players -= tdm_players % 4
	var koth_players := clampi(GameSession.koth_player_count, 4, 48)
	koth_players -= koth_players % 4
	var bot_count := infection_players - 1 if infection_mode else (tdm_players - 1 if mode_id == "tdm" else (ffa_players - 1 if mode_id == "bots" else (koth_players - 1 if king_mode else 5)))
	var ffa_spawn_positions: Array[Vector3] = []
	var used_names := CombatantNames.used_name_set([player.display_name])
	if mode_id == "bots":
		ffa_spawn_positions = _distributed_ffa_spawns(bot_count)
	for i in bot_count:
		var bot := CombatBot.new()
		var bot_team := _initial_bot_team(i, bot_count)
		var team_index := 0
		for existing_bot in bots:
			if existing_bot.team_id == bot_team:
				team_index += 1
		bot.name = "Rival_%02d" % (i + 1) if mode_id == "bots" else (("Ally_%d" if bot_team == 0 else "Enemy_%d") % (team_index + 1))
		bot.display_name = CombatantNames.random_unique(used_names)
		bot.position = ffa_spawn_positions[i] if i < ffa_spawn_positions.size() else _initial_bot_spawn(bot_team, i)
		var infected := infection_mode and bot_team == 1
		var bot_weapon_ids := ContentRegistry.get_bot_loadout_weapon_ids()
		var bot_weapon := str(bot_weapon_ids[i % bot_weapon_ids.size()])
		bot.setup(player if bot_team == 1 else null, waypoints, "infected" if infected else bot_weapon, bot_team, GameSession.bot_difficulty_id)
		if i == 0 or i == 3:
			bot.enable_portal_gun()
		add_child(bot)
		bot.set_mode_infected(infected)
		bot.killed.connect(_on_bot_killed)
		bots.append(bot)
		combatant_streaks[bot.get_instance_id()] = 0
		if mode_id == "bots":
			ffa_scores[bot.get_instance_id()] = 0
		if king_mode and not team_deathmatch:
			hill_scores[bot.get_instance_id()] = 0.0
		leaderboard_kills[bot.get_instance_id()] = 0
		leaderboard_deaths[bot.get_instance_id()] = 0
		leaderboard_points[bot.get_instance_id()] = 0
		multi_kill_counts[bot.get_instance_id()] = 0
		multi_kill_deadlines[bot.get_instance_id()] = 0
		juggernaut_scores[bot.get_instance_id()] = 0
	var combatants: Array[CharacterBody3D] = [player]
	combatants.append_array(bots)
	var solo_targets: Array[CharacterBody3D] = [player]
	for bot in bots:
		bot.set_target_candidates(combatants if team_deathmatch or king_mode or juggernaut_mode or mode_id == "bots" else solo_targets)

func _initial_bot_team(index: int, total_bots: int) -> int:
	if juggernaut_mode:
		return index + 1
	if infection_mode:
		return 1 if index >= total_bots - 2 else 0
	if king_mode:
		if not team_deathmatch:
			return index + 1
		var allied_koth_bots := floori(float(total_bots - 1) * 0.5)
		return 0 if index < allied_koth_bots else 1
	if mode_id == "tdm":
		# The player occupies the first blue slot; split the remaining bots around
		# that slot so both teams have the configured number of combatants.
		var allied_bot_count := floori(float(total_bots - 1) * 0.5)
		return 0 if index < allied_bot_count else 1
	if team_deathmatch:
		return 0 if index < 2 else 1
	if mode_id == "bots":
		return index + 1
	return 1

func _initial_bot_spawn(team: int, index: int) -> Vector3:
	var koth_spawns := _highrise_koth_spawn_points()
	if not koth_spawns.is_empty():
		return koth_spawns[index % koth_spawns.size()]
	if infection_mode and not waypoints.is_empty():
		var waypoint_index := posmod(index * 7 + team * 3, waypoints.size())
		var cycle := index / waypoints.size()
		var angle := float(index) * 2.399
		return waypoints[waypoint_index] + Vector3(cos(angle), 0.0, sin(angle)) * minf(float(cycle) * 0.65, 1.3)
	if mode_id == "bots" and not waypoints.is_empty():
		return waypoints[index % waypoints.size()]
	return player_spawns[(index + 1) % player_spawns.size()] if team == 0 else bot_spawns[index % bot_spawns.size()]

func _distributed_ffa_spawns(count: int) -> Array[Vector3]:
	var available := _ffa_spawn_candidates()
	var selected: Array[Vector3] = []
	var occupied: Array[Vector3] = [player.global_position]
	while selected.size() < count and not available.is_empty():
		var best_index := 0
		var best_spacing := -1.0
		for candidate_index in available.size():
			var candidate := available[candidate_index]
			var nearest := INF
			for occupied_position in occupied:
				nearest = minf(nearest, candidate.distance_to(occupied_position))
			if nearest > best_spacing:
				best_spacing = nearest
				best_index = candidate_index
		var chosen := available[best_index]
		available.remove_at(best_index)
		selected.append(chosen)
		occupied.append(chosen)
	return selected

func _ffa_spawn_candidates() -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	for spawn in community_ffa_spawns:
		if _spawn_position_is_clear(spawn):
			candidates.append(spawn)
	for waypoint in waypoints:
		if _spawn_position_is_clear(waypoint):
			candidates.append(waypoint)
		var angle_offset := randf_range(0.0, TAU)
		for slot in FFA_SPAWN_RING_SLOTS:
			var angle := angle_offset + TAU * float(slot) / float(FFA_SPAWN_RING_SLOTS)
			var candidate := waypoint + Vector3(cos(angle), 0.0, sin(angle)) * FFA_SPAWN_RING_RADIUS
			if _spawn_position_is_clear(candidate):
				candidates.append(candidate)
	if candidates.is_empty():
		candidates.assign(waypoints)
	candidates.shuffle()
	return candidates

func _spawn_position_is_clear(candidate: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.48
	shape.height = 1.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, candidate)
	query.collision_mask = 1
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _on_bot_killed(bot: Node, attacker: Node) -> void:
	if not match_active:
		return
	var credited_attacker := _attack_dog_owner(attacker)
	combat_hud.add_kill_feed(_feed_name(credited_attacker), _feed_name(bot), str(bot.get("last_hit_zone")) == "head")
	_record_leaderboard_elimination(bot, credited_attacker)
	_apply_teamkill_penalty(bot, credited_attacker)
	var valid_enemy_kill: bool = is_instance_valid(credited_attacker) and credited_attacker != bot and credited_attacker.get("team_id") != bot.team_id
	_reset_multi_kill(bot)
	if valid_enemy_kill and str(bot.get("last_hit_zone")) == "fall" and credited_attacker.has_method("show_indirect_hitmarker"):
		credited_attacker.show_indirect_hitmarker(true)
	if juggernaut_mode:
		_award_juggernaut_kill(bot, credited_attacker)
	elif infection_mode:
		_handle_infection_death(bot, credited_attacker)
	elif king_mode:
		pass
	elif mode_id in ["bots", "tdm"]:
		_award_ffa_tdm_points(bot, credited_attacker)
	elif credited_attacker == player:
		player_score += 1
	if valid_enemy_kill and bool(bot.get_meta("gun_streak_kill", false)) and not bool(bot.get_meta("killstreak_exempt_death", false)):
		_award_combatant_streak(credited_attacker, bot.global_position)
	_drop_carried_powerups(bot, bot.global_position)
	_maybe_drop_random_perk(bot.global_position)
	combatant_streaks[bot.get_instance_id()] = 0
	if infection_mode:
		return
	combat_hud.set_score(player_score, bot_score, score_target)
	if _check_score_victory():
		return
	await get_tree().create_timer(3.0).timeout
	if match_active:
		bot.respawn_at(_best_spawn_for_team(bot.team_id, bot))

func _on_player_died(attacker: Node) -> void:
	if not match_active:
		return
	player_respawn_skip_requested = false
	var credited_attacker := _attack_dog_owner(attacker)
	combat_hud.add_kill_feed(_feed_name(credited_attacker), _feed_name(player), str(player.get("last_hit_zone")) == "head")
	_record_leaderboard_elimination(player, credited_attacker)
	_apply_teamkill_penalty(player, credited_attacker)
	_reset_multi_kill(player)
	var killer_name := _feed_name(credited_attacker)
	var deathcam_started := _start_deathcam(credited_attacker, killer_name)
	if is_instance_valid(credited_attacker) and credited_attacker != player and credited_attacker.get("team_id") != player.team_id and bool(player.get_meta("gun_streak_kill", false)) and not bool(player.get_meta("killstreak_exempt_death", false)):
		_award_combatant_streak(credited_attacker, player.global_position)
	_drop_carried_powerups(player, player.global_position)
	_maybe_drop_random_perk(player.global_position)
	if juggernaut_mode:
		_award_juggernaut_kill(player, credited_attacker)
	elif infection_mode:
		_handle_infection_death(player, attacker)
	elif mode_id in ["bots", "tdm"]:
		_award_ffa_tdm_points(player, credited_attacker)
	elif not king_mode and (not team_deathmatch or (credited_attacker and credited_attacker.get("team_id") == 1)):
		bot_score += 1
	_reset_player_streak()
	jetpack_spawn_timer = _powerup_interval(16.0, 30.0)
	coil_gun_spawn_timer = _powerup_interval(22.0, 40.0)
	if not infection_mode:
		combat_hud.set_score(player_score, bot_score, score_target)
	if not deathcam_started:
		combat_hud.show_death_screen(killer_name, 3.0)
	if infection_mode:
		return
	if not king_mode and _check_score_victory():
		return
	await _wait_for_player_respawn(3.0)
	if match_active:
		_respawn_player_with_loadout(_best_player_spawn())
		if infection_mode and player.team_id == 1:
			player.set_mode_infected(true)
		combat_hud.hide_death_screen()

func _start_deathcam(attacker: Node, killer_name: String) -> bool:
	_stop_deathcam()
	if not is_instance_valid(attacker) or attacker == player or attacker is not Node3D:
		return false
	if attacker.get("alive") != true or attacker.get("team_id") == player.team_id:
		return false
	var source_camera := get_viewport().get_camera_3d()
	if not is_instance_valid(source_camera):
		return false
	var deathcam_controller_script = load(DEATHCAM_CONTROLLER_PATH)
	var controller = deathcam_controller_script.new()
	controller.name = "Deathcam"
	add_child(controller)
	if not controller.begin(source_camera, attacker as Node3D, player):
		controller.queue_free()
		return false
	deathcam = controller
	combat_hud.show_deathcam_overlay(killer_name, 3.0)
	return true

func _on_player_respawn_skip_requested() -> void:
	if match_active and is_instance_valid(player) and not player.alive:
		player_respawn_skip_requested = true

func _wait_for_player_respawn(duration: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration * 1000.0)
	while match_active and is_instance_valid(player) and not player.alive and not player_respawn_skip_requested and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _stop_deathcam() -> void:
	if is_instance_valid(deathcam):
		deathcam.stop()
	deathcam = null

func _award_juggernaut_kill(victim: Node, attacker: Node) -> void:
	if attacker == current_juggernaut:
		var attacker_id := attacker.get_instance_id()
		juggernaut_scores[attacker_id] = int(juggernaut_scores.get(attacker_id, 0)) + 1
		if attacker == player:
			player_score += 1
		else:
			bot_score += 1
	if victim == current_juggernaut:
		var next_holder: Node = attacker if attacker and attacker.get("alive") else _random_living_combatant(victim)
		if next_holder:
			_assign_juggernaut(next_holder)

func _assign_juggernaut(holder: Node) -> void:
	if current_juggernaut and is_instance_valid(current_juggernaut):
		current_juggernaut.set_mode_juggernaut(false)
	current_juggernaut = holder
	holder.set_mode_juggernaut(true)
	_update_juggernaut_marker(holder)
	_refresh_juggernaut_targets()
	if combat_hud:
		combat_hud.show_notification("%s IS THE JUGGERNAUT" % _feed_name(holder).to_upper(), 3.0)

func _update_juggernaut_marker(holder: Node3D) -> void:
	if is_instance_valid(juggernaut_marker):
		juggernaut_marker.queue_free()
	juggernaut_marker = Node3D.new()
	juggernaut_marker.name = "JuggernautMarker"
	holder.add_child(juggernaut_marker)
	if DedicatedServer.active:
		return
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ff8c35")
	material.emission_enabled = true
	material.emission = Color("#ff4f20")
	material.emission_energy_multiplier = 4.0
	mesh.material = material
	orb.mesh = mesh
	orb.position.y = 1.65
	juggernaut_marker.add_child(orb)
	var label := Label3D.new()
	label.text = "JUGGERNAUT"
	label.position.y = 2.15
	label.font_size = 38
	label.modulate = Color("#ffad55")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	juggernaut_marker.add_child(label)

func _refresh_juggernaut_targets() -> void:
	if not current_juggernaut:
		return
	var combatants := _all_combatants()
	for bot in bots:
		if bot == current_juggernaut:
			bot.set_target_candidates(combatants)
		else:
			var targets: Array[CharacterBody3D] = []
			if current_juggernaut is CharacterBody3D:
				targets.append(current_juggernaut)
			bot.set_target_candidates(targets)

func _random_living_combatant(excluded: Node = null) -> Node:
	var living: Array[Node] = []
	for combatant in _all_combatants():
		if combatant != excluded and combatant.alive:
			living.append(combatant)
	return living.pick_random() if not living.is_empty() else null

func _handle_infection_death(victim: Node, _attacker: Node) -> void:
	var was_survivor: bool = victim.team_id == 0
	if was_survivor:
		victim.team_id = 1
		victim.set_mode_infected(true)
		combat_hud.show_notification("%s HAS BEEN INFECTED" % _feed_name(victim).to_upper(), 3.0)
	_refresh_infection_targets()
	_update_infection_hud()
	if _survivor_count() == 0:
		_end_match(player.team_id == 1)
		return
	_respawn_infected_later(victim)

func _respawn_infected_later(victim: Node) -> void:
	if victim == player:
		await _wait_for_player_respawn(3.0)
	else:
		await get_tree().create_timer(3.0).timeout
	if not match_active or not is_instance_valid(victim):
		return
	if victim == player:
		_respawn_player_with_loadout(_best_spawn_for_team(1, player))
		player.set_mode_infected(true)
		combat_hud.hide_death_screen()
	else:
		victim.respawn_at(_best_spawn_for_team(1, victim))
		victim.set_mode_infected(true)
	_refresh_infection_targets()

func _refresh_infection_targets() -> void:
	var combatants := _all_combatants()
	for bot in bots:
		bot.set_target_candidates(combatants)

func _survivor_count() -> int:
	var count := 0
	for combatant in _all_combatants():
		if combatant.team_id == 0:
			count += 1
	return count

func _update_infection_hud() -> void:
	if not combat_hud:
		return
	var survivors := _survivor_count()
	var total_combatants := bots.size() + 1
	combat_hud.set_score(survivors, total_combatants - survivors, maxi(total_combatants, 6))
	var seconds := maxi(0, int(ceil(infection_time_left)))
	combat_hud.set_mode_caption("SURVIVE  %02d:%02d" % [seconds / 60, seconds % 60])

func _feed_name(combatant: Node) -> String:
	if not combatant:
		return "ENVIRONMENT"
	var combatant_name = combatant.get("display_name")
	if combatant_name != null and not str(combatant_name).is_empty():
		return str(combatant_name)
	return str(combatant.name).replace("_", " ")

func _attack_dog_owner(attacker: Node) -> Node:
	if not is_instance_valid(attacker):
		return null
	if attacker.get("streak_owner") != null and is_instance_valid(attacker.get("streak_owner")):
		return attacker.get("streak_owner") as Node
	var vehicle_driver = attacker.get("driver")
	if is_instance_valid(vehicle_driver):
		return vehicle_driver as Node
	# Empty traffic cars and other world actors are environmental hazards, not
	# combatants that can earn score, perks, or killstreak rewards.
	if attacker.get("active_perks") is not Array or not attacker.has_method("apply_perk"):
		return null
	return attacker

func _spawn_attack_dog_pack(owner: Node3D, owner_id: int, show_notification := true) -> void:
	if not is_instance_valid(owner):
		return
	var spawn_points := _spread_attack_dog_spawns(owner.global_position, 4)
	for spawn_point in spawn_points:
		var dog := AttackDog.new()
		dog.setup(attack_dog_serial, owner_id, owner, int(owner.get("team_id")), true, waypoints)
		attack_dog_serial += 1
		add_child(dog)
		dog.global_position = spawn_point
		dog.killed.connect(_on_attack_dog_killed)
		dog.expired.connect(_on_attack_dog_expired)
		attack_dogs.append(dog)
	_append_attack_dog_targets()
	if show_notification and combat_hud:
		combat_hud.show_streak_callout("10 KILLSTREAK — ATTACK DOGS DEPLOYED", 5.0)

func _spread_attack_dog_spawns(origin: Vector3, count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var candidates := (community_vehicle_points if not community_vehicle_points.is_empty() else waypoints).duplicate()
	for _index in count:
		var best := Vector3.ZERO
		var best_score := -1.0
		for candidate_value in candidates:
			var candidate: Vector3 = candidate_value
			var origin_distance := candidate.distance_to(origin)
			if origin_distance < 8.0 or origin_distance > 36.0:
				continue
			var separation := origin_distance
			for selected in result:
				separation = minf(separation, candidate.distance_to(selected))
			if separation > best_score:
				best_score = separation
				best = candidate
		if best_score < 0.0:
			var angle := float(result.size()) * TAU / float(maxi(count, 1)) + randf_range(-0.25, 0.25)
			best = origin + Vector3(cos(angle), 0.0, sin(angle)) * 11.0
		else:
			candidates.erase(best)
		result.append(best)
	return result

func _on_attack_dog_killed(dog: Node, _attacker: Node) -> void:
	_remove_attack_dog_from_targets(dog)
	await get_tree().create_timer(4.0).timeout
	attack_dogs.erase(dog)
	if is_instance_valid(dog):
		dog.queue_free()

func _on_attack_dog_expired(dog: Node) -> void:
	_remove_attack_dog_from_targets(dog)
	attack_dogs.erase(dog)
	if is_instance_valid(dog):
		dog.queue_free()

func _remove_attack_dog_from_targets(dog: Node) -> void:
	for bot in bots:
		if not is_instance_valid(bot):
			continue
		bot.target_candidates.erase(dog)
		if bot.target == dog:
			bot.target = null

func _append_attack_dog_targets() -> void:
	for bot in bots:
		var candidates: Array[CharacterBody3D] = bot.target_candidates.duplicate()
		for dog in attack_dogs:
			if is_instance_valid(dog) and dog.alive and dog.team_id != bot.team_id and dog not in candidates:
				candidates.append(dog)
		bot.set_target_candidates(candidates)

func _spawn_random_perk_pickup(drop_position: Vector3) -> void:
	var reward := PerkCatalog.random_perk()
	var pickup := PerkPickup.new()
	pickup.configure(reward["id"], reward["name"])
	pickup.position = drop_position
	add_child(pickup)
	pickup.collected.connect(_on_perk_collected.bind(pickup))
	pickup.tree_exited.connect(_on_perk_pickup_removed.bind(pickup))
	perk_pickups.append(pickup)

func _maybe_drop_random_perk(drop_position: Vector3) -> void:
	if randf() <= RANDOM_PERK_DROP_CHANCE:
		_spawn_random_perk_pickup(drop_position)

func _on_perk_collected(_perk_id: String, perk_name: String, collector: Node, pickup: Area3D) -> void:
	perk_pickups.erase(pickup)
	if collector == player:
		if perk_name not in active_perk_names:
			active_perk_names.append(perk_name)
		combat_hud.set_perks(active_perk_names)
		var message := "%s ACQUIRED" % perk_name.to_upper()
		combat_hud.show_notification(message)
		combat_hud.play_reward_sound()

func _on_perk_pickup_removed(pickup: Area3D) -> void:
	perk_pickups.erase(pickup)

func _reset_player_streak() -> void:
	player_killstreak = 0
	combatant_streaks[player.get_instance_id()] = 0
	active_perk_names.clear()
	player.reset_combat_perks()
	combat_hud.set_killstreak(0, _next_perk_reward_text())
	combat_hud.set_perks(active_perk_names)

func _next_perk_reward_text() -> String:
	for threshold in [3, 6, 10, 35]:
		if player_killstreak < threshold:
			return "%d %s" % [threshold, STREAK_REWARDS[threshold]]
	return "MAX STREAK"

func _award_combatant_streak(attacker: Node, target_position: Vector3) -> void:
	if not is_instance_valid(attacker) or attacker.get("alive") != true:
		return
	var attacker_perks = attacker.get("active_perks")
	if attacker_perks is not Array or not attacker.has_method("apply_perk"):
		return
	var attacker_id := attacker.get_instance_id()
	combatant_streaks[attacker_id] = int(combatant_streaks.get(attacker_id, 0)) + 1
	var streak := int(combatant_streaks[attacker_id])
	if attacker.has_method("on_confirmed_kill"):
		attacker.on_confirmed_kill()
	if streak in PERK_MILESTONES:
		var reward := PerkCatalog.random_unowned(attacker_perks)
		if not reward.is_empty() and attacker.apply_perk(str(reward["id"])) and attacker == player:
			if str(reward["name"]) not in active_perk_names:
				active_perk_names.append(str(reward["name"]))
			combat_hud.set_perks(active_perk_names)
			var message := "%s ACTIVATED" % str(reward["name"]).to_upper()
			combat_hud.show_notification(message, 3.0)
			combat_hud.play_reward_sound()
	match streak:
		3:
			_grant_streak_reward(attacker, "ammo_drop")
		6:
			_grant_streak_reward(attacker, "airstrike", target_position)
		10:
			_grant_streak_reward(attacker, "attack_dogs")
		35:
			_grant_streak_reward(attacker, "nuke")
	if attacker == player:
		player_killstreak = streak
		player_best_killstreak = maxi(player_best_killstreak, streak)
		combat_hud.set_killstreak(streak, _next_perk_reward_text())

func _grant_streak_reward(owner: Node, reward_id: String, bot_target: Vector3 = Vector3.ZERO) -> void:
	if owner == player:
		player_streak_inventory.append(reward_id)
		combat_hud.set_streak_inventory(player_streak_inventory)
		combat_hud.show_streak_callout("%s EARNED — PRESS ~ TO DEPLOY" % reward_id.replace("_", " ").to_upper(), 5.0)
		return
	if not _deploy_streak(owner, reward_id, bot_target) and reward_id == "nuke":
		_wait_to_deploy_bot_nuke(owner)

func use_local_killstreak(_entity_id := 0) -> void:
	if not player or not player.alive or player_streak_inventory.is_empty():
		return
	var reward_id: String = player_streak_inventory[0]
	if reward_id == "nuke" and _nuke_in_progress():
		combat_hud.show_notification("NUKE ALREADY INBOUND — REWARD HELD", 3.0)
		return
	if _deploy_streak(player, reward_id, _local_streak_target()):
		player_streak_inventory.pop_front()
		combat_hud.set_streak_inventory(player_streak_inventory)

func _deploy_streak(owner: Node, reward_id: String, target_position: Vector3 = Vector3.ZERO) -> bool:
	match reward_id:
		"ammo_drop":
			_spawn_ammo_drop(owner.global_position)
		"airstrike":
			_trigger_strike(owner, target_position, "airstrike")
		"attack_dogs":
			_spawn_attack_dog_pack(owner, owner.get_instance_id())
		"nuke":
			return _trigger_strike(owner, owner.global_position, "nuke")
	return true

func _nuke_in_progress() -> bool:
	return not get_tree().get_nodes_in_group("active_nuke_strike").is_empty()

func _wait_to_deploy_bot_nuke(owner: Node) -> void:
	while is_instance_valid(owner) and is_inside_tree():
		while _nuke_in_progress() and is_instance_valid(owner):
			await get_tree().create_timer(0.5, true, false, true).timeout
		if not is_instance_valid(owner):
			return
		if _deploy_streak(owner, "nuke", owner.global_position):
			return
		await get_tree().create_timer(0.25, true, false, true).timeout

func _local_streak_target() -> Vector3:
	if not player or not player.camera:
		return player.global_position if player else Vector3.ZERO
	var origin: Vector3 = player.camera.global_position
	var endpoint: Vector3 = origin - player.camera.global_transform.basis.z * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", endpoint)

func _spawn_ammo_drop(position: Vector3) -> void:
	var drop := AmmoDropPickup.new()
	var angle := randf() * TAU
	drop.position = _ground_pickup_position(position + Vector3(cos(angle) * 2.6, -0.95, sin(angle) * 2.6))
	add_child(drop)
	drop.collected.connect(_on_ammo_drop_collected)
	if combat_hud:
		combat_hud.show_streak_callout("KILLSTREAK READY — AMMO DROP INBOUND", 4.5)

func _ground_pickup_position(candidate: Vector3) -> Vector3:
	# Begin below normal ceilings/upper floors so a ground-level call-in cannot
	# accidentally snap upward onto the floor above it.
	var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.75, candidate + Vector3.DOWN * 12.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3) + Vector3.UP * 0.05 if not hit.is_empty() else candidate

func _on_ammo_drop_collected(collector: Node) -> void:
	if collector == player and combat_hud:
		combat_hud.show_notification("AMMO DROP COLLECTED — FULLY RESTOCKED", 3.0)
		combat_hud.play_reward_sound()

func _trigger_strike(owner: Node, position: Vector3, strike_type: String) -> bool:
	var strike := KillstreakStrike.new()
	add_child(strike)
	if not strike.activate(owner, position, strike_type):
		return false
	if combat_hud:
		combat_hud.show_streak_callout("%s CALLED IN BY %s" % [strike_type.to_upper(), _feed_name(owner).to_upper()], 5.0)
	return true

func _spawn_jetpack_pickup() -> void:
	if waypoints.is_empty():
		jetpack_spawn_timer = 10.0
		return
	var spawn_point := _powerup_spawn_position()
	jetpack_pickup = JetpackPickup.new()
	jetpack_pickup.position = spawn_point
	add_child(jetpack_pickup)
	jetpack_pickup.collected.connect(_on_jetpack_collected)
	jetpack_pickup.tree_exited.connect(_on_jetpack_pickup_removed.bind(jetpack_pickup))
	combat_hud.show_notification("JETPACK AVAILABLE — FIND THE BLUE PICKUP", 4.0)

func _drop_carried_powerups(victim: Node, drop_position: Vector3) -> void:
	var records: Array = victim.get_meta("death_powerup_drops", [])
	victim.remove_meta("death_powerup_drops")
	if records.is_empty() and victim.has_method("carried_powerup_drop_records"):
		records = victim.carried_powerup_drop_records()
	for index in records.size():
		var record: Dictionary = records[index] if records[index] is Dictionary else {"kind": str(records[index]), "handoffs": 0}
		var handoffs := maxi(0, int(record.get("handoffs", 0)))
		if randf() > pow(POWERUP_HANDOFF_DROP_DECAY, handoffs):
			continue
		var angle := TAU * float(index) / float(maxi(records.size(), 1))
		_spawn_dropped_powerup(str(record.get("kind", "")), drop_position + Vector3(cos(angle), 0.25, sin(angle)) * 0.65, handoffs + 1)

func _spawn_dropped_powerup(kind: String, drop_position: Vector3, handoff_count := 1) -> void:
	var pickup: Area3D
	match kind:
		"jetpack":
			pickup = JetpackPickup.new()
			pickup.collected.connect(_on_jetpack_collected)
		"coil_gun":
			pickup = CoilGunPickup.new()
			pickup.collected.connect(_on_coil_gun_collected)
		"suicide_vest":
			pickup = SuicideVestPickup.new()
			pickup.collected.connect(_on_suicide_vest_collected)
		"ricochet", "force", "gravity_bomb", "sticky_bomb":
			pickup = PhysicsPowerupPickup.new()
			pickup.configure(kind)
			pickup.collected.connect(_on_physics_pickup_collected)
		_:
			return
	pickup.set_meta("powerup_handoff_count", handoff_count)
	pickup.position = drop_position
	add_child(pickup)

func _on_jetpack_collected(collector: Node) -> void:
	jetpack_spawn_timer = _powerup_interval(16.0, 30.0)
	if collector == player:
		combat_hud.show_notification("JETPACK ACQUIRED — HOLD JUMP TO BOOST", 4.0)
		combat_hud.play_reward_sound()

func _on_jetpack_pickup_removed(pickup: Area3D) -> void:
	if jetpack_pickup == pickup:
		jetpack_pickup = null

func _spawn_coil_gun_pickup() -> void:
	if waypoints.is_empty():
		coil_gun_spawn_timer = 10.0
		return
	var spawn_point := _powerup_spawn_position()
	coil_gun_pickup = CoilGunPickup.new()
	coil_gun_pickup.position = spawn_point
	add_child(coil_gun_pickup)
	coil_gun_pickup.collected.connect(_on_coil_gun_collected)
	coil_gun_pickup.tree_exited.connect(_on_coil_gun_pickup_removed.bind(coil_gun_pickup))
	combat_hud.show_notification("COIL GUN AVAILABLE — FIND THE PURPLE PICKUP", 4.0)

func _on_coil_gun_collected(collector: Node) -> void:
	coil_gun_spawn_timer = _powerup_interval(22.0, 40.0)
	if collector == player:
		combat_hud.show_notification("COIL GUN ACQUIRED — UP TO 3 NEARBY TARGETS", 4.0)
		combat_hud.play_reward_sound()

func _on_coil_gun_pickup_removed(pickup: Area3D) -> void:
	if coil_gun_pickup == pickup:
		coil_gun_pickup = null

func _spawn_physics_pickup(kind: String) -> void:
	if waypoints.is_empty():
		physics_pickup_timers[kind] = 10.0
		return
	var pickup := PhysicsPowerupPickup.new()
	pickup.configure(kind)
	pickup.position = _powerup_spawn_position()
	add_child(pickup)
	physics_pickups[kind] = pickup
	pickup.collected.connect(_on_physics_pickup_collected)
	pickup.tree_exited.connect(_on_physics_pickup_removed.bind(kind, pickup))
	var names := {"ricochet": "RICOCHET", "force": "FORCE MANIPULATOR", "gravity_bomb": "GRAVITY BOMBS", "sticky_bomb": "STICKY BOMBS"}
	combat_hud.show_notification("%s AVAILABLE — FIND THE GLOWING PICKUP" % names[kind], 4.0)

func _on_physics_pickup_collected(kind: String, collector: Node) -> void:
	physics_pickup_timers[kind] = _powerup_interval(35.0, 55.0)
	if collector != player:
		return
	var messages := {
		"ricochet": "RICOCHET ACTIVE — SHOTS BOUNCE TWICE FOR 30 SECONDS",
		"force": "FORCE MANIPULATOR EQUIPPED — HOLD AND RELEASE LEFT CLICK / LT",
		"gravity_bomb": "GRAVITY BOMBS EQUIPPED — REPLACES NORMAL GRENADES",
		"sticky_bomb": "STICKY BOMBS EQUIPPED — STICKS TO PLAYERS / LARGE BLAST"
	}
	combat_hud.show_notification(messages[kind], 4.0)
	combat_hud.play_reward_sound()

func _on_physics_pickup_removed(kind: String, pickup: Area3D) -> void:
	if physics_pickups.get(kind) == pickup:
		physics_pickups.erase(kind)

func _spawn_suicide_vest_pickup() -> void:
	if waypoints.is_empty():
		suicide_vest_spawn_timer = 10.0
		return
	suicide_vest_pickup = SuicideVestPickup.new()
	suicide_vest_pickup.position = _powerup_spawn_position()
	add_child(suicide_vest_pickup)
	suicide_vest_pickup.collected.connect(_on_suicide_vest_collected)
	suicide_vest_pickup.tree_exited.connect(_on_suicide_vest_pickup_removed.bind(suicide_vest_pickup))
	combat_hud.show_notification("SUICIDE VEST AVAILABLE — FIND THE RED PICKUP", 4.0)

func _on_suicide_vest_collected(collector: Node) -> void:
	suicide_vest_spawn_timer = _powerup_interval(35.0, 65.0)
	if collector == player:
		combat_hud.show_notification("C4 EQUIPPED — FIRE TO DETONATE", 4.0)
		combat_hud.play_reward_sound()

func _on_suicide_vest_pickup_removed(pickup: Area3D) -> void:
	if suicide_vest_pickup == pickup:
		suicide_vest_pickup = null

func _best_player_spawn() -> Vector3:
	return _best_spawn_for_team(0, player)

func _best_bot_spawn() -> Vector3:
	return _best_spawn_for_team(1)

func _best_spawn_for_team(team: int, respawning: Node = null) -> Vector3:
	var koth_spawns := _highrise_koth_spawn_points()
	var spawn_pool: Array = koth_spawns if not koth_spawns.is_empty() else (_ffa_spawn_candidates() if mode_id == "bots" and not waypoints.is_empty() else (waypoints if infection_mode and not waypoints.is_empty() else (player_spawns if team == 0 else bot_spawns)))
	var best: Vector3 = spawn_pool[0]
	var best_distance := -1.0
	for spawn_value in spawn_pool:
		var spawn: Vector3 = spawn_value
		var nearest := 999.0
		if player != respawning and player.alive and player.team_id != team:
			nearest = minf(nearest, spawn.distance_to(player.global_position))
		for candidate in bots:
			if candidate != respawning and candidate.alive and candidate.team_id != team:
				nearest = minf(nearest, spawn.distance_to(candidate.global_position))
		if nearest > best_distance:
			best_distance = nearest
			best = spawn
	return best

func _award_ffa_tdm_points(victim: Node, attacker: Node) -> void:
	if not is_instance_valid(attacker) or attacker == victim:
		return
	if attacker.get("team_id") == victim.get("team_id"):
		return
	var attacker_id := attacker.get_instance_id()
	var now := Time.get_ticks_msec()
	var chain := int(multi_kill_counts.get(attacker_id, 0)) + 1 if now <= int(multi_kill_deadlines.get(attacker_id, 0)) else 1
	multi_kill_counts[attacker_id] = chain
	multi_kill_deadlines[attacker_id] = now + MULTI_KILL_WINDOW_MSEC
	var same_sniper_shot := false
	if attacker == player and player.get_last_fired_weapon_id() == "sniper":
		var shot_serial: int = player.get_last_fired_shot_serial()
		same_sniper_shot = int(last_scored_sniper_shot.get(attacker_id, -1)) == shot_serial
		last_scored_sniper_shot[attacker_id] = shot_serial
	var points := BASE_KILL_POINTS + (MULTI_KILL_BONUS if chain >= 2 and not same_sniper_shot else 0)
	leaderboard_points[attacker_id] = int(leaderboard_points.get(attacker_id, 0)) + points
	if mode_id == "tdm":
		if int(attacker.get("team_id")) == 0:
			player_score += points
		else:
			bot_score += points
	else:
		ffa_scores[attacker_id] = int(ffa_scores.get(attacker_id, 0)) + points
		player_score = int(ffa_scores.get(player.get_instance_id(), 0))
		bot_score = 0
		for bot in bots:
			if is_instance_valid(bot):
				bot_score = maxi(bot_score, int(ffa_scores.get(bot.get_instance_id(), 0)))
	if attacker == player:
		player.show_score_award(points, _multi_kill_callout(chain))

func _apply_teamkill_penalty(victim: Node, attacker: Node) -> bool:
	if not is_instance_valid(victim) or not is_instance_valid(attacker) or attacker == victim:
		return false
	if attacker.get("team_id") != victim.get("team_id"):
		return false
	var attacker_id := attacker.get_instance_id()
	leaderboard_points[attacker_id] = int(leaderboard_points.get(attacker_id, 0)) - TEAMKILL_PENALTY
	_reset_multi_kill(attacker)
	if team_deathmatch:
		var team := int(attacker.get("team_id"))
		if king_mode:
			if team == 0:
				hill_score_fraction.x -= TEAMKILL_PENALTY
				player_score = int(hill_score_fraction.x)
			else:
				hill_score_fraction.y -= TEAMKILL_PENALTY
				bot_score = int(hill_score_fraction.y)
		elif team == 0:
			player_score -= TEAMKILL_PENALTY
		else:
			bot_score -= TEAMKILL_PENALTY
	if attacker == player:
		player.show_score_award(-TEAMKILL_PENALTY, "TEAMKILL")
	return true

func award_collateral_bonus(attacker: Node, kill_count: int) -> void:
	if not match_active or kill_count < 2 or attacker != player or mode_id not in ["bots", "tdm"]:
		return
	var attacker_id := attacker.get_instance_id()
	leaderboard_points[attacker_id] = int(leaderboard_points.get(attacker_id, 0)) + COLLATERAL_BONUS
	if mode_id == "tdm":
		player_score += COLLATERAL_BONUS
	else:
		ffa_scores[attacker_id] = int(ffa_scores.get(attacker_id, 0)) + COLLATERAL_BONUS
		player_score = int(ffa_scores[attacker_id])
	attacker.show_score_award(COLLATERAL_BONUS, "COLLATERAL")
	combat_hud.set_score(player_score, bot_score, score_target)
	_check_score_victory()

func _reset_multi_kill(combatant: Node) -> void:
	if not is_instance_valid(combatant):
		return
	var combatant_id := combatant.get_instance_id()
	multi_kill_counts[combatant_id] = 0
	multi_kill_deadlines[combatant_id] = 0

func _multi_kill_callout(chain: int) -> String:
	match chain:
		2: return "DOUBLE KILL"
		3: return "TRIPLE KILL"
		4: return "QUAD KILL"
	return "MULTI KILL x%d" % chain if chain >= 5 else ""

func _record_leaderboard_elimination(victim: Node, attacker: Node) -> void:
	if not is_instance_valid(victim):
		return
	var victim_id := victim.get_instance_id()
	leaderboard_deaths[victim_id] = int(leaderboard_deaths.get(victim_id, 0)) + 1
	if not is_instance_valid(attacker) or attacker == victim:
		return
	if attacker.get("team_id") == victim.get("team_id"):
		return
	var attacker_id := attacker.get_instance_id()
	leaderboard_kills[attacker_id] = int(leaderboard_kills.get(attacker_id, 0)) + 1

func _update_leaderboard() -> void:
	var rows: Array[Dictionary] = []
	for combatant in _all_combatants():
		if not is_instance_valid(combatant):
			continue
		var entity_id := combatant.get_instance_id()
		var score := int(leaderboard_kills.get(entity_id, 0))
		if mode_id in ["bots", "tdm"]:
			score = int(leaderboard_points.get(entity_id, 0))
		elif king_mode:
			score = int(hill_scores.get(entity_id, 0.0)) if not team_deathmatch else (player_score if int(combatant.team_id) == 0 else bot_score)
		elif juggernaut_mode:
			score = int(juggernaut_scores.get(entity_id, 0))
		var status := ""
		if infection_mode:
			status = "SURVIVOR" if combatant.team_id == 0 else "INFECTED"
		elif juggernaut_mode and combatant == current_juggernaut:
			status = "JUGGERNAUT"
		elif team_deathmatch:
			status = "BLUE" if combatant.team_id == 0 else "RED"
		rows.append({
			"name": combatant.display_name if not str(combatant.get("display_name")).is_empty() else str(combatant.name).replace("_", " "),
			"score": score,
			"kills": int(leaderboard_kills.get(entity_id, 0)),
			"deaths": int(leaderboard_deaths.get(entity_id, 0)),
			"team": int(combatant.team_id) if team_deathmatch else -1,
			"local": combatant == player,
			"status": status
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		if int(a["kills"]) != int(b["kills"]):
			return int(a["kills"]) > int(b["kills"])
		return str(a["name"]) < str(b["name"])
	)
	var mode_name := "FREE-FOR-ALL" if mode_id == "bots" else (("FFA" if not team_deathmatch else "TDM") + " KING OF THE HILL" if king_mode else mode_id.replace("_", " ").to_upper())
	var caption := "FIRST TO %02d" % score_target
	if team_deathmatch:
		caption = "BLUE %02d  —  %02d RED" % [player_score, bot_score]
	if infection_mode:
		caption = "SURVIVORS %02d  —  %02d INFECTED" % [_survivor_count(), _all_combatants().size() - _survivor_count()]
	combat_hud.set_leaderboard(mode_name + " LEADERBOARD", caption, rows)

func _end_match(player_won: bool) -> void:
	match_active = false
	_stop_deathcam()
	player.alive = false
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_weapon_views_enabled(false)
	if player.touch_controls:
		player.touch_controls.set_controls_enabled(false)
	for bot in bots:
		bot.set_physics_process(false)
	for dog in attack_dogs:
		if is_instance_valid(dog):
			dog.set_physics_process(false)
	for vehicle in vehicles:
		if is_instance_valid(vehicle):
			vehicle.eject_all()
			vehicle.set_physics_process(false)
	combat_hud.hide_death_screen()
	var mode_name := "FREE-FOR-ALL" if GameSession.game_mode_id == "bots" else str(GameSession.game_mode_id).replace("_", " ").to_upper()
	var map_name := str(GameSession.bot_map_id).replace("_", " ").to_upper()
	combat_hud.show_match_result(
		player_won,
		"AFTER ACTION REPORT  //  %s" % mode_name,
		"%02d   —   %02d" % [player_score, bot_score],
		"AREA SECURED" if player_won else "COMBAT ZONE LOST",
		["MODE  %s" % mode_name, "MAP  %s" % map_name, "BEST STREAK  %02d" % player_best_killstreak],
		"REPLAY",
		"HOME"
	)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _spawn_initial_vehicles() -> void:
	for _i in 2:
		if not _spawn_one_vehicle():
			break

func _spawn_one_vehicle() -> bool:
	var occupied_positions: Array[Vector3] = []
	for vehicle in vehicles:
		if is_instance_valid(vehicle):
			occupied_positions.append(vehicle.global_position)
	var candidates := waypoints.duplicate()
	candidates.shuffle()
	for waypoint_value in candidates:
		var waypoint: Vector3 = waypoint_value
		var candidate := Vector3(waypoint.x, 0.05, waypoint.z)
		if not _vehicle_spawn_far_from_characters(candidate):
			continue
		var separated := true
		for occupied in occupied_positions:
			if candidate.distance_to(occupied) < 15.0:
				separated = false
				break
		if not separated:
			continue
		var rotations := [0.0, PI * 0.5, PI, PI * 1.5]
		rotations.shuffle()
		for yaw in rotations:
			if not _vehicle_spawn_is_clear(candidate, yaw):
				continue
			var vehicle := CombatVehicle.new()
			vehicle.position = candidate
			vehicle.rotation.y = yaw
			add_child(vehicle)
			vehicle.destroyed.connect(_on_vehicle_destroyed)
			vehicles.append(vehicle)
			return true
	return false

func _vehicle_spawn_far_from_characters(candidate: Vector3) -> bool:
	var minimum_distance := 5.0 if GameSession.bot_map_id == "warehouse" else 8.0
	for spawn in player_spawns:
		if candidate.distance_to(spawn) < minimum_distance:
			return false
	for spawn in bot_spawns:
		if candidate.distance_to(spawn) < minimum_distance:
			return false
	return true

func _vehicle_spawn_is_clear(candidate: Vector3, yaw: float) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.8, 2.2, 5.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), candidate + Vector3.UP * 1.2)
	query.collision_mask = 1 | 2 | 4
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _on_vehicle_destroyed(vehicle: Node) -> void:
	await get_tree().create_timer(VEHICLE_RESPAWN_DELAY).timeout
	vehicles.erase(vehicle)
	if is_instance_valid(vehicle):
		vehicle.queue_free()
	if not match_active:
		return
	while match_active and not _spawn_one_vehicle():
		await get_tree().create_timer(VEHICLE_RESPAWN_RETRY_DELAY).timeout

func _restart_bot_match() -> void:
	_stop_deathcam()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred("reload_current_scene")

func _return_to_main_menu() -> void:
	_stop_deathcam()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred("change_scene_to_file", "res://root.tscn")

func _start_music() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_db = -15.0
	add_child(music_player)
	music_player.finished.connect(_play_next_track)
	_play_next_track()

func _play_next_track() -> void:
	if music_tracks.is_empty():
		for path in MUSIC_TRACK_PATHS:
			var stream := load(path) as AudioStream
			if stream:
				music_tracks.append(stream)
	if music_tracks.is_empty():
		return
	if music_track_queue.is_empty():
		for index in music_tracks.size():
			music_track_queue.append(index)
		music_track_queue.shuffle()
		# The previous cycle's last track must not also open the new cycle.
		if music_track_queue.size() > 1 and music_track_queue.back() == current_track:
			var swap_index := music_track_queue.size() - 2
			var held := music_track_queue[swap_index]
			music_track_queue[swap_index] = music_track_queue.back()
			music_track_queue[music_track_queue.size() - 1] = held
	var next: int = music_track_queue.pop_back()
	current_track = next
	music_player.stream = music_tracks[next]
	music_player.play()

func _box(node_name: String, size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	if not DedicatedServer.active:
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		var map_surface_materials := load(MAP_SURFACE_MATERIALS_PATH) as Script
		mesh.material = map_surface_materials.create(color, _map_surface_for_box(node_name))
		mesh_instance.mesh = mesh
		body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _map_surface_for_box(node_name: String) -> String:
	if GameSession.bot_map_id == "twin_bastion":
		if "Boundary" in node_name or "CommandBlock" in node_name or "Wing" in node_name:
			return "painted_metal"
		if "Cover" in node_name or "Shield" in node_name:
			return "concrete"
		return "bastion_concrete"
	if GameSession.bot_map_id == "highrise":
		if "Office" in node_name or "Divider" in node_name or "ServiceCore" in node_name:
			return "glass"
		if "Parapet" in node_name or "Ramp" in node_name or "Column" in node_name or node_name.ends_with("Core"):
			return "painted_metal"
		if "Roof" in node_name:
			return "roof_membrane"
		return "bastion_concrete"
	if "Floor" in node_name:
		return "training_rubber"
	if "Cover" in node_name or "Deck" in node_name or "Bridge" in node_name:
		return "concrete"
	if "Tower" in node_name or "Parapet" in node_name or "Ramp" in node_name or "Landing" in node_name or "Rail" in node_name:
		return "bastion_concrete"
	return "painted_metal"
