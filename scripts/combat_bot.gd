extends CharacterBody3D

signal killed(bot: Node, attacker: Node)

const CombatHitbox = preload("res://scripts/combat_hitbox.gd")
const SuicideVestCharge = preload("res://scripts/suicide_vest_charge.gd")
const FallDamage = preload("res://scripts/fall_damage.gd")
const PortalManager = preload("res://scripts/portal_manager.gd")
const GrenadeProjectile = preload("res://scripts/grenade_projectile.gd")
const ThrowingAxe = preload("res://scripts/throwing_axe.gd")
const ForceImpactDamage = preload("res://scripts/force_impact_damage.gd")
const SOLDIER_RIG_PATH := "res://scripts/soldier_rig.gd"
const ZOMBIE_RIG_PATH := "res://scripts/zombie_rig.gd"
const HEADSHOT_EFFECT_PATH := "res://scripts/headshot_effect.gd"
const LIMB_DISMEMBERMENT_EFFECT_PATH := "res://scripts/limb_dismemberment_effect.gd"
const DEATH_VOICE_POOL_PATH := "res://scripts/death_voice_pool.gd"
const JETPACK_THRUSTER_AUDIO_PATH := "res://scripts/jetpack_thruster_audio.gd"
const COIL_LIGHTNING_EFFECT_PATH := "res://scripts/coil_lightning_effect.gd"
const KNIFE_IMPACT_SOUND_PATH := "res://sounds/sfx/knife-impact.mp3"
const RIFLE_SHOT_SOUND_PATH := "res://sounds/gun1/gunshot_trimmed.ogg"
const SHOTGUN_SHOT_SOUND_PATH := "res://sounds/gun1/shotgun_shot.mp3"
const SNIPER_SHOT_SOUND_PATH := "res://content/core/weapons/sniper/audio/fire.ogg"
const GROUND_POUND_SOUND_PATH := "res://sounds/sfx/grenade_explosion.mp3"
const PORTAL_SOUND_PATH := "res://sounds/sfx/portal-gun.mp3"
const DIFFICULTY_PROFILES := {
	"easy": {
		"move": 0.85, "reaction_min": 1.25, "reaction_max": 1.8,
		"reaction_acquire": 0.8, "reaction_recover": 1.6, "fire_interval": 1.3,
		"damage": 0.75, "accuracy": 0.7, "headshot": 0.04
	},
	"normal": {
		"move": 1.0, "reaction_min": 0.85, "reaction_max": 1.45,
		"reaction_acquire": 0.35, "reaction_recover": 1.1, "fire_interval": 1.0,
		"damage": 1.0, "accuracy": 1.0, "headshot": 0.08
	},
	"hard": {
		"move": 1.15, "reaction_min": 0.4, "reaction_max": 0.75,
		"reaction_acquire": 0.18, "reaction_recover": 0.6, "fire_interval": 0.78,
		"damage": 1.2, "accuracy": 1.25, "headshot": 0.13
	}
}

var target: CharacterBody3D
var target_candidates: Array[CharacterBody3D] = []
var waypoints: Array[Vector3] = []
var weapon_type := "ak47"
var base_weapon_type := "ak47"
var is_aiming := false
var team_id := 1
var entity_id := 0
var display_name := ""
var is_human_player := false
var passive_training_dummy := false
var max_health := 100.0
var health := 100.0
var alive := true
var time_since_damage := 999.0
var invulnerable_time := 0.0
var move_speed := 3.8
var destination := Vector3.ZERO
var navigation_step := Vector3.ZERO
var navigation_goal := Vector3.ZERO
var has_navigation_step := false
var blocked_route_point := Vector3.ZERO
var blocked_route_time := 0.0
var blocked_route_target_id := 0
var blocked_route_active := false
var last_climb_floor_position := Vector3.ZERO
var fire_cooldown := 0.0
var reaction_timer := 1.0
var target_refresh_timer := 0.0
var lost_sight_time := 0.0
var body_root: Node3D
var body_collision: CollisionShape3D
var hitboxes: Array[Area3D] = []
var muzzle_light: OmniLight3D
var gun_audio: AudioStreamPlayer3D
var knife_audio: AudioStreamPlayer3D
var death_voice_audio: AudioStreamPlayer3D
var jetpack_thruster_audio: AudioStreamPlayer3D
var tbag_audio: AudioStreamPlayer3D
var fall_death_y := -8.0
var soldier_rig: Node3D
var zombie_rig: Node3D
var nameplate: Label3D
var aim_pitch := 0.0
var current_vehicle: Node
var vehicle_seat := ""
var vehicle_goal: Node
var vehicle_seek_timer := 0.0
var difficulty_id := "normal"
var reaction_delay_min := 0.85
var reaction_delay_max := 1.45
var reaction_acquire_delay := 0.35
var reaction_recover_delay := 1.1
var fire_interval_multiplier := 1.0
var damage_multiplier := 1.0
var accuracy_multiplier := 1.0
var headshot_chance := 0.08
var last_hit_zone := "torso"
var last_hit_position := Vector3.ZERO
var last_hit_normal := Vector3.UP
var last_dismembered_limbs: Array[String] = []
var pending_explosion_intensity := 0.0
var objective_active := false
var objective_position := Vector3.ZERO
var mode_juggernaut := false
var mode_infected := false
var base_mode_move_speed := 3.8
var infection_marker: Node3D
var active_perks: Array[String] = []
var last_stand_used := false
var explosive_damage_multiplier := 1.0
var jetpack_owned := false
var jetpack_fuel := 0.0
var jetpack_boost_time := 0.0
var jetpack_tactical_cooldown := 0.0
var coil_gun_owned := false
var suicide_vest_owned := false
var suicide_vest_triggering := false
var physics_utility_id := ""
var ricochet_time := 0.0
var using_ricochet_path := false
var physics_utility_cooldown := 0.0
var force_held_target: Node3D
var force_hold_time := 0.0
var ground_pound_cooldown := 0.0
var grenades_remaining := 3
var grenade_type := "normal"
var sticky_bomb_panic_time := 0.0
var jump_cooldown := 0.0
var axes_remaining := 1
var throwable_cooldown := 0.0
var knife_engage_time := 0.0
var crouching := false
var tbagging := false
var taunt_target: Node3D
var taunt_time := 0.0
var tbag_phase := 0.0
var considered_taunt_targets: Dictionary = {}
var pickup_goal: Area3D
var pickup_seek_timer := 0.0
var pickup_best_distance := INF
var pickup_stall_time := 0.0
var unreachable_pickups: Dictionary = {}
var peak_fall_speed := 0.0
var portal_fall_attacker: Node
var portal_fall_credit_until := 0
const MODEL_FLOOR_OFFSET := -0.86
const JETPACK_MAX_FUEL := 4.0
const PORTAL_TACTIC_MIN_DISTANCE := 10.0
const PORTAL_TACTIC_MAX_DISTANCE := 28.0
const SPRINT_SPEED_MULTIPLIER := 1.65
const SPRINT_MIN_DISTANCE := 7.0
const SEPARATION_RADIUS := 1.15
const SEPARATION_WEIGHT := 1.35
const GROUND_POUND_TRIGGER_SPEED := 12.0
const GRENADE_THROW_SPEED := 16.0
const GRENADE_MAX_LOB_SPEED := 3.8
const GRENADE_TACTIC_MAX_DISTANCE := 18.0
const JUMP_VELOCITY := 5.0
const JUMP_PROBE_DISTANCE := 1.05
const PANIC_JUMP_PROBE_DISTANCE := 1.55
const FORCE_ACTOR_THROW_SPEED := 46.0
const FORCE_PROP_THROW_SPEED := 48.0
const FORCE_THROW_LIFT := 9.0
var portal_gun_owned := false
var portal_manager: Node3D
var portal_viewer: Camera3D
var portal_audio: AudioStreamPlayer3D
var portal_tactic_cooldown := 0.0
var portal_plan_active := false
var portal_plan_time := 0.0
var portal_reached_entrance := false

func setup(player_target: CharacterBody3D, navigation_points: Array[Vector3], assigned_weapon: String, assigned_team := 1, assigned_difficulty := "normal") -> void:
	target = player_target
	waypoints = navigation_points
	var bot_weapons := ContentRegistry.get_bot_loadout_weapon_ids()
	base_weapon_type = assigned_weapon if assigned_weapon in bot_weapons or assigned_weapon == "infected" else str(bot_weapons.pick_random())
	weapon_type = base_weapon_type
	team_id = assigned_team
	difficulty_id = assigned_difficulty if DIFFICULTY_PROFILES.has(assigned_difficulty) else "normal"
	_apply_difficulty_profile()

func enable_portal_gun() -> void:
	portal_gun_owned = true
	if is_inside_tree() and not is_instance_valid(portal_manager):
		_build_portal_gear()

func _apply_difficulty_profile() -> void:
	var profile: Dictionary = DIFFICULTY_PROFILES[difficulty_id]
	move_speed = 3.8 * float(profile["move"])
	base_mode_move_speed = move_speed
	reaction_delay_min = float(profile["reaction_min"])
	reaction_delay_max = float(profile["reaction_max"])
	reaction_acquire_delay = float(profile["reaction_acquire"])
	reaction_recover_delay = float(profile["reaction_recover"])
	fire_interval_multiplier = float(profile["fire_interval"])
	damage_multiplier = float(profile["damage"])
	accuracy_multiplier = float(profile["accuracy"])
	headshot_chance = float(profile["headshot"])

func set_target_candidates(candidates: Array[CharacterBody3D]) -> void:
	target_candidates = candidates
	_select_nearest_target()

func _ready() -> void:
	add_to_group("combatants")
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	safe_margin = 0.04
	_build_model()
	if portal_gun_owned:
		_build_portal_gear()
	last_climb_floor_position = global_position
	reaction_timer = randf_range(reaction_delay_min, reaction_delay_max)
	throwable_cooldown = randf_range(2.0, 4.0)
	_choose_destination()

