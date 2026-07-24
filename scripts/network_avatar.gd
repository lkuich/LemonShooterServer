extends CharacterBody3D

signal died(victim: Node, attacker_id: int)

const CombatHitbox = preload("res://scripts/combat_hitbox.gd")
const SOLDIER_RIG_PATH := "res://scripts/soldier_rig.gd"
const ZOMBIE_RIG_PATH := "res://scripts/zombie_rig.gd"
const HEADSHOT_EFFECT_PATH := "res://scripts/headshot_effect.gd"
const LIMB_DISMEMBERMENT_EFFECT_PATH := "res://scripts/limb_dismemberment_effect.gd"
const DEATH_VOICE_POOL_PATH := "res://scripts/death_voice_pool.gd"
const JETPACK_THRUSTER_AUDIO_PATH := "res://scripts/jetpack_thruster_audio.gd"
const COIL_LIGHTNING_EFFECT_PATH := "res://scripts/coil_lightning_effect.gd"
const RIFLE_SHOT_SOUND_PATH := "res://sounds/gun1/gunshot_trimmed.ogg"
const SHOTGUN_SHOT_SOUND_PATH := "res://sounds/gun1/shotgun_shot.mp3"
const SNIPER_SHOT_SOUND_PATH := "res://content/core/weapons/sniper/audio/fire.ogg"

var entity_id := 0
var owner_peer_id := 0
var display_name := "PLAYER"
var model_id := "soldier"
var team_id := 0
var is_human_player := true
var max_health := 100.0
var health := 100.0
var alive := true
var invulnerable_time := 0.0
var current_vehicle: Node
var active_perks: Array[String] = []
var last_stand_used := false
var explosive_damage_multiplier := 1.0
var jetpack_owned := false
var coil_gun_owned := false
var suicide_vest_owned := false
var suicide_vest_triggering := false
var physics_utility_id := ""
var ricochet_time := 0.0
var mode_juggernaut := false
var mode_infected := false
var crouching := false
var tbagging := false
var aiming := false
var equipped_weapon_id := "ak47"
var mode_marker: Node3D
var grenades_remaining := 3
var grenade_type := "normal"
var axes_remaining := 1

var body_root: Node3D
var soldier_rig: Node3D
var zombie_rig: Node3D
var body_collision: CollisionShape3D
var hitboxes: Array[Area3D] = []
var nameplate: Label3D
var gun_audio: AudioStreamPlayer3D
var muzzle_light: OmniLight3D
var target_position := Vector3.ZERO
var target_rotation_y := 0.0
var target_aim_pitch := 0.0
var last_snapshot_velocity := Vector3.ZERO
var death_tween: Tween
var death_voice_audio: AudioStreamPlayer3D
var jetpack_thruster_audio: AudioStreamPlayer3D
var tbag_audio: AudioStreamPlayer3D
var time_since_damage := 999.0
var regen_delay := 5.0
var regen_rate := 25.0
var last_hit_zone := "torso"
var last_hit_position := Vector3.ZERO
var last_hit_normal := Vector3.UP
var last_dismembered_limbs: Array[String] = []
var pending_explosion_intensity := 0.0

func setup(id: int, peer_id: int, player_name: String, assigned_team: int, assigned_model_id := "soldier") -> void:
	entity_id = id
	owner_peer_id = peer_id
	display_name = player_name
	model_id = assigned_model_id if ContentRegistry.has_model(assigned_model_id) else "soldier"
	team_id = assigned_team
	name = "NetPlayer_%d" % id

func _ready() -> void:
	add_to_group("combatants")
	collision_layer = 2
	collision_mask = 1 | 4
	if NetworkSession.is_dedicated_server:
		_build_server_avatar()
	else:
		_build_avatar()
	target_position = global_position
	target_rotation_y = rotation.y