func _build_model() -> void:
	body_collision = CollisionShape3D.new()
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.36
	body_shape.height = 1.75
	body_collision.shape = body_shape
	add_child(body_collision)
	body_root = Node3D.new()
	body_root.name = "BlueTeamModel" if team_id == 0 else "RedTeamModel"
	body_root.position.y = MODEL_FLOOR_OFFSET
	add_child(body_root)
	var uniform_color := Color("#3975a8") if team_id == 0 else Color("#a84d43")
	if not NetworkSession.is_dedicated_server:
		var soldier_rig_script = load(SOLDIER_RIG_PATH)
		soldier_rig = soldier_rig_script.new()
		soldier_rig.team_color = uniform_color
		soldier_rig.set_equipped_weapon(weapon_type)
		body_root.add_child(soldier_rig)
		nameplate = Label3D.new()
		nameplate.text = display_name if not display_name.is_empty() else str(name).replace("_", " ")
		nameplate.position.y = 1.35
		nameplate.font_size = 30
		nameplate.outline_size = 7
		nameplate.modulate = uniform_color
		nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# The default depth test prevents names revealing bots through walls.
		nameplate.no_depth_test = false
		add_child(nameplate)
	_add_hitbox("head", 2.0, Vector3(0, 0.66, 0), Vector3(0.48, 0.48, 0.46))
	_add_hitbox("torso", 1.0, Vector3(0, 0.14, 0), Vector3(0.52, 0.68, 0.40))
	_add_hitbox("arm_l", 0.75, Vector3(-0.38, 0.34, 0), Vector3(0.22, 0.58, 0.32))
	_add_hitbox("arm_r", 0.75, Vector3(0.38, 0.34, 0), Vector3(0.22, 0.58, 0.32))
	_add_hitbox("leg_l", 0.75, Vector3(-0.15, -0.40, 0), Vector3(0.24, 0.80, 0.34))
	_add_hitbox("leg_r", 0.75, Vector3(0.15, -0.40, 0), Vector3(0.24, 0.80, 0.34))
	muzzle_light = OmniLight3D.new()
	muzzle_light.position = Vector3(0, 1.32, -0.88)
	muzzle_light.light_color = Color("#ffbb55")
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 2.5
	body_root.add_child(muzzle_light)
	gun_audio = AudioStreamPlayer3D.new()
	if not NetworkSession.is_dedicated_server:
		gun_audio.stream = load(RIFLE_SHOT_SOUND_PATH)
	gun_audio.bus = "SFX"
	gun_audio.volume_db = -10.0
	gun_audio.max_distance = 45.0
	gun_audio.max_polyphony = 3
	add_child(gun_audio)
	knife_audio = AudioStreamPlayer3D.new()
	knife_audio.name = "KnifeImpactAudio"
	if not NetworkSession.is_dedicated_server:
		knife_audio.stream = load(KNIFE_IMPACT_SOUND_PATH)
	knife_audio.bus = "SFX"
	knife_audio.volume_db = -1.0
	knife_audio.max_distance = 40.0
	add_child(knife_audio)
	death_voice_audio = AudioStreamPlayer3D.new()
	death_voice_audio.name = "DeathVoiceAudio"
	death_voice_audio.bus = "SFX"
	death_voice_audio.volume_db = -2.0
	death_voice_audio.max_distance = 55.0
	add_child(death_voice_audio)
	if not NetworkSession.is_dedicated_server:
		var jetpack_audio_script = load(JETPACK_THRUSTER_AUDIO_PATH)
		jetpack_thruster_audio = jetpack_audio_script.new()
		add_child(jetpack_thruster_audio)

func _add_hitbox(zone: String, multiplier: float, pos: Vector3, size: Vector3) -> void:
	var hitbox := CombatHitbox.new()
	var shape := BoxShape3D.new()
	shape.size = size
	hitbox.configure(self, zone, multiplier, shape, pos)
	hitbox.set_meta("standing_y", pos.y)
	add_child(hitbox)
	hitboxes.append(hitbox)

func _physics_process(delta: float) -> void:
	if jetpack_thruster_audio:
		jetpack_thruster_audio.set_thrusting(false)
	if not alive:
		return
	jump_cooldown = maxf(jump_cooldown - delta, 0.0)
	blocked_route_time = maxf(blocked_route_time - delta, 0.0)
	if is_on_floor():
		last_climb_floor_position = global_position
	elif has_navigation_step and navigation_goal.y > last_climb_floor_position.y + 1.8 and global_position.y < last_climb_floor_position.y - 1.0:
		global_position = last_climb_floor_position
		velocity = Vector3.ZERO
	if global_position.y < fall_death_y:
		last_hit_zone = "fall"
		_die(_portal_fall_credit())
		return
	if _update_sticky_bomb_panic(delta):
		_update_crouch_stance(delta)
		_update_soldier_animation(delta, false)
		return
	if passive_training_dummy:
		invulnerable_time = maxf(invulnerable_time - delta, 0.0)
		time_since_damage += delta
		if time_since_damage >= 5.0 and health < max_health:
			health = minf(health + 25.0 * delta, max_health)
		velocity.x = move_toward(velocity.x, 0.0, delta * 8.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 8.0)
		if not is_on_floor():
			velocity += get_gravity() * delta
		_move_and_slide_with_fall_damage()
		_update_soldier_animation(delta, false)
		return
	invulnerable_time = maxf(invulnerable_time - delta, 0.0)
	target_refresh_timer -= delta
	if target_refresh_timer <= 0.0 or not _is_valid_enemy(target):
		_select_nearest_target()
	time_since_damage += delta
	if time_since_damage >= 5.0 and health < max_health:
		health = minf(health + 25.0 * delta, max_health)
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	throwable_cooldown = maxf(throwable_cooldown - delta, 0.0)
	ricochet_time = maxf(ricochet_time - delta, 0.0)
	physics_utility_cooldown = maxf(physics_utility_cooldown - delta, 0.0)
	ground_pound_cooldown = maxf(ground_pound_cooldown - delta, 0.0)
	portal_tactic_cooldown = maxf(portal_tactic_cooldown - delta, 0.0)
	muzzle_light.light_energy = move_toward(muzzle_light.light_energy, 0.0, delta * 45.0)
	if current_vehicle:
		crouching = false
		_set_tbagging(false)
		_update_crouch_stance(delta)
		_update_vehicle_combat(delta)
		return
	if _update_tbag_taunt(delta):
		_update_crouch_stance(delta)
		_update_soldier_animation(delta, false)
		return
	_update_crouch_stance(delta)
	if _update_portal_tactics(delta):
		_update_soldier_animation(delta, false)
		return
	_update_jetpack_tactics(delta)
	_update_physics_tactics(delta)
	# Objectives guide the bot when combat is quiet, but never suppress a visible
	# enemy. This keeps KOTH bots pushing uphill without blindly walking past
	# opponents along the shared ascent routes.
	var visible_combat_threat := _is_valid_enemy(target) and global_position.distance_to(target.global_position) < 30.0 and _has_line_of_sight()
	if objective_active and not visible_combat_threat and Vector2(global_position.x - objective_position.x, global_position.z - objective_position.z).length() > 5.0:
		_move_toward_point(objective_position, delta)
		_update_soldier_animation(delta, false)
		return
	pickup_seek_timer -= delta
	if pickup_seek_timer <= 0.0:
		pickup_seek_timer = randf_range(0.4, 0.7)
		var next_pickup := _nearest_desired_pickup(35.0)
		if next_pickup != pickup_goal:
			pickup_goal = next_pickup
			pickup_best_distance = INF
			pickup_stall_time = 0.0
	if is_instance_valid(pickup_goal) and _wants_pickup(pickup_goal):
		if visible_combat_threat:
			pickup_goal = null
			pickup_best_distance = INF
			pickup_stall_time = 0.0
		else:
			var pickup_distance := global_position.distance_to(pickup_goal.global_position)
			if pickup_distance < pickup_best_distance - 0.2:
				pickup_best_distance = pickup_distance
				pickup_stall_time = 0.0
			else:
				pickup_stall_time += delta
			if pickup_stall_time >= 2.5:
				unreachable_pickups[pickup_goal.get_instance_id()] = Time.get_ticks_msec() + 8000
				pickup_goal = null
				pickup_best_distance = INF
				pickup_stall_time = 0.0
			else:
				_move_toward_point(pickup_goal.global_position, delta)
				_update_soldier_animation(delta, false)
				return
	else:
		pickup_goal = null
	if not mode_infected:
		vehicle_seek_timer -= delta
		if vehicle_seek_timer <= 0.0:
			vehicle_seek_timer = randf_range(0.8, 1.4)
			vehicle_goal = _nearest_available_vehicle(12.0)
	if vehicle_goal:
		if not is_instance_valid(vehicle_goal) or not vehicle_goal.alive or vehicle_goal.get_open_seat_for(self).is_empty():
			vehicle_goal = null
		else:
			if global_position.distance_to(vehicle_goal.global_position) < 3.0:
				vehicle_goal.request_seat(self)
				vehicle_goal = null
			else:
				_move_toward_point(vehicle_goal.global_position, delta)
				_update_soldier_animation(delta, false)
			return
	if not target or not target.alive:
		knife_engage_time = 0.0
		aim_pitch = move_toward(aim_pitch, 0.0, delta * 2.5)
		_patrol(delta)
		_update_soldier_animation(delta, false)
		return
	var distance := global_position.distance_to(target.global_position)
	var can_see := distance < 30.0 and _has_line_of_sight()
	if can_see:
		lost_sight_time = 0.0
		blocked_route_active = false
		reaction_timer -= delta
		_engage(delta, distance)
	else:
		knife_engage_time = 0.0
		reaction_timer = minf(reaction_timer + delta, reaction_recover_delay)
		lost_sight_time += delta
		var pursuit_point := _blocked_pursuit_point(target.global_position)
		if blocked_route_active or lost_sight_time < 3.0:
			_move_toward_point(pursuit_point, delta)
		else:
			_patrol(delta)
	_update_soldier_animation(delta, can_see)

func _build_portal_gear() -> void:
	portal_viewer = Camera3D.new()
	portal_viewer.name = "PortalViewer"
	portal_viewer.position = Vector3(0, 1.05, 0)
	portal_viewer.current = false
	add_child(portal_viewer)
	portal_manager = PortalManager.new()
	portal_manager.name = "BotPortalManager"
	get_tree().current_scene.add_child.call_deferred(portal_manager)
	portal_manager.call_deferred("setup", portal_viewer, self)
	portal_audio = AudioStreamPlayer3D.new()
	if not NetworkSession.is_dedicated_server:
		portal_audio.stream = load(PORTAL_SOUND_PATH)
	portal_audio.bus = "SFX"
	portal_audio.volume_db = -5.0
	portal_audio.max_distance = 48.0
	add_child(portal_audio)
	portal_tactic_cooldown = randf_range(4.0, 8.0)
	tree_exiting.connect(_cleanup_portal_gear)

func _cleanup_portal_gear() -> void:
	if is_instance_valid(portal_manager):
		portal_manager.queue_free()

func _update_portal_tactics(delta: float) -> bool:
	if not portal_gun_owned or mode_infected or not is_instance_valid(portal_manager):
		return false
	if portal_plan_active:
		portal_plan_time += delta
		var entrance: Area3D = portal_manager.portals[0] if is_instance_valid(portal_manager.portals[0]) else null
		if not entrance or not is_instance_valid(portal_manager.portals[1]) or portal_plan_time > 6.0:
			_cancel_portal_plan()
			return false
		var entrance_distance := global_position.distance_to(entrance.global_position)
		if entrance_distance < 2.1:
			portal_reached_entrance = true
		if portal_reached_entrance and entrance_distance > 5.0:
			portal_plan_active = false
			portal_tactic_cooldown = randf_range(12.0, 18.0)
			return false
		_move_directly_into_portal(entrance, delta)
		return true
	if portal_tactic_cooldown > 0.0 or not _is_valid_enemy(target):
		return false
	var distance := global_position.distance_to(target.global_position)
	if distance < PORTAL_TACTIC_MIN_DISTANCE or distance > PORTAL_TACTIC_MAX_DISTANCE or not _has_line_of_sight():
		return false
	_try_begin_portal_flank()
	return portal_plan_active

func _try_begin_portal_flank() -> void:
	portal_tactic_cooldown = randf_range(7.0, 11.0)
	var origin := global_position + Vector3.UP * 1.05
	var toward_target := (target.global_position + Vector3.UP * 0.55 - origin).normalized()
	var exclusions: Array[RID] = [get_rid()]
	var exit_placed := false
	var target_floor_direction := (target.global_position - Vector3.UP * 1.05 - origin).normalized()
	for direction in [target_floor_direction, toward_target, toward_target.rotated(Vector3.UP, -0.14), toward_target.rotated(Vector3.UP, 0.14)]:
		if portal_manager.place_portal_from(1, origin, direction, 42.0, exclusions):
			var exit_portal: Area3D = portal_manager.portals[1]
			if exit_portal.global_position.distance_to(target.global_position) + 4.0 < global_position.distance_to(target.global_position):
				exit_placed = true
				break
			portal_manager.remove_portal(1)
	if not exit_placed:
		return
	var backward := -Vector3(toward_target.x, 0.0, toward_target.z).normalized()
	var nearby_floor_direction := (global_position + backward * 3.2 - Vector3.UP * 1.05 - origin).normalized()
	var entrance_placed := false
	for direction in [nearby_floor_direction, backward, backward.rotated(Vector3.UP, 0.72), backward.rotated(Vector3.UP, -0.72)]:
		if portal_manager.place_portal_from(0, origin, direction, 18.0, exclusions):
			entrance_placed = true
			break
	if not entrance_placed:
		portal_manager.remove_portal(1)
		return
	portal_plan_active = true
	portal_plan_time = 0.0
	portal_reached_entrance = false
	_play_portal_shot(1)
	_play_portal_shot(0)
	_publish_portal_placement(1)
	_publish_portal_placement(0)

func _move_directly_into_portal(entrance: Area3D, delta: float) -> void:
	var direction := entrance.global_position - global_position
	var portal_distance := Vector2(direction.x, direction.z).length()
	direction.y = 0.0
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		look_at(global_position + direction, Vector3.UP)
	var travel_speed := move_speed * SPRINT_SPEED_MULTIPLIER if portal_distance > 3.5 and is_on_floor() else move_speed
	velocity.x = move_toward(velocity.x, direction.x * travel_speed, delta * 12.0)
	velocity.z = move_toward(velocity.z, direction.z * travel_speed, delta * 12.0)
	if not is_on_floor():
		velocity += get_gravity() * delta
	_move_and_slide_with_fall_damage()

func _cancel_portal_plan() -> void:
	portal_plan_active = false
	portal_reached_entrance = false
	portal_tactic_cooldown = randf_range(6.0, 10.0)

func _play_portal_shot(index: int) -> void:
	muzzle_light.light_color = Color("#27a8ff") if index == 0 else Color("#ff8a22")
	muzzle_light.light_energy = 7.0
	if soldier_rig:
		soldier_rig.play_shot()
	if portal_audio:
		portal_audio.pitch_scale = 0.92 if index == 0 else 1.08
		portal_audio.play()

func _publish_portal_placement(index: int) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("bot_placed_portal") and is_instance_valid(portal_manager.portals[index]):
		scene.bot_placed_portal(self, index, portal_manager.portals[index].global_transform)

func _patrol(delta: float) -> void:
	if global_position.distance_to(destination) < 1.2:
		_choose_destination()
	_move_toward_point(destination, delta)

func _engage(delta: float, distance: float) -> void:
	var target_flat := Vector3(target.global_position.x, global_position.y, target.global_position.z)
	look_at(target_flat, Vector3.UP)
	var target_height := target.global_position.y + 0.55
	var horizontal_distance := maxf(Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length(), 0.01)
	aim_pitch = clampf(atan2(target_height - (global_position.y + 0.52), horizontal_distance), -0.35, 0.42)
	if suicide_vest_triggering:
		_move_toward_point(target.global_position, delta)
		return
	if suicide_vest_owned and not suicide_vest_triggering:
		if distance <= 5.5:
			trigger_suicide_vest()
		else:
			_move_toward_point(target.global_position, delta)
		return
	if mode_infected:
		_move_toward_point(target.global_position, delta)
		if distance <= 1.8 and reaction_timer <= 0.0 and fire_cooldown <= 0.0:
			fire_cooldown = 0.75 * fire_interval_multiplier
			reaction_timer = 0.2
			if zombie_rig:
				zombie_rig.play_attack()
			var hit_position := target.global_position + Vector3.UP * 0.35
			if target.has_method("receive_zone_hit"):
				target.receive_zone_hit(55.0 * damage_multiplier, "torso", hit_position, (global_position - target.global_position).normalized(), self)
			else:
				target.apply_damage(55.0 * damage_multiplier, global_position, self)
		return
	if distance <= 2.1:
		knife_engage_time += delta
	else:
		knife_engage_time = 0.0
	if distance <= 2.1 and knife_engage_time >= _knife_windup_duration() and reaction_timer <= 0.0 and fire_cooldown <= 0.0:
		_knife_target()
		return
	if reaction_timer <= 0.0 and fire_cooldown <= 0.0 and _try_throwable(distance):
		return
	var right := global_transform.basis.x * (1.0 if int(Time.get_ticks_msec() / 1800 + get_instance_id()) % 2 == 0 else -1.0)
	var desired := target.global_position + right * 4.0
	if distance > 13.0:
		_move_toward_point(desired, delta)
	else:
		velocity.x = move_toward(velocity.x, right.x * 2.2, delta * 8.0)
		velocity.z = move_toward(velocity.z, right.z * 2.2, delta * 8.0)
		if not is_on_floor() and jetpack_boost_time <= 0.0:
			velocity += get_gravity() * delta
		_move_and_slide_with_fall_damage()
	if reaction_timer <= 0.0 and fire_cooldown <= 0.0:
		_fire_at_player(distance)

func _try_throwable(distance: float) -> bool:
	if throwable_cooldown > 0.0 or mode_infected or not _is_valid_enemy(target):
		return false
	var can_throw_grenade := grenades_remaining > 0 and distance >= 9.0 and distance <= GRENADE_TACTIC_MAX_DISTANCE
	var can_throw_axe := axes_remaining > 0 and distance >= 4.0 and distance <= 17.0
	if not can_throw_grenade and not can_throw_axe:
		return false
	# Failed opportunities get reconsidered soon; successful throws have a much
	# longer tactical pause so bots do not unload every throwable at once.
	throwable_cooldown = randf_range(0.9, 1.5)
	var use_axe := can_throw_axe and (not can_throw_grenade or randf() < 0.15)
	var throw_chance := clampf((0.08 if use_axe else 0.52) * accuracy_multiplier, 0.04 if use_axe else 0.35, 0.14 if use_axe else 0.75)
	if randf() > throw_chance:
		return false
	var thrown := _throw_axe_at_target() if use_axe else _throw_grenade_at_target()
	if thrown:
		fire_cooldown = 0.85 * fire_interval_multiplier
		reaction_timer = 0.2
		throwable_cooldown = randf_range(5.0, 8.0)
	return thrown

func _throw_grenade_at_target() -> bool:
	var start := global_position + Vector3.UP * 0.62 - global_transform.basis.z * 0.48
	var target_position := _predicted_throw_target(GRENADE_THROW_SPEED, 0.15)
	var launch_velocity := _ballistic_velocity(start, target_position, GRENADE_THROW_SPEED)
	if not launch_velocity.is_finite():
		return false
	launch_velocity.y = minf(launch_velocity.y, GRENADE_MAX_LOB_SPEED)
	var scene := get_tree().current_scene
	if scene and scene.has_method("bot_throw_grenade"):
		return scene.bot_throw_grenade(self, start, launch_velocity)
	grenades_remaining -= 1
	var grenade := GrenadeProjectile.new()
	grenade.configure(grenade_type)
	scene.add_child(grenade)
	var exclusions: Array[PhysicsBody3D] = [self]
	grenade.launch(self, start, launch_velocity, exclusions)
	return true

func _throw_axe_at_target() -> bool:
	var start := global_position + Vector3.UP * 0.62 - global_transform.basis.z * 0.55
	var target_position := _predicted_throw_target(28.0, 0.48)
	var launch_velocity := _ballistic_velocity(start, target_position, 28.0)
	if not launch_velocity.is_finite():
		return false
	var spin_axis := global_transform.basis.x.normalized()
	var scene := get_tree().current_scene
	if scene and scene.has_method("bot_throw_axe"):
		return scene.bot_throw_axe(self, start, launch_velocity, spin_axis)
	axes_remaining -= 1
	var axe := ThrowingAxe.new()
	scene.add_child(axe)
	var exclusions: Array[PhysicsBody3D] = [self]
	axe.launch(self, start, launch_velocity, spin_axis, exclusions)
	return true