func _physics_process(delta: float) -> void:
	invulnerable_time = maxf(invulnerable_time - delta, 0.0)
	ricochet_time = maxf(ricochet_time - delta, 0.0)
	if not alive:
		if jetpack_thruster_audio:
			jetpack_thruster_audio.set_thrusting(false)
		return
	if multiplayer.is_server():
		time_since_damage += delta
		if time_since_damage >= regen_delay and health < max_health:
			health = minf(health + regen_rate * delta, max_health)
	global_position = global_position.lerp(target_position, minf(delta * 14.0, 1.0))
	rotation.y = lerp_angle(rotation.y, target_rotation_y, minf(delta * 16.0, 1.0))
	velocity = last_snapshot_velocity
	if jetpack_thruster_audio:
		jetpack_thruster_audio.set_thrusting(jetpack_owned and velocity.y > 1.0 and not current_vehicle)
	var speed := Vector2(last_snapshot_velocity.x, last_snapshot_velocity.z).length()
	if mode_infected and zombie_rig:
		zombie_rig.animate(speed)
	elif soldier_rig:
		soldier_rig.set_equipped_weapon(equipped_weapon_id)
		soldier_rig.animate(delta, speed, aiming, target_aim_pitch, crouching)
	_update_crouch_stance(delta)
	if muzzle_light:
		muzzle_light.light_energy = move_toward(muzzle_light.light_energy, 0.0, delta * 45.0)

func apply_snapshot(state: Dictionary) -> void:
	target_position = state.get("position", global_position)
	target_rotation_y = float(state.get("yaw", rotation.y))
	target_aim_pitch = float(state.get("pitch", 0.0))
	crouching = state.get("crouching", false) == true
	aiming = state.get("aiming", false) == true
	equipped_weapon_id = str(state.get("weapon", equipped_weapon_id))
	last_snapshot_velocity = state.get("velocity", Vector3.ZERO)
	var state_alive: bool = state.get("alive", alive) == true
	var state_health := float(state.get("health", health))
	if state_alive != alive:
		if state_alive:
			global_position = state.get("position", global_position)
			target_position = global_position
		_set_alive_visual(state_alive)
	health = state_health
	alive = state_alive
	_set_tbagging(state_alive and state.get("tbagging", false) == true)
	team_id = int(state.get("team", team_id))
	# Client movement packets intentionally omit authority-owned inventory and
	# mode fields. Only replace them when applying a full host snapshot.
	if state.has("perks"):
		active_perks.clear()
		var replicated_perks: Array = state["perks"]
		for perk_id in replicated_perks:
			active_perks.append(str(perk_id))
	set_mode_juggernaut(state.get("mode_juggernaut", mode_juggernaut) == true)
	set_mode_infected(state.get("mode_infected", mode_infected) == true)
	jetpack_owned = state.get("jetpack", jetpack_owned) == true
	coil_gun_owned = state.get("coil_gun", coil_gun_owned) == true
	suicide_vest_owned = state.get("suicide_vest", suicide_vest_owned) == true
	suicide_vest_triggering = state.get("suicide_vest_triggering", suicide_vest_triggering) == true
	physics_utility_id = str(state.get("physics_utility", physics_utility_id))
	ricochet_time = float(state.get("ricochet_time", ricochet_time))
	grenades_remaining = int(state.get("grenades", grenades_remaining))
	grenade_type = str(state.get("grenade_type", grenade_type))
	axes_remaining = int(state.get("axes", axes_remaining))

func _update_crouch_stance(delta: float) -> void:
	if not body_collision:
		return
	var capsule := body_collision.shape as CapsuleShape3D
	capsule.height = move_toward(capsule.height, 1.15 if crouching else 1.8, delta * 4.5)
	body_collision.position.y = move_toward(body_collision.position.y, -0.325 if crouching else 0.0, delta * 2.3)
	if nameplate:
		nameplate.position.y = move_toward(nameplate.position.y, 1.02 if crouching else 1.35, delta * 3.0)
	for hitbox in hitboxes:
		var standing_y := float(hitbox.get_meta("standing_y", hitbox.position.y))
		hitbox.position.y = move_toward(hitbox.position.y, standing_y - (0.34 if crouching else 0.0), delta * 2.4)