func _predicted_throw_target(projectile_speed: float, height: float) -> Vector3:
	var target_position := target.global_position + Vector3.UP * height
	var flat_distance := Vector2(target_position.x - global_position.x, target_position.z - global_position.z).length()
	var flight_time := flat_distance / projectile_speed
	var target_velocity = target.get("velocity")
	if target_velocity is Vector3:
		target_position += Vector3(target_velocity.x, 0.0, target_velocity.z) * flight_time * 0.65
	return target_position

func _ballistic_velocity(start: Vector3, destination: Vector3, horizontal_speed: float) -> Vector3:
	var flat_offset := Vector3(destination.x - start.x, 0.0, destination.z - start.z)
	var flat_distance := flat_offset.length()
	if flat_distance < 0.1:
		return Vector3.INF
	var flight_time := flat_distance / horizontal_speed
	var gravity := absf(get_gravity().y)
	var vertical_speed := (destination.y - start.y + 0.5 * gravity * flight_time * flight_time) / flight_time
	return flat_offset.normalized() * horizontal_speed + Vector3.UP * vertical_speed + velocity * 0.2

func _knife_target() -> void:
	fire_cooldown = 1.35 * fire_interval_multiplier
	reaction_timer = 0.25
	knife_engage_time = 0.0
	if soldier_rig:
		soldier_rig.play_shot()
	if knife_audio:
		knife_audio.play()
	var hit_position := target.global_position + Vector3.UP * 0.35
	var hit_normal := (global_position - target.global_position).normalized()
	if target.has_method("receive_zone_hit"):
		target.receive_zone_hit(10000.0, "torso", hit_position, hit_normal, self)
	else:
		target.apply_damage(10000.0, global_position, self)

func _knife_windup_duration() -> float:
	match difficulty_id:
		"easy": return 0.85
		"hard": return 0.45
	return 0.65

func _move_toward_point(point: Vector3, delta: float) -> void:
	var movement_point := _elevation_navigation_point(point)
	var direction := Vector3(movement_point.x - global_position.x, 0, movement_point.z - global_position.z).normalized()
	direction = _apply_combatant_separation(direction)
	var is_elevation_route := has_navigation_step and absf(navigation_goal.y - global_position.y) > 1.8
	var is_climbing_link := has_navigation_step and absf(navigation_step.y - global_position.y) > 0.2
	var route_step_distance := Vector2(navigation_step.x - global_position.x, navigation_step.z - global_position.z).length() if has_navigation_step else INF
	var goal_distance := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	var travel_speed := move_speed * SPRINT_SPEED_MULTIPLIER if goal_distance >= SPRINT_MIN_DISTANCE and not is_elevation_route and is_on_floor() else move_speed
	# Compact ramp portals sit close to the tower shell. Finish the short staging
	# leg directly so a sloped collision side cannot pin the bot at the floor edge.
	if is_elevation_route and route_step_distance < 10.0:
		global_position.x = move_toward(global_position.x, navigation_step.x, delta * move_speed)
		global_position.z = move_toward(global_position.z, navigation_step.z, delta * move_speed)
		if is_climbing_link and route_step_distance < 2.5:
			global_position.y = navigation_step.y
		else:
			global_position.y = move_toward(global_position.y, navigation_step.y, delta * 4.0)
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0
		return
	if not is_elevation_route or (not is_climbing_link and route_step_distance >= 10.0):
		_try_jump_over_obstacle(direction)
		var probe_origin := global_position + Vector3(0, 0.55, 0)
		var probe := PhysicsRayQueryParameters3D.create(probe_origin, probe_origin + direction * 1.35)
		probe.collision_mask = 1
		if not get_world_3d().direct_space_state.intersect_ray(probe).is_empty():
			var side := 1.0 if get_instance_id() % 2 == 0 else -1.0
			direction = Vector3(-direction.z * side, 0, direction.x * side)
	if direction.length_squared() > 0.01:
		look_at(global_position + direction, Vector3.UP)
	velocity.x = move_toward(velocity.x, direction.x * travel_speed, delta * 10.0)
	velocity.z = move_toward(velocity.z, direction.z * travel_speed, delta * 10.0)
	if is_climbing_link:
		var step_horizontal_distance := Vector2(navigation_step.x - global_position.x, navigation_step.z - global_position.z).length()
		if step_horizontal_distance < 4.0:
			global_position.y = move_toward(global_position.y, navigation_step.y, delta * 4.0)
			velocity.y = 0.0
	if not is_on_floor():
		velocity += get_gravity() * delta
	_move_and_slide_with_fall_damage()

func _blocked_pursuit_point(goal: Vector3) -> Vector3:
	if waypoints.is_empty() or not is_instance_valid(target):
		blocked_route_active = false
		return goal
	var target_id := target.get_instance_id()
	if blocked_route_active and blocked_route_target_id == target_id and blocked_route_time > 0.0 and global_position.distance_to(blocked_route_point) > 1.15:
		return blocked_route_point
	blocked_route_active = false
	blocked_route_target_id = target_id
	blocked_route_time = 1.25
	var direct_distance := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
	var best_score := INF
	var best_point := Vector3.ZERO
	var combatants := get_tree().get_nodes_in_group("combatants")
	for waypoint_index in waypoints.size():
		var waypoint := waypoints[waypoint_index]
		var travel_distance := Vector2(waypoint.x - global_position.x, waypoint.z - global_position.z).length()
		if travel_distance < 1.0 or travel_distance > 42.0 or not _navigation_segment_clear(global_position, waypoint):
			continue
		var remaining_distance := Vector2(goal.x - waypoint.x, goal.z - waypoint.z).length()
		var sees_target := _navigation_segment_clear(waypoint, goal)
		# If this is not yet the doorway/corner that exposes the target, it must at
		# least make meaningful progress before being considered as an intermediate.
		if not sees_target and remaining_distance >= direct_distance - 0.75:
			continue
		var crowd_penalty := 0.0
		for candidate in combatants:
			if candidate == self or candidate is not Node3D or candidate.get("alive") != true:
				continue
			if (candidate as Node3D).global_position.distance_squared_to(waypoint) < 2.5 * 2.5:
				crowd_penalty += 2.5
		var target_weight := 0.65 if sees_target else 1.0
		var visibility_bonus := -24.0 if sees_target else 0.0
		var route_spread := sin(float(get_instance_id() % 997) * 0.17 + float(waypoint_index) * 1.91) * 1.4
		var score := travel_distance + remaining_distance * target_weight + crowd_penalty + visibility_bonus + route_spread
		if score < best_score:
			best_score = score
			best_point = waypoint
	if best_score < INF:
		blocked_route_point = best_point
		blocked_route_active = true
		return blocked_route_point
	return goal

func _navigation_segment_clear(from: Vector3, to: Vector3) -> bool:
	# Check the capsule's lower body, centre, and head clearance. A centre-only
	# ray incorrectly treats the wedge beneath a stair ramp as a valid route.
	for height_value in [-0.55, 0.0, 0.72]:
		var height := float(height_value)
		var height_offset: Vector3 = Vector3.UP * height
		var query := PhysicsRayQueryParameters3D.create(from + height_offset, to + height_offset)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return true

func _try_jump_over_obstacle(direction: Vector3, urgent := false) -> bool:
	if not is_on_floor() or jump_cooldown > 0.0 or direction.length_squared() < 0.01:
		return false
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	var probe_distance := PANIC_JUMP_PROBE_DISTANCE if urgent else JUMP_PROBE_DISTANCE
	# Probe near the bot's feet, then again above waist height. A hit below with
	# clear space above identifies debris or a short ledge instead of a full wall.
	var low_origin := global_position + Vector3.UP * -0.72
	var high_origin := global_position + Vector3.UP * 0.28
	var low_query := PhysicsRayQueryParameters3D.create(low_origin, low_origin + forward * probe_distance)
	low_query.collision_mask = 1
	low_query.exclude = [get_rid()]
	if get_world_3d().direct_space_state.intersect_ray(low_query).is_empty():
		return false
	var high_query := PhysicsRayQueryParameters3D.create(high_origin, high_origin + forward * probe_distance)
	high_query.collision_mask = 1
	high_query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(high_query).is_empty():
		return false
	velocity.y = JUMP_VELOCITY
	jump_cooldown = 0.55
	return true

func _move_and_slide_with_fall_damage() -> void:
	var was_airborne := not is_on_floor()
	var pre_move_speed := velocity.length()
	if was_airborne:
		peak_fall_speed = maxf(peak_fall_speed, maxf(-velocity.y, 0.0))
	move_and_slide()
	if pre_move_speed >= 12.0 and get_slide_collision_count() > 0 and _portal_fall_credit() != null:
		receive_zone_hit(clampf((pre_move_speed - 10.0) * 2.5, 5.0, 45.0), "impact", global_position, Vector3.UP, _portal_fall_credit())
		_clear_portal_fall_credit()
		if not alive:
			return
	if not is_on_floor():
		peak_fall_speed = maxf(peak_fall_speed, maxf(-velocity.y, 0.0))
		return
	var landing_speed := peak_fall_speed
	peak_fall_speed = 0.0
	if not alive or not was_airborne:
		_clear_portal_fall_credit()
		return
	if "shockwave_ground_pound" in active_perks and ground_pound_cooldown <= 0.0 and landing_speed >= GROUND_POUND_TRIGGER_SPEED:
		ground_pound_cooldown = 5.0
		_trigger_bot_ground_pound()
		return
	var damage := FallDamage.calculate(landing_speed)
	if damage > 0.0:
		receive_zone_hit(damage, "fall", global_position, Vector3.UP, _portal_fall_credit())
	if alive:
		_clear_portal_fall_credit()

func _update_physics_tactics(delta: float) -> void:
	if physics_utility_id != "force":
		_cancel_bot_force_audio()
		force_held_target = null
		return
	if is_instance_valid(force_held_target):
		_update_held_force_target(delta)
		return
	if force_held_target != null:
		_cancel_bot_force_audio()
		force_held_target = null
	if physics_utility_cooldown > 0.0 or not _is_valid_enemy(target):
		return
	var distance := global_position.distance_to(target.global_position)
	if distance > 18.0:
		return
	var throwable := _nearest_force_throwable(13.0)
	if throwable:
		force_held_target = throwable
		force_hold_time = 0.45
		_start_bot_force_audio(throwable)
		return
	var direction := (target.global_position - global_position).normalized()
	if distance < 6.0:
		_start_bot_force_audio(target)
		_apply_character_velocity(target, direction * FORCE_ACTOR_THROW_SPEED + Vector3.UP * FORCE_THROW_LIFT, true)
		_mark_force_kill_credit(target)
		_finish_bot_force_audio(true)
		physics_utility_cooldown = randf_range(3.5, 5.0)
		return
	force_held_target = target
	force_hold_time = 0.38
	_mark_force_kill_credit(target)
	_start_bot_force_audio(target)

func _update_held_force_target(delta: float) -> void:
	_update_bot_force_audio(delta)
	force_hold_time -= delta
	var aim_target: Node3D = target if _is_valid_enemy(target) else null
	var forward := -global_transform.basis.z
	if aim_target:
		forward = (aim_target.global_position - global_position).normalized()
	var hold_point := global_position + Vector3.UP * 1.2 + forward * 3.0
	var desired_velocity := ((hold_point - force_held_target.global_position) / 0.1).limit_length(55.0)
	if force_held_target is RigidBody3D:
		(force_held_target as RigidBody3D).linear_velocity = desired_velocity
	elif force_held_target is CharacterBody3D:
		_apply_character_velocity(force_held_target as CharacterBody3D, desired_velocity, true)
	if force_hold_time > 0.0:
		return
	var threw_character := force_held_target.is_in_group("combatants")
	if force_held_target is RigidBody3D and aim_target:
		var target_velocity: Vector3 = aim_target.get("velocity") if aim_target.get("velocity") is Vector3 else Vector3.ZERO
		var predicted_position: Vector3 = aim_target.global_position + target_velocity * 0.25 + Vector3.UP * 0.7
		var prop_throw_direction: Vector3 = (predicted_position - force_held_target.global_position).normalized()
		(force_held_target as RigidBody3D).linear_velocity = prop_throw_direction * FORCE_PROP_THROW_SPEED
		_arm_bot_force_impact(force_held_target as RigidBody3D)
	elif force_held_target is CharacterBody3D:
		var actor_throw_direction: Vector3 = (force_held_target.global_position - global_position).normalized()
		_apply_character_velocity(force_held_target as CharacterBody3D, actor_throw_direction * FORCE_ACTOR_THROW_SPEED + Vector3.UP * FORCE_THROW_LIFT, true)
		_mark_force_kill_credit(force_held_target)
	_finish_bot_force_audio(threw_character)
	force_held_target = null
	physics_utility_cooldown = randf_range(3.5, 6.0)

func _start_bot_force_audio(_candidate: Node3D) -> void:
	pass

func _update_bot_force_audio(_delta: float) -> void:
	pass

func _finish_bot_force_audio(_threw_character: bool) -> void:
	pass

func _cancel_bot_force_audio() -> void:
	pass

func _nearest_force_throwable(max_distance: float) -> RigidBody3D:
	var nearest: RigidBody3D
	var nearest_distance := max_distance * max_distance
	for candidate in get_tree().get_nodes_in_group("physics_objects"):
		if candidate is not RigidBody3D or not is_instance_valid(candidate):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest

func _arm_bot_force_impact(body: RigidBody3D) -> void:
	var existing := body.get_node_or_null("ForceImpactDamage")
	if existing and existing.has_method("configure"):
		existing.configure(body, self)
		return
	var impact_damage := ForceImpactDamage.new()
	impact_damage.name = "ForceImpactDamage"
	impact_damage.configure(body, self)
	body.add_child(impact_damage)

func _mark_force_kill_credit(candidate: Node) -> void:
	if candidate.has_method("set_physics_kill_credit"):
		candidate.set_physics_kill_credit(self)
	elif candidate.has_method("set_portal_fall_credit"):
		candidate.set_portal_fall_credit(self)

func _apply_character_velocity(candidate: CharacterBody3D, value: Vector3, replace: bool) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("apply_lan_character_velocity"):
		scene.apply_lan_character_velocity(candidate, value, replace)
	elif replace:
		candidate.velocity = value
	else:
		candidate.velocity += value

func _trigger_bot_ground_pound() -> void:
	var radius := 7.0
	if not NetworkSession.is_dedicated_server:
		var impact_audio := AudioStreamPlayer3D.new()
		impact_audio.stream = load(GROUND_POUND_SOUND_PATH)
		impact_audio.bus = "SFX"
		impact_audio.volume_db = -1.0
		impact_audio.max_distance = 65.0
		get_tree().current_scene.add_child(impact_audio)
		impact_audio.global_position = global_position
		impact_audio.finished.connect(impact_audio.queue_free)
		impact_audio.play()
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if candidate == self or candidate is not CharacterBody3D or not is_instance_valid(candidate):
			continue
		var offset: Vector3 = candidate.global_position - global_position
		var distance := offset.length()
		if distance > radius:
			continue
		var strength := 1.0 - distance / radius
		var direction := Vector3(offset.x, 0.0, offset.z).normalized()
		_apply_character_velocity(candidate, direction * lerpf(5.0, 15.0, strength) + Vector3.UP * lerpf(4.0, 9.0, strength), false)
		if candidate.has_method("set_physics_kill_credit"):
			candidate.set_physics_kill_credit(self)
		elif candidate.has_method("set_portal_fall_credit"):
			candidate.set_portal_fall_credit(self)
		if candidate.has_method("receive_zone_hit"):
			candidate.receive_zone_hit(lerpf(10.0, 35.0, strength), "explosion", candidate.global_position, direction, self)

func set_portal_fall_credit(attacker: Node) -> void:
	if not is_instance_valid(attacker) or attacker == self:
		_clear_portal_fall_credit()
		return
	portal_fall_attacker = attacker
	portal_fall_credit_until = Time.get_ticks_msec() + 8000

func set_physics_kill_credit(attacker: Node) -> void:
	set_portal_fall_credit(attacker)

func _portal_fall_credit() -> Node:
	if Time.get_ticks_msec() > portal_fall_credit_until or not is_instance_valid(portal_fall_attacker):
		_clear_portal_fall_credit()
		return null
	return portal_fall_attacker

func _clear_portal_fall_credit() -> void:
	portal_fall_attacker = null
	portal_fall_credit_until = 0

func _apply_combatant_separation(direction: Vector3) -> Vector3:
	var separation := Vector3.ZERO
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if candidate == self or candidate is not CharacterBody3D or candidate.get("alive") != true or candidate.get("current_vehicle") != null:
			continue
		var combatant := candidate as CharacterBody3D
		var offset: Vector3 = global_position - combatant.global_position
		if absf(offset.y) > 1.25:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.001 or distance >= SEPARATION_RADIUS:
			continue
		separation += offset / distance * (1.0 - distance / SEPARATION_RADIUS)
	if separation.length_squared() <= 0.0001:
		return direction
	var separated_direction := direction + separation * SEPARATION_WEIGHT
	return separated_direction.normalized() if separated_direction.length_squared() > 0.001 else direction

func _elevation_navigation_point(goal: Vector3) -> Vector3:
	var vertical_difference := goal.y - global_position.y
	if absf(vertical_difference) <= 1.8:
		has_navigation_step = false
		return goal
	var elevation_direction := signf(vertical_difference)
	if has_navigation_step:
		var step_height_direction := signf(navigation_step.y - global_position.y)
		# Combat movement offsets the target sideways while strafing. Keep a climb
		# route stable through those small changes and only rebuild it for a truly
		# different destination or after reaching the current portal.
		var step_reverses_climb := absf(navigation_step.y - global_position.y) > 0.2 and step_height_direction != elevation_direction
		if navigation_goal.distance_to(goal) > 10.0 or global_position.distance_to(navigation_step) < 0.45 or absf(navigation_step.y - global_position.y) > 2.5 or step_reverses_climb:
			has_navigation_step = false
	if not has_navigation_step:
		var best_score := INF
		var climb_step := Vector3.ZERO
		for waypoint in waypoints:
			var elevation_gain := (waypoint.y - global_position.y) * elevation_direction
			if elevation_gain < 0.30 or elevation_gain > 2.25:
				continue
			var horizontal_distance := Vector2(waypoint.x - global_position.x, waypoint.z - global_position.z).length()
			var remaining_distance := Vector2(goal.x - waypoint.x, goal.z - waypoint.z).length()
			var preferred_gain_penalty := absf(elevation_gain - 1.2) * 2.5
			var score := horizontal_distance + remaining_distance * 0.05 + preferred_gain_penalty
			if score < best_score:
				best_score = score
				climb_step = waypoint
		if best_score < INF:
			navigation_step = climb_step
			var entry_step := _climb_entry_waypoint(climb_step, elevation_direction)
			if entry_step != climb_step and global_position.distance_to(entry_step) > 1.4:
				navigation_step = entry_step
			has_navigation_step = true
			navigation_goal = goal
	return navigation_step if has_navigation_step else goal

func _climb_entry_waypoint(climb_step: Vector3, elevation_direction: float) -> Vector3:
	# Infer the authored low/high end of a ramp from the next waypoint in its
	# vertical chain, then approach the current-floor end before climbing. This
	# prevents a bot beside or beneath a ramp from cutting straight to its midpoint.
	var continuation := Vector3.ZERO
	var continuation_score := INF
	for waypoint in waypoints:
		var gain := (waypoint.y - climb_step.y) * elevation_direction
		if gain < 0.3 or gain > 2.25:
			continue
		var horizontal_distance := Vector2(waypoint.x - climb_step.x, waypoint.z - climb_step.z).length()
		if horizontal_distance < 0.8 or horizontal_distance > 8.0:
			continue
		var score := horizontal_distance + absf(gain - 1.5)
		if score < continuation_score:
			continuation_score = score
			continuation = waypoint
	if continuation_score == INF:
		return climb_step
	var expected_entry := Vector3(
		climb_step.x - (continuation.x - climb_step.x),
		global_position.y,
		climb_step.z - (continuation.z - climb_step.z)
	)
	var entry := climb_step
	var entry_score := INF
	for waypoint in waypoints:
		if absf(waypoint.y - global_position.y) > 0.5:
			continue
		if Vector2(waypoint.x - climb_step.x, waypoint.z - climb_step.z).length() > 9.0:
			continue
		var score := Vector2(waypoint.x - expected_entry.x, waypoint.z - expected_entry.z).length()
		if score < entry_score:
			entry_score = score
			entry = waypoint
	return entry

func _update_soldier_animation(delta: float, aiming: bool) -> void:
	is_aiming = aiming
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if mode_infected and zombie_rig:
		zombie_rig.animate(planar_speed)
	elif soldier_rig:
		soldier_rig.set_equipped_weapon(weapon_type)
		soldier_rig.animate(delta, planar_speed, aiming, aim_pitch, crouching)