func apply_damage(amount: float, source_position: Vector3, attacker: Node) -> bool:
	return receive_zone_hit(amount, "torso", source_position, Vector3.UP, attacker)

func apply_explosion_damage(amount: float, source_position: Vector3, attacker: Node, intensity := 1.0) -> bool:
	pending_explosion_intensity = clampf(intensity, 0.0, 1.0)
	var killed_by_blast := receive_zone_hit(amount, "explosion", global_position, (global_position - source_position).normalized(), attacker)
	pending_explosion_intensity = 0.0
	return killed_by_blast

func receive_zone_hit(amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3, attacker: Node) -> bool:
	var scene := get_tree().current_scene
	var attacker_id := _attacker_entity_id(attacker)
	if not multiplayer.is_server():
		if scene and scene.has_method("request_network_hit"):
			scene.request_network_hit(attacker_id, entity_id, amount, zone, hit_position, hit_normal)
		return false
	if not alive or invulnerable_time > 0.0:
		return false
	last_hit_zone = zone
	last_dismembered_limbs.clear()
	last_hit_position = hit_position
	last_hit_normal = hit_normal
	health = maxf(health - amount, 0.0)
	time_since_damage = 0.0
	if health <= 0.0:
		if "last_stand" in active_perks and not last_stand_used and amount < 9000.0:
			last_stand_used = true
			health = maxf(25.0, max_health * 0.2)
			invulnerable_time = 0.8
			return false
		if zone == "head" or _is_limb_zone(zone):
			_trigger_lethal_dismemberment([zone], hit_position, hit_normal)
		elif zone == "explosion":
			_trigger_lethal_dismemberment(_explosion_limbs(pending_explosion_intensity), hit_position, hit_normal)
		if current_vehicle:
			current_vehicle.leave_seat(self, true)
		alive = false
		suicide_vest_owned = false
		suicide_vest_triggering = false
		_set_alive_visual(false)
		died.emit(self, attacker_id)
		return true
	return false

func apply_vehicle_impact(amount: float, push_velocity: Vector3, attacker: Node) -> void:
	last_snapshot_velocity = push_velocity
	target_position += Vector3(push_velocity.x, 0.0, push_velocity.z) * 0.22
	if multiplayer.is_server() and owner_peer_id > 0:
		var scene := get_tree().current_scene
		if scene and scene.has_method("send_city_vehicle_impact"):
			scene.send_city_vehicle_impact(entity_id, push_velocity)
	if amount > 0.0:
		apply_damage(amount, global_position, attacker)

func respawn_at(spawn: Vector3) -> void:
	global_position = spawn
	target_position = spawn
	velocity = Vector3.ZERO
	last_snapshot_velocity = Vector3.ZERO
	max_health = 350.0 if mode_juggernaut else 100.0
	health = max_health
	alive = true
	invulnerable_time = 1.5
	time_since_damage = 999.0
	active_perks.clear()
	last_stand_used = false
	explosive_damage_multiplier = 1.0
	jetpack_owned = false
	coil_gun_owned = false
	suicide_vest_owned = false
	suicide_vest_triggering = false
	physics_utility_id = ""
	ricochet_time = 0.0
	grenades_remaining = 3
	grenade_type = "normal"
	axes_remaining = 1
	_set_alive_visual(true)

func apply_perk(perk_id: String) -> bool:
	if perk_id in active_perks or not alive or mode_infected:
		return false
	active_perks.append(perk_id)
	if perk_id == "juggernog":
		max_health = 150.0
		health = max_health
	elif perk_id == "last_stand":
		last_stand_used = false
	elif perk_id == "demolitionist":
		explosive_damage_multiplier = 1.3
		grenades_remaining = maxi(grenades_remaining, 4)
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
	return true

func acquire_jetpack() -> bool:
	if jetpack_owned or not alive or mode_infected:
		return false
	jetpack_owned = true
	return true

func acquire_coil_gun() -> bool:
	if coil_gun_owned or not alive or mode_infected:
		return false
	coil_gun_owned = true
	return true

func acquire_suicide_vest() -> bool:
	if suicide_vest_owned or suicide_vest_triggering or not alive or mode_infected:
		return false
	suicide_vest_owned = true
	return true

func acquire_ricochet() -> bool:
	if not alive or mode_infected:
		return false
	ricochet_time = 30.0
	return true

func acquire_grenade_powerup(kind: String) -> bool:
	if kind not in ["gravity_bomb", "sticky_bomb"] or not alive or mode_infected:
		return false
	var capacity := 4 if "demolitionist" in active_perks else 3
	if grenade_type == kind and grenades_remaining >= capacity:
		return false
	grenade_type = kind
	grenades_remaining = capacity
	return true

func acquire_physics_utility(id: String) -> bool:
	if id != "force" or not alive or mode_infected:
		return false
	physics_utility_id = id
	return true

func set_physics_kill_credit(attacker: Node) -> void:
	set_meta("physics_kill_attacker", attacker)
	set_meta("physics_kill_until", Time.get_ticks_msec() + 8000)
	var scene := get_tree().current_scene
	if multiplayer.is_server() and scene and scene.has_method("forward_lan_physics_credit"):
		scene.forward_lan_physics_credit(entity_id, attacker)

func set_portal_fall_credit(attacker: Node) -> void:
	set_physics_kill_credit(attacker)

func set_mode_juggernaut(active: bool) -> void:
	if mode_juggernaut == active:
		return
	mode_juggernaut = active
	max_health = 350.0 if active else 100.0
	if active:
		health = max_health
	_refresh_mode_marker()

func set_mode_infected(active: bool) -> void:
	if mode_infected == active:
		return
	mode_infected = active
	if active:
		_ensure_zombie_rig()
	if soldier_rig:
		soldier_rig.visible = not active
	if zombie_rig:
		zombie_rig.visible = active
		zombie_rig.reset_pose()
	_refresh_mode_marker()

func _ensure_zombie_rig() -> void:
	if zombie_rig or not body_root:
		return
	var zombie_rig_script = load(ZOMBIE_RIG_PATH)
	zombie_rig = zombie_rig_script.new()
	zombie_rig.visible = false
	body_root.add_child(zombie_rig)

func _refresh_mode_marker() -> void:
	if is_instance_valid(mode_marker):
		mode_marker.queue_free()
	mode_marker = null
	if not mode_juggernaut or NetworkSession.is_dedicated_server:
		return
	mode_marker = Node3D.new()
	mode_marker.name = "ModePlaceholder"
	add_child(mode_marker)
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.24
	mesh.height = mesh.radius * 2.0
	var color := Color("#ff8738")
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.5
	mesh.material = material
	orb.mesh = mesh
	orb.position.y = 1.65
	mode_marker.add_child(orb)
	var label := Label3D.new()
	label.text = "JUGGERNAUT"
	label.position.y = 2.05
	label.font_size = 34
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mode_marker.add_child(label)

func collect_throwing_axe() -> bool:
	if axes_remaining >= 1:
		return false
	axes_remaining += 1
	return true

func enter_vehicle(vehicle: Node, seat: String) -> void:
	current_vehicle = vehicle
	velocity = Vector3.ZERO
	collision_layer = 0
	if body_collision:
		body_collision.set_deferred("disabled", true)
	if body_root:
		body_root.visible = false
	if nameplate:
		nameplate.visible = false
	for hitbox in hitboxes:
		hitbox.collision_layer = 0
	set_meta("vehicle_seat", seat)

func leave_vehicle(exit_position: Vector3, _forced := false) -> void:
	current_vehicle = null
	global_position = exit_position
	target_position = exit_position
	collision_layer = 2
	if body_collision:
		body_collision.set_deferred("disabled", not alive)
	if body_root:
		body_root.visible = alive
	if nameplate:
		nameplate.visible = alive
	if alive:
		for hitbox in hitboxes:
			hitbox.collision_layer = 8
	remove_meta("vehicle_seat")