func _update_tbag_taunt(delta: float) -> bool:
	if mode_infected:
		crouching = false
		_set_tbagging(false)
		return false
	if is_instance_valid(taunt_target):
		if taunt_target.get("alive") == true or taunt_time <= 0.0:
			taunt_target = null
			crouching = false
			_set_tbagging(false)
			return false
		taunt_time -= delta
		var distance := global_position.distance_to(taunt_target.global_position)
		if distance > 1.25:
			crouching = false
			_set_tbagging(false)
			_move_toward_point(taunt_target.global_position, delta)
			return true
		var face_point := Vector3(taunt_target.global_position.x, global_position.y, taunt_target.global_position.z)
		if global_position.distance_squared_to(face_point) > 0.01:
			look_at(face_point, Vector3.UP)
		velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)
		move_and_slide()
		tbag_phase += delta
		crouching = fmod(tbag_phase, 0.44) < 0.22
		_set_tbagging(crouching)
		return true
	if taunt_target != null:
		taunt_target = null
	for candidate in target_candidates:
		if not is_instance_valid(candidate) or candidate == self or candidate.get("alive") == true or candidate.get("team_id") == team_id:
			continue
		if global_position.distance_squared_to(candidate.global_position) > 7.0 * 7.0:
			continue
		var corpse_id := candidate.get_instance_id()
		if considered_taunt_targets.has(corpse_id):
			continue
		considered_taunt_targets[corpse_id] = true
		if randf() <= 0.18:
			taunt_target = candidate
			taunt_time = randf_range(2.4, 5.0)
			tbag_phase = 0.0
			return true
	crouching = false
	_set_tbagging(false)
	return false

func _set_tbagging(active: bool) -> void:
	tbagging = active
	if not tbag_audio:
		return
	if active and not tbag_audio.playing:
		tbag_audio.play()
	elif not active and tbag_audio.playing:
		tbag_audio.stop()

func _update_crouch_stance(delta: float) -> void:
	if not body_collision:
		return
	var capsule := body_collision.shape as CapsuleShape3D
	capsule.height = move_toward(capsule.height, 1.12 if crouching else 1.75, delta * 4.8)
	body_collision.position.y = move_toward(body_collision.position.y, -0.315 if crouching else 0.0, delta * 2.5)
	if nameplate:
		nameplate.position.y = move_toward(nameplate.position.y, 1.02 if crouching else 1.35, delta * 3.2)
	for hitbox in hitboxes:
		var standing_y := float(hitbox.get_meta("standing_y", hitbox.position.y))
		hitbox.position.y = move_toward(hitbox.position.y, standing_y - (0.33 if crouching else 0.0), delta * 2.6)

func _has_line_of_sight() -> bool:
	using_ricochet_path = false
	var origin := global_position + Vector3(0, 1.05, 0)
	var target_point := target.global_position + Vector3(0, 0.65, 0)
	var query := PhysicsRayQueryParameters3D.create(origin, target_point)
	query.collision_mask = 1
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	if ricochet_time > 0.0 and _has_ricochet_bank(origin, target_point):
		using_ricochet_path = true
		return true
	return false

func _has_ricochet_bank(origin: Vector3, target_point: Vector3) -> bool:
	var direct := (target_point - origin).normalized()
	for yaw_degrees in [-72.0, -54.0, -36.0, 36.0, 54.0, 72.0]:
		var incoming := direct.rotated(Vector3.UP, deg_to_rad(yaw_degrees)).normalized()
		var bank_query := PhysicsRayQueryParameters3D.create(origin, origin + incoming * 24.0)
		bank_query.collision_mask = 1
		var bank_hit := get_world_3d().direct_space_state.intersect_ray(bank_query)
		if bank_hit.is_empty():
			continue
		var reflected := incoming.bounce(bank_hit.normal).normalized()
		var toward_target: Vector3 = (target_point - bank_hit.position).normalized()
		if reflected.dot(toward_target) < 0.96:
			continue
		var exit_query := PhysicsRayQueryParameters3D.create(bank_hit.position + reflected * 0.05, target_point)
		exit_query.collision_mask = 1
		if get_world_3d().direct_space_state.intersect_ray(exit_query).is_empty():
			return true
	return false

func _fire_at_player(distance: float) -> void:
	if coil_gun_owned:
		if distance <= 22.0:
			_fire_coil_gun()
		return
	var weapon_profile := ContentRegistry.resolve_bot_tactics(weapon_type)
	if distance > float(weapon_profile["range"]):
		fire_cooldown = 0.18
		return
	var rate := float(weapon_profile["interval"])
	var base_damage := float(weapon_profile["damage"])
	fire_cooldown = (rate + randf_range(0.0, 0.08)) * fire_interval_multiplier
	muzzle_light.light_color = Color("#ffbb55")
	muzzle_light.light_energy = 3.0
	if soldier_rig:
		soldier_rig.play_shot()
	gun_audio.stream = _weapon_shot_sound(weapon_type)
	gun_audio.pitch_scale = float(weapon_profile["pitch"])
	gun_audio.play()
	var scene := get_tree().current_scene
	if scene and scene.has_method("bot_fired_weapon"):
		scene.bot_fired_weapon(self, weapon_type)
	base_damage *= damage_multiplier
	if using_ricochet_path:
		base_damage *= 0.75
	var range_falloff := 0.018 if weapon_type == "shotgun" else (0.007 if weapon_type == "sniper" else (0.014 if weapon_type == "smg" else 0.011))
	var base_accuracy := clampf((0.66 - distance * range_falloff) * float(weapon_profile["accuracy"]), 0.16, 0.82)
	var accuracy := clampf(base_accuracy * accuracy_multiplier, 0.12, 0.82)
	var pellet_count := int(weapon_profile["pellets"])
	for _pellet in pellet_count:
		if randf() > accuracy:
			continue
		var pellet_target := target
		if not is_instance_valid(pellet_target) or pellet_target.get("alive") != true:
			break
		var zone_roll := randf()
		var limb_zones := ["arm_l", "arm_r", "leg_l", "leg_r"]
		var pellet_headshot_chance := headshot_chance * (0.35 if weapon_type == "shotgun" else 1.0)
		var zone: String = "head" if zone_roll < pellet_headshot_chance else (limb_zones.pick_random() if zone_roll < 0.33 else "torso")
		var multiplier := 2.0 if zone == "head" else (0.75 if zone != "torso" else 1.0)
		var hit_position := pellet_target.global_position + _limb_offset(zone)
		var hit_normal := (global_position - pellet_target.global_position).normalized()
		pellet_target.set_meta("gun_streak_kill", true)
		if pellet_target.has_method("receive_zone_hit"):
			pellet_target.receive_zone_hit(base_damage * multiplier, zone, hit_position, hit_normal, self)
		else:
			pellet_target.apply_damage(base_damage * multiplier, global_position, self)
		if is_instance_valid(pellet_target):
			pellet_target.remove_meta("gun_streak_kill")

func _weapon_shot_sound(weapon_id: String) -> AudioStream:
	if NetworkSession.is_dedicated_server:
		return null
	match weapon_id:
		"shotgun": return load(SHOTGUN_SHOT_SOUND_PATH)
		"sniper": return load(SNIPER_SHOT_SOUND_PATH)
	return load(RIFLE_SHOT_SOUND_PATH)

func _fire_coil_gun() -> void:
	fire_cooldown = (1.0 / 0.34) * fire_interval_multiplier
	muzzle_light.light_color = Color("#71dcff")
	muzzle_light.light_energy = 8.0
	if soldier_rig:
		soldier_rig.play_shot()
	var candidates := get_tree().get_nodes_in_group("combatants")
	candidates.append_array(get_tree().get_nodes_in_group("city_civilians"))
	candidates.append_array(get_tree().get_nodes_in_group("attack_dogs"))
	var nearby: Array[Dictionary] = []
	for candidate in candidates:
		if candidate == self or candidate.get("alive") != true:
			continue
		if not candidate.is_in_group("city_civilians") and candidate.get("team_id") == team_id:
			continue
		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		if distance_squared <= 22.0 * 22.0:
			nearby.append({"target": candidate, "distance": distance_squared})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	var target_positions: Array[Vector3] = []
	for index in mini(nearby.size(), 3):
		var coil_target: Node = nearby[index]["target"]
		var hit_position: Vector3 = coil_target.global_position + Vector3.UP * 0.45
		target_positions.append(hit_position)
		coil_target.set_meta("gun_streak_kill", true)
		if coil_target.has_method("receive_zone_hit"):
			coil_target.receive_zone_hit(10000.0, "torso", hit_position, Vector3.UP, self)
		elif coil_target.has_method("apply_damage"):
			coil_target.apply_damage(10000.0, global_position, self)
		if is_instance_valid(coil_target):
			coil_target.remove_meta("gun_streak_kill")
	if target_positions.is_empty():
		return
	_spawn_coil_effect(target_positions)
	var scene := get_tree().current_scene
	if scene and scene.has_method("bot_fired_coil_gun"):
		scene.bot_fired_coil_gun(self, target_positions)

func _spawn_coil_effect(target_positions: Array[Vector3]) -> void:
	if NetworkSession.is_dedicated_server:
		return
	var coil_effect_script = load(COIL_LIGHTNING_EFFECT_PATH)
	var effect = coil_effect_script.new()
	get_tree().current_scene.add_child(effect)
	effect.activate(muzzle_light.global_position, target_positions)

func _update_jetpack_tactics(delta: float) -> void:
	if not jetpack_owned:
		return
	jetpack_boost_time = maxf(jetpack_boost_time - delta, 0.0)
	jetpack_tactical_cooldown = maxf(jetpack_tactical_cooldown - delta, 0.0)
	if jetpack_boost_time <= 0.0 and jetpack_tactical_cooldown <= 0.0 and jetpack_fuel >= 0.6 and _is_valid_enemy(target):
		var distance := global_position.distance_to(target.global_position)
		var needs_height := target.global_position.y > global_position.y + 1.1
		var combat_dodge := distance >= 3.0 and distance <= 13.0 and _has_line_of_sight()
		if needs_height or combat_dodge:
			jetpack_boost_time = 0.85 if needs_height else 0.55
			jetpack_tactical_cooldown = randf_range(2.4, 4.0)
	if jetpack_boost_time > 0.0 and jetpack_fuel > 0.0:
		if jetpack_thruster_audio:
			jetpack_thruster_audio.set_thrusting(true)
		velocity.y = move_toward(velocity.y, 8.2, delta * 18.0)
		jetpack_fuel = maxf(jetpack_fuel - delta, 0.0)
	elif is_on_floor():
		jetpack_fuel = minf(jetpack_fuel + delta * 0.8, JETPACK_MAX_FUEL)