func play_remote_shot(weapon_id := "ak47") -> void:
	if soldier_rig:
		equipped_weapon_id = weapon_id
		soldier_rig.set_equipped_weapon(equipped_weapon_id)
		soldier_rig.play_shot()
	if muzzle_light:
		muzzle_light.light_color = Color("#ffbb55")
		muzzle_light.light_energy = 3.5
	if gun_audio:
		var pitches := {"ak47": 0.92, "ar15": 1.0, "smg": 1.08, "pistol": 1.03}
		var sound_path := SHOTGUN_SHOT_SOUND_PATH if weapon_id == "shotgun" else (SNIPER_SHOT_SOUND_PATH if weapon_id == "sniper" else RIFLE_SHOT_SOUND_PATH)
		gun_audio.stream = load(sound_path)
		gun_audio.pitch_scale = float(pitches.get(weapon_id, 1.0))
		gun_audio.play()

func play_remote_coil(target_positions: Array[Vector3]) -> void:
	if soldier_rig:
		equipped_weapon_id = "coil_gun"
		soldier_rig.set_equipped_weapon(equipped_weapon_id)
		soldier_rig.play_shot()
	if muzzle_light:
		muzzle_light.light_color = Color("#71dcff")
		muzzle_light.light_energy = 8.0
	var coil_lightning_script = load(COIL_LIGHTNING_EFFECT_PATH)
	var effect = coil_lightning_script.new()
	get_tree().current_scene.add_child(effect)
	effect.activate(muzzle_light.global_position, target_positions)

func _build_avatar() -> void:
	_build_server_avatar()
	body_root = Node3D.new()
	body_root.position.y = -0.86
	add_child(body_root)
	var soldier_rig_script = load(SOLDIER_RIG_PATH)
	soldier_rig = soldier_rig_script.new()
	soldier_rig.team_color = _team_color()
	soldier_rig.model_id = model_id
	soldier_rig.set_equipped_weapon(equipped_weapon_id)
	body_root.add_child(soldier_rig)
	muzzle_light = OmniLight3D.new()
	muzzle_light.name = "MuzzleFlash"
	muzzle_light.position = Vector3(0, 1.32, -0.88)
	muzzle_light.light_color = Color("#ffbb55")
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 2.5
	body_root.add_child(muzzle_light)
	nameplate = Label3D.new()
	nameplate.text = display_name
	nameplate.position.y = 1.35
	nameplate.font_size = 30
	nameplate.outline_size = 7
	nameplate.modulate = _team_color()
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Keep player names depth-tested so arena geometry and walls occlude them.
	nameplate.no_depth_test = false
	add_child(nameplate)
	gun_audio = AudioStreamPlayer3D.new()
	gun_audio.stream = load(RIFLE_SHOT_SOUND_PATH)
	gun_audio.bus = "SFX"
	gun_audio.volume_db = -8.0
	gun_audio.max_distance = 55.0
	gun_audio.max_polyphony = 4
	add_child(gun_audio)
	death_voice_audio = AudioStreamPlayer3D.new()
	death_voice_audio.name = "DeathVoiceAudio"
	death_voice_audio.bus = "SFX"
	death_voice_audio.volume_db = -2.0
	death_voice_audio.max_distance = 55.0
	add_child(death_voice_audio)
	var jetpack_audio_script = load(JETPACK_THRUSTER_AUDIO_PATH)
	jetpack_thruster_audio = jetpack_audio_script.new()
	add_child(jetpack_thruster_audio)

func _build_server_avatar() -> void:
	body_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	body_collision.shape = capsule
	add_child(body_collision)
	_add_hitbox("head", 2.0, Vector3(0, 0.66, 0), Vector3(0.48, 0.48, 0.46))
	_add_hitbox("torso", 1.0, Vector3(0, 0.14, 0), Vector3(0.52, 0.68, 0.40))
	_add_hitbox("arm_l", 0.75, Vector3(-0.38, 0.34, 0), Vector3(0.22, 0.58, 0.32))
	_add_hitbox("arm_r", 0.75, Vector3(0.38, 0.34, 0), Vector3(0.22, 0.58, 0.32))
	_add_hitbox("leg_l", 0.75, Vector3(-0.15, -0.40, 0), Vector3(0.24, 0.80, 0.34))
	_add_hitbox("leg_r", 0.75, Vector3(0.15, -0.40, 0), Vector3(0.24, 0.80, 0.34))

func _set_tbagging(active: bool) -> void:
	tbagging = active
	if not tbag_audio:
		return
	if active and not tbag_audio.playing:
		tbag_audio.play()
	elif not active and tbag_audio.playing:
		tbag_audio.stop()

func _add_hitbox(zone: String, multiplier: float, position: Vector3, size: Vector3) -> void:
	var hitbox := CombatHitbox.new()
	var shape := BoxShape3D.new()
	shape.size = size
	hitbox.configure(self, zone, multiplier, shape, position)
	hitbox.set_meta("standing_y", position.y)
	add_child(hitbox)
	hitboxes.append(hitbox)

func _set_alive_visual(value: bool) -> void:
	if value:
		if death_tween and death_tween.is_valid():
			death_tween.kill()
		if soldier_rig:
			soldier_rig.reset_pose()
		if zombie_rig:
			zombie_rig.reset_pose()
		last_dismembered_limbs.clear()
		if body_root:
			body_root.visible = true
			body_root.rotation = Vector3.ZERO
			body_root.position = Vector3(0, -0.86, 0)
		if nameplate:
			nameplate.visible = true
	else:
		play_death()
	if body_collision:
		body_collision.set_deferred("disabled", not value)
	for hitbox in hitboxes:
		hitbox.collision_layer = 8 if value else 0

func play_death() -> void:
	alive = false
	_set_tbagging(false)
	velocity = Vector3.ZERO
	last_snapshot_velocity = Vector3.ZERO
	if body_collision:
		body_collision.set_deferred("disabled", true)
	for hitbox in hitboxes:
		hitbox.collision_layer = 0
	if nameplate:
		nameplate.visible = false
	if mode_infected and zombie_rig:
		zombie_rig.play_death()
	else:
		_play_death_voice()
	if not body_root:
		return
	body_root.visible = true
	if death_tween and death_tween.is_valid():
		return
	death_tween = create_tween().set_parallel(true)
	death_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	death_tween.tween_property(body_root, "rotation:z", deg_to_rad(88.0), 0.34)
	death_tween.tween_property(body_root, "position:y", -1.18, 0.34)

func _trigger_lethal_dismemberment(limbs: Array[String], hit_position: Vector3, hit_normal: Vector3) -> void:
	last_dismembered_limbs.assign(limbs)
	if soldier_rig:
		soldier_rig.remove_limbs(limbs)
	_spawn_dismemberment_effects(limbs, hit_position, hit_normal)

func show_network_dismemberment(limbs: Array[String], hit_position: Vector3, hit_normal: Vector3) -> void:
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
	var result: Array[String] = []
	for index in count:
		result.append(pool[index])
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

func _play_death_voice() -> void:
	if death_voice_audio and death_voice_audio.playing:
		return
	if not death_voice_audio:
		return
	var death_voice_pool_script = load(DEATH_VOICE_POOL_PATH)
	var voice: AudioStream = death_voice_pool_script.get_next_voice()
	if voice:
		death_voice_audio.stream = voice
		death_voice_audio.play()

func _team_color() -> Color:
	if NetworkSession.config.get("mode", "ffa") == "ffa":
		var hue := fmod(float(entity_id) * 0.173, 1.0)
		return Color.from_hsv(hue, 0.55, 0.95)
	return Color("#3975a8") if team_id == 0 else Color("#a84d43")

func _attacker_entity_id(attacker: Node) -> int:
	if not attacker:
		return 0
	var value = attacker.get("entity_id")
	if value != null:
		return int(value)
	value = attacker.get("lan_peer_id")
	return int(value) if value != null else 0