func apply_damage(amount: float, source_position: Vector3, attacker: Node) -> bool:
	return receive_zone_hit(amount, "torso", source_position, Vector3.UP, attacker)

func apply_explosion_damage(amount: float, source_position: Vector3, attacker: Node, intensity := 1.0) -> bool:
	pending_explosion_intensity = clampf(intensity, 0.0, 1.0)
	var killed_by_blast := receive_zone_hit(amount, "explosion", global_position, (global_position - source_position).normalized(), attacker)
	pending_explosion_intensity = 0.0
	return killed_by_blast

func receive_zone_hit(amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3, attacker: Node) -> bool:
	if not alive or (invulnerable_time > 0.0 and zone != "fall"):
		return false
	last_hit_zone = zone
	last_dismembered_limbs.clear()
	last_hit_position = hit_position
	last_hit_normal = hit_normal
	if current_vehicle:
		var armored_vehicle := current_vehicle
		armored_vehicle.apply_occupant_damage(amount, attacker)
		amount *= 0.4
	health -= amount
	time_since_damage = 0.0
	if health <= 0.0:
		if "last_stand" in active_perks and not last_stand_used and amount < 9000.0:
			last_stand_used = true
			health = maxf(25.0, max_health * 0.2)
			invulnerable_time = 0.8
			weapon_type = "pistol"
			return false
		if zone == "head" or _is_limb_zone(zone):
			_trigger_lethal_dismemberment([zone], hit_position, hit_normal)
		elif zone == "explosion":
			_trigger_lethal_dismemberment(_explosion_limbs(pending_explosion_intensity), hit_position, hit_normal)
		_die(attacker)
		return true
	return false

func _trigger_lethal_dismemberment(limbs: Array[String], hit_position: Vector3, hit_normal: Vector3) -> void:
	last_dismembered_limbs.assign(limbs)
	if soldier_rig:
		soldier_rig.remove_limbs(limbs)
	_spawn_dismemberment_effects(limbs, hit_position, hit_normal)

func _spawn_dismemberment_effects(limbs: Array[String], hit_position: Vector3, hit_normal: Vector3) -> void:
	if NetworkSession.is_dedicated_server:
		return
	for index in limbs.size():
		var limb := limbs[index]
		var effect_position := hit_position if limbs.size() == 1 else global_position + _limb_offset(limb)
		if limb == "head":
			var headshot_effect_script = load(HEADSHOT_EFFECT_PATH)
			var head_effect = headshot_effect_script.new()
			get_tree().current_scene.add_child(head_effect)
			head_effect.activate(effect_position, hit_normal)
		else:
			var limb_effect_script = load(LIMB_DISMEMBERMENT_EFFECT_PATH)
			var effect = limb_effect_script.new()
			get_tree().current_scene.add_child(effect)
			effect.activate(effect_position, hit_normal, limb, index == 0)

func _explosion_limbs(intensity: float) -> Array[String]:
	var pool: Array[String] = ["arm_l", "arm_r", "leg_l", "leg_r"]
	pool.shuffle()
	var count := clampi(int(round(lerpf(2.0, 4.0, intensity))), 2, 4)
	var result: Array[String] = pool.slice(0, count)
	if intensity >= 0.85:
		result.append("head")
	return result

func _is_limb_zone(zone: String) -> bool:
	return zone in ["arm_l", "arm_r", "leg_l", "leg_r"]

func _limb_offset(limb: String) -> Vector3:
	match limb:
		"head": return Vector3(0, 0.69, 0)
		"arm_l": return Vector3(-0.38, 0.34, 0)
		"arm_r": return Vector3(0.38, 0.34, 0)
		"leg_l": return Vector3(-0.15, -0.40, 0)
		"leg_r": return Vector3(0.15, -0.40, 0)
	return Vector3(0, 0.12, 0)

func _die(attacker: Node) -> void:
	_cancel_bot_force_audio()
	set_meta("death_powerup_drops", carried_powerup_drop_records())
	remove_meta("powerup_handoff_counts")
	if current_vehicle:
		current_vehicle.leave_seat(self, true)
	if mode_infected and zombie_rig:
		zombie_rig.play_death()
	else:
		_play_death_voice()
	alive = false
	crouching = false
	_set_tbagging(false)
	taunt_target = null
	velocity = Vector3.ZERO
	if nameplate:
		nameplate.visible = false
	body_collision.set_deferred("disabled", true)
	for hitbox in hitboxes:
		hitbox.collision_layer = 0
	var tween := create_tween()
	tween.tween_property(body_root, "rotation:z", deg_to_rad(88), 0.3)
	killed.emit(self, attacker)

func carried_powerup_ids() -> Array[String]:
	var result: Array[String] = []
	if jetpack_owned:
		result.append("jetpack")
	if coil_gun_owned:
		result.append("coil_gun")
	if suicide_vest_owned and not suicide_vest_triggering:
		result.append("suicide_vest")
	if ricochet_time > 0.0:
		result.append("ricochet")
	if physics_utility_id == "force":
		result.append("force")
	if grenade_type in ["gravity_bomb", "sticky_bomb"]:
		result.append(grenade_type)
	return result

func carried_powerup_drop_records() -> Array[Dictionary]:
	var counts: Dictionary = get_meta("powerup_handoff_counts", {})
	var result: Array[Dictionary] = []
	for kind in carried_powerup_ids():
		result.append({"kind": kind, "handoffs": int(counts.get(kind, 0))})
	return result

func _play_death_voice() -> void:
	if not death_voice_audio or NetworkSession.is_dedicated_server:
		return
	var death_voice_pool_script = load(DEATH_VOICE_POOL_PATH)
	var voice: AudioStream = death_voice_pool_script.get_next_voice()
	if voice:
		death_voice_audio.stream = voice
		death_voice_audio.play()

func respawn_at(spawn: Vector3) -> void:
	if current_vehicle:
		current_vehicle.leave_seat(self, true)
	global_position = spawn
	peak_fall_speed = 0.0
	_clear_portal_fall_credit()
	last_climb_floor_position = spawn
	health = max_health
	last_dismembered_limbs.clear()
	alive = true
	blocked_route_active = false
	blocked_route_time = 0.0
	blocked_route_target_id = 0
	if nameplate:
		nameplate.visible = true
	# Firing-range dummies should accept precision shots as soon as they reappear.
	# Regular match bots retain spawn protection.
	invulnerable_time = 0.0 if passive_training_dummy else 1.5
	time_since_damage = 999.0
	body_root.rotation = Vector3.ZERO
	body_root.position.y = MODEL_FLOOR_OFFSET
	crouching = false
	_set_tbagging(false)
	taunt_target = null
	taunt_time = 0.0
	if soldier_rig:
		soldier_rig.reset_pose()
	if zombie_rig:
		zombie_rig.reset_pose()
	body_collision.disabled = false
	for hitbox in hitboxes:
		hitbox.collision_layer = 8
	_reset_pickup_abilities()
	_choose_new_loadout_weapon()
	has_navigation_step = false
	_cancel_portal_plan()
	_choose_destination()

func set_objective(point: Vector3, active: bool) -> void:
	objective_position = point
	objective_active = active
	if active:
		destination = point
		has_navigation_step = false

func set_mode_juggernaut(active: bool) -> void:
	if mode_juggernaut == active:
		return
	mode_juggernaut = active
	max_health = 350.0 if active else 100.0
	health = max_health
	_refresh_mode_move_speed()
	if body_root:
		body_root.scale = Vector3.ONE * (1.28 if active else 1.0)

func set_mode_infected(active: bool) -> void:
	mode_infected = active
	weapon_type = "infected" if active else base_weapon_type
	vehicle_goal = null
	if active:
		_cancel_portal_plan()
		if is_instance_valid(portal_manager):
			portal_manager.clear_portals()
	_refresh_mode_move_speed()
	if active:
		_ensure_zombie_rig()
	if soldier_rig:
		soldier_rig.visible = not active
	if zombie_rig:
		zombie_rig.visible = active
		zombie_rig.reset_pose()
	if is_instance_valid(infection_marker):
		infection_marker.queue_free()
	infection_marker = null

func _ensure_zombie_rig() -> void:
	if zombie_rig or NetworkSession.is_dedicated_server:
		return
	var zombie_rig_script = load(ZOMBIE_RIG_PATH)
	zombie_rig = zombie_rig_script.new()
	zombie_rig.visible = false
	body_root.add_child(zombie_rig)

func _refresh_mode_move_speed() -> void:
	var mode_multiplier := 1.75 if mode_infected else (0.82 if mode_juggernaut else 1.0)
	var perk_multiplier := 1.18 if "featherfoot" in active_perks else 1.0
	move_speed = base_mode_move_speed * mode_multiplier * perk_multiplier

func _choose_destination() -> void:
	if not waypoints.is_empty():
		destination = waypoints.pick_random()

func _is_valid_enemy(candidate) -> bool:
	# Keep this argument untyped: a queued-for-deletion CharacterBody3D can remain in
	# a typed target array for one frame, and Godot rejects it before a typed method
	# can perform an instance-validity check.
	if not is_instance_valid(candidate) or candidate == self or not candidate.get("alive") or candidate.get("team_id") == team_id:
		return false
	return not current_vehicle or candidate.get("current_vehicle") != current_vehicle

func _select_nearest_target() -> void:
	target_refresh_timer = randf_range(0.25, 0.5)
	for index in range(target_candidates.size() - 1, -1, -1):
		if not is_instance_valid(target_candidates[index]):
			target_candidates.remove_at(index)
	var nearest: CharacterBody3D = null
	var nearest_distance := INF
	var nearest_visible: CharacterBody3D = null
	var nearest_visible_distance := 30.0 * 30.0
	for candidate in target_candidates:
		if not _is_valid_enemy(candidate):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
		if distance < nearest_visible_distance and _candidate_is_visible(candidate):
			nearest_visible_distance = distance
			nearest_visible = candidate
	target = nearest_visible if nearest_visible else nearest
	if target:
		reaction_timer = maxf(reaction_timer, reaction_acquire_delay)

func _candidate_is_visible(candidate: CharacterBody3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.05, candidate.global_position + Vector3.UP * 0.65)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _nearest_available_vehicle(max_distance: float) -> Node:
	var nearest: Node
	var nearest_distance := max_distance * max_distance
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if not vehicle.alive or vehicle.get_open_seat_for(self).is_empty():
			continue
		var distance := global_position.distance_squared_to(vehicle.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = vehicle
	return nearest

func _nearest_desired_pickup(max_distance: float) -> Area3D:
	if mode_infected:
		return null
	var nearest: Area3D
	var nearest_distance := max_distance * max_distance
	for candidate in get_tree().get_nodes_in_group("collectible_pickups"):
		if candidate is not Area3D or not _wants_pickup(candidate):
			continue
		var blocked_until := int(unreachable_pickups.get(candidate.get_instance_id(), 0))
		if blocked_until > Time.get_ticks_msec() or not _pickup_claim_available(candidate):
			continue
		if blocked_until > 0:
			unreachable_pickups.erase(candidate.get_instance_id())
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest

func _pickup_claim_available(candidate: Area3D) -> bool:
	# Lowest instance ID wins a contested claim, which converges deterministically
	# even if several bots discover a newly spawned pickup during the same frame.
	for combatant in get_tree().get_nodes_in_group("combatants"):
		if combatant == self or combatant.get("alive") != true or combatant.get("pickup_goal") != candidate:
			continue
		if combatant.get_instance_id() < get_instance_id():
			return false
	return true

func _wants_pickup(pickup: Node) -> bool:
	if not is_instance_valid(pickup) or not alive or mode_infected:
		return false
	match str(pickup.get("pickup_kind")):
		"jetpack":
			return not jetpack_owned
		"coil_gun":
			return not coil_gun_owned
		"suicide_vest":
			return not suicide_vest_owned and not suicide_vest_triggering
		"ricochet":
			return ricochet_time <= 0.0
		"force":
			return str(pickup.get("pickup_kind")) != physics_utility_id
		"gravity_bomb", "sticky_bomb":
			return str(pickup.get("pickup_kind")) != grenade_type or grenades_remaining < (4 if "demolitionist" in active_perks else 3)
		"perk":
			return str(pickup.get("perk_id")) not in active_perks
		"ammo_drop":
			var grenade_capacity := 4 if "demolitionist" in active_perks else 3
			return grenades_remaining < grenade_capacity or axes_remaining < 1
	return false

func acquire_jetpack() -> bool:
	if jetpack_owned or not alive:
		return false
	jetpack_owned = true
	jetpack_fuel = JETPACK_MAX_FUEL
	pickup_goal = null
	return true

func acquire_coil_gun() -> bool:
	if coil_gun_owned or not alive:
		return false
	coil_gun_owned = true
	weapon_type = "coil_gun"
	pickup_goal = null
	return true

func acquire_suicide_vest() -> bool:
	if suicide_vest_owned or suicide_vest_triggering or not alive:
		return false
	suicide_vest_owned = true
	pickup_goal = null
	return true

func acquire_ricochet() -> bool:
	if not alive or mode_infected:
		return false
	ricochet_time = 30.0
	pickup_goal = null
	return true

func acquire_grenade_powerup(kind: String) -> bool:
	if kind not in ["gravity_bomb", "sticky_bomb"] or not alive or mode_infected:
		return false
	var capacity := 4 if "demolitionist" in active_perks else 3
	if grenade_type == kind and grenades_remaining >= capacity:
		return false
	grenade_type = kind
	grenades_remaining = capacity
	pickup_goal = null
	return true

func acquire_physics_utility(id: String) -> bool:
	if id != "force" or not alive or mode_infected:
		return false
	physics_utility_id = id
	physics_utility_cooldown = randf_range(1.0, 2.5)
	pickup_goal = null
	return true

func apply_perk(perk_id: String) -> bool:
	if perk_id in active_perks or not alive:
		return false
	active_perks.append(perk_id)
	match perk_id:
		"sleight_of_hand":
			fire_interval_multiplier *= 0.72
		"juggernog":
			max_health += 100.0
			health += 100.0
		"featherfoot":
			_refresh_mode_move_speed()
		"stopping_power":
			damage_multiplier *= 1.25
		"scavenger", "quick_fix":
			pass
		"last_stand":
			last_stand_used = false
		"demolitionist":
			explosive_damage_multiplier = 1.3
			grenades_remaining = maxi(grenades_remaining, 4)
		"shockwave_ground_pound":
			ground_pound_cooldown = 0.0
	pickup_goal = null
	return true

func on_confirmed_kill() -> void:
	if "quick_fix" in active_perks:
		health = minf(health + max_health * 0.45, max_health)
		time_since_damage = 999.0
	if "scavenger" in active_perks:
		grenades_remaining = mini(grenades_remaining + 1, 4 if "demolitionist" in active_perks else 3)

func collect_ammo_drop() -> bool:
	if not alive:
		return false
	grenades_remaining = 4 if "demolitionist" in active_perks else 3
	axes_remaining = 1
	pickup_goal = null
	return true

func set_sticky_bomb_panic(fuse_time: float) -> void:
	sticky_bomb_panic_time = maxf(sticky_bomb_panic_time, fuse_time)
	if current_vehicle:
		current_vehicle.leave_seat(self, true)

func _update_sticky_bomb_panic(delta: float) -> bool:
	if sticky_bomb_panic_time <= 0.0 or not alive:
		return false
	sticky_bomb_panic_time = maxf(sticky_bomb_panic_time - delta, 0.0)
	var nearest: Node3D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if candidate == self or candidate is not Node3D or candidate.get("alive") != true:
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	if not nearest:
		return true
	var direction := nearest.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		look_at(global_position + direction, Vector3.UP)
	var panic_speed := move_speed * SPRINT_SPEED_MULTIPLIER * 1.2
	velocity.x = move_toward(velocity.x, direction.x * panic_speed, delta * 18.0)
	velocity.z = move_toward(velocity.z, direction.z * panic_speed, delta * 18.0)
	_try_jump_over_obstacle(direction, true)
	if not is_on_floor():
		velocity += get_gravity() * delta
	_move_and_slide_with_fall_damage()
	return true

func trigger_suicide_vest() -> void:
	if not suicide_vest_owned or suicide_vest_triggering or not alive:
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("bot_trigger_suicide_vest"):
		scene.bot_trigger_suicide_vest(self)
		return
	suicide_vest_owned = false
	suicide_vest_triggering = true
	var charge := SuicideVestCharge.new()
	get_tree().current_scene.add_child(charge)
	charge.detonated.connect(_remove_suicide_vest)
	charge.arm(self, true)

func _remove_suicide_vest() -> void:
	suicide_vest_owned = false
	suicide_vest_triggering = false

func _reset_pickup_abilities() -> void:
	active_perks.clear()
	last_stand_used = false
	explosive_damage_multiplier = 1.0
	jetpack_owned = false
	jetpack_fuel = 0.0
	jetpack_boost_time = 0.0
	jetpack_tactical_cooldown = 0.0
	if jetpack_thruster_audio:
		jetpack_thruster_audio.set_thrusting(false)
	coil_gun_owned = false
	muzzle_light.light_color = Color("#ffbb55")
	suicide_vest_owned = false
	suicide_vest_triggering = false
	physics_utility_id = ""
	ricochet_time = 0.0
	physics_utility_cooldown = 0.0
	_cancel_bot_force_audio()
	force_held_target = null
	force_hold_time = 0.0
	ground_pound_cooldown = 0.0
	grenades_remaining = 3
	grenade_type = "normal"
	sticky_bomb_panic_time = 0.0
	axes_remaining = 1
	throwable_cooldown = randf_range(2.0, 4.0)
	knife_engage_time = 0.0
	weapon_type = "infected" if mode_infected else base_weapon_type
	_apply_difficulty_profile()
	max_health = 350.0 if mode_juggernaut else 100.0
	_refresh_mode_move_speed()
	health = max_health
	pickup_goal = null

func _choose_new_loadout_weapon() -> void:
	if mode_infected:
		return
	var choices: Array = ContentRegistry.get_bot_loadout_weapon_ids().filter(func(candidate): return candidate != base_weapon_type)
	base_weapon_type = str(choices.pick_random()) if not choices.is_empty() else "ak47"
	weapon_type = base_weapon_type

func enter_vehicle(vehicle: Node, seat: String) -> void:
	current_vehicle = vehicle
	vehicle_seat = seat
	vehicle_goal = null
	velocity = Vector3.ZERO
	collision_layer = 0
	body_collision.set_deferred("disabled", true)
	body_root.visible = false
	if nameplate:
		nameplate.visible = false
	for hitbox in hitboxes:
		hitbox.collision_layer = 0

func leave_vehicle(exit_position: Vector3, _forced := false) -> void:
	current_vehicle = null
	vehicle_seat = ""
	global_position = exit_position
	velocity = Vector3.ZERO
	peak_fall_speed = 0.0
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	body_collision.set_deferred("disabled", false)
	body_root.visible = true
	if nameplate:
		nameplate.visible = alive
	if alive:
		for hitbox in hitboxes:
			hitbox.collision_layer = 8

func _update_vehicle_combat(delta: float) -> void:
	if not current_vehicle or not current_vehicle.alive:
		return
	if vehicle_seat == "driver":
		if target and target.alive:
			current_vehicle.set_ai_drive_target(target.global_position)
		else:
			current_vehicle.set_ai_drive_target(destination)
		return
	reaction_timer -= delta
	if target and target.alive:
		var distance := global_position.distance_to(target.global_position)
		if distance < 30.0 and reaction_timer <= 0.0 and fire_cooldown <= 0.0 and _has_line_of_sight():
			_fire_at_player(distance)

func apply_vehicle_impact(amount: float, push_velocity: Vector3, attacker: Node) -> void:
	velocity.x = push_velocity.x
	velocity.z = push_velocity.z
	if is_on_floor():
		velocity.y = 0.0
	if amount > 0.0:
		apply_damage(amount, global_position, attacker)

func receive_vehicle_protected_damage(amount: float, _source_position: Vector3, attacker: Node) -> void:
	if not alive or invulnerable_time > 0.0:
		return
	health -= amount * 0.4
	time_since_damage = 0.0
	if health <= 0.0:
		_die(attacker)
