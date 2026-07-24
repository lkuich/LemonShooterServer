extends RigidBody3D

const GRENADE_MODEL_PATH := "res://models/grenade/model.glb"
const EXPLOSION_SOUND_PATH := "res://sounds/sfx/grenade_explosion.mp3"
const ENHANCED_GRENADE_VISUAL_PATH := "res://scripts/enhanced_grenade_visual.gd"

const FUSE_TIME := 2.5
const BLAST_RADIUS := 8.5
const MAX_DAMAGE := 120.0
const GRAVITY_RADIUS := 13.0
const GRAVITY_ACCELERATION := 34.0
const STICKY_BLAST_RADIUS := 12.0
const STICKY_MAX_DAMAGE := 190.0
const BLAST_PROJECTILE_FORCE := 24.0
const ENHANCED_BLAST_PROJECTILE_FORCE := 38.0

var thrower: Node
var fuse_remaining := FUSE_TIME
var exploded := false
var model_root: Node3D
var explosion_audio: AudioStreamPlayer3D
var network_cosmetic := false
var grenade_kind := "normal"
var stuck_target: Node3D
var pending_stick := false
var stick_rearm_time := 0.0

func configure(kind: String) -> void:
	grenade_kind = kind if kind in ["gravity_bomb", "sticky_bomb"] else "normal"

func _ready() -> void:
	add_to_group("physics_projectiles")
	name = "Grenade"
	mass = 0.35
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = 16
	collision_mask = 1 | 2 | 4
	body_entered.connect(_on_body_entered)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.11
	collision.shape = shape
	add_child(collision)
	model_root = Node3D.new()
	model_root.name = "GrenadeModel"
	add_child(model_root)
	if not DedicatedServer.active:
		if grenade_kind == "normal":
			model_root.scale = Vector3.ONE * 0.38
			var grenade_scene := load(GRENADE_MODEL_PATH) as PackedScene
			if grenade_scene:
				model_root.add_child(grenade_scene.instantiate())
		else:
			var enhanced_visual_script := load(ENHANCED_GRENADE_VISUAL_PATH) as Script
			if enhanced_visual_script:
				var enhanced_visual = enhanced_visual_script.new()
				enhanced_visual.configure(grenade_kind, 0.115, 20)
				model_root.add_child(enhanced_visual)
	explosion_audio = AudioStreamPlayer3D.new()
	explosion_audio.name = "ExplosionAudio"
	if not DedicatedServer.active:
		explosion_audio.stream = load(EXPLOSION_SOUND_PATH) as AudioStream
	explosion_audio.bus = "SFX"
	explosion_audio.volume_db = -1.0
	explosion_audio.max_distance = 65.0
	add_child(explosion_audio)

func launch(owner: Node, start_position: Vector3, launch_velocity: Vector3, excluded_bodies: Array[PhysicsBody3D] = []) -> void:
	thrower = owner
	global_position = start_position
	linear_velocity = launch_velocity
	angular_velocity = Vector3(7.0, 10.0, 5.0)
	for body in excluded_bodies:
		if is_instance_valid(body):
			add_collision_exception_with(body)

func _physics_process(delta: float) -> void:
	if exploded:
		return
	stick_rearm_time = maxf(stick_rearm_time - delta, 0.0)
	fuse_remaining -= delta
	if grenade_kind == "gravity_bomb" and not network_cosmetic:
		_apply_gravity_pull(delta)
	if fuse_remaining <= 0.0:
		_explode()

func _on_body_entered(body: Node) -> void:
	if grenade_kind != "sticky_bomb" or pending_stick or stick_rearm_time > 0.0 or is_instance_valid(stuck_target) or body == thrower:
		return
	var candidate: Node3D = body as Node3D
	var damage_owner = body.get("damage_owner")
	if damage_owner is Node3D and damage_owner.is_in_group("combatants"):
		candidate = damage_owner
	if not candidate:
		return
	pending_stick = true
	call_deferred("_stick_to_target", candidate)

func _stick_to_target(candidate: Node3D) -> void:
	if exploded or not is_instance_valid(candidate):
		pending_stick = false
		return
	stuck_target = candidate
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	reparent(candidate, true)
	if not network_cosmetic and candidate.has_method("set_sticky_bomb_panic"):
		candidate.set_sticky_bomb_panic(fuse_remaining)

func _apply_gravity_pull(delta: float) -> void:
	var candidates := get_tree().get_nodes_in_group("combatants")
	candidates.append_array(get_tree().get_nodes_in_group("vehicles"))
	candidates.append_array(get_tree().get_nodes_in_group("physics_objects"))
	var affected: Dictionary = {}
	for candidate in candidates:
		if candidate == self or candidate == thrower or candidate is not Node3D or not is_instance_valid(candidate):
			continue
		var instance_id := candidate.get_instance_id()
		if affected.has(instance_id):
			continue
		affected[instance_id] = true
		var offset: Vector3 = global_position - candidate.global_position
		var distance := offset.length()
		if distance <= 0.25 or distance > GRAVITY_RADIUS:
			continue
		var strength := 1.0 - distance / GRAVITY_RADIUS
		var pull := offset.normalized() * GRAVITY_ACCELERATION * (0.25 + strength * strength) * delta
		if candidate is RigidBody3D:
			candidate.linear_velocity += pull
		elif candidate is CharacterBody3D:
			var scene := get_tree().current_scene
			if scene and scene.has_method("apply_lan_character_velocity"):
				scene.apply_lan_character_velocity(candidate, pull, false)
			else:
				candidate.velocity += pull
		elif candidate.has_method("apply_external_velocity"):
			candidate.apply_external_velocity(pull)

func _explode() -> void:
	if exploded:
		return
	exploded = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	model_root.hide()
	explosion_audio.play()
	if not network_cosmetic:
		_damage_nearby_targets()
		_blast_nearby_projectiles()
	_build_explosion_effect()
	await get_tree().create_timer(2.3).timeout
	queue_free()

func _blast_nearby_projectiles() -> void:
	var enhanced_blast := grenade_kind in ["gravity_bomb", "sticky_bomb"]
	var blast_radius := STICKY_BLAST_RADIUS if enhanced_blast else BLAST_RADIUS
	var maximum_force := ENHANCED_BLAST_PROJECTILE_FORCE if enhanced_blast else BLAST_PROJECTILE_FORCE
	var candidates := get_tree().get_nodes_in_group("physics_projectiles")
	candidates.append_array(get_tree().get_nodes_in_group("physics_objects"))
	var affected: Dictionary = {}
	for candidate in candidates:
		if candidate == self or candidate is not RigidBody3D or not is_instance_valid(candidate):
			continue
		var instance_id := candidate.get_instance_id()
		if affected.has(instance_id):
			continue
		affected[instance_id] = true
		var offset: Vector3 = candidate.global_position - global_position
		var distance := offset.length()
		if distance > blast_radius or distance < 0.05 or not _has_blast_line_of_sight(candidate, candidate.global_position):
			continue
		var strength := clampf(1.0 - distance / blast_radius, 0.15, 1.0)
		var direction := (offset.normalized() + Vector3.UP * 0.24).normalized()
		var impulse_velocity := direction * maximum_force * strength
		if candidate.has_method("apply_explosion_impulse"):
			candidate.apply_explosion_impulse(impulse_velocity)
		else:
			candidate.freeze = false
			candidate.sleeping = false
			candidate.linear_velocity += impulse_velocity
			candidate.angular_velocity += Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)) * strength
		if candidate.is_in_group("physics_projectiles"):
			var scene := get_tree().current_scene
			if scene and scene.has_method("lan_projectile_blast_impulse"):
				scene.lan_projectile_blast_impulse(candidate, impulse_velocity)

func apply_explosion_impulse(impulse_velocity: Vector3) -> void:
	if exploded:
		return
	var previous_target := stuck_target
	if is_instance_valid(stuck_target):
		reparent(get_tree().current_scene, true)
	stuck_target = null
	pending_stick = false
	stick_rearm_time = 0.18
	freeze = false
	sleeping = false
	collision_layer = 16
	collision_mask = 1 | 2 | 4
	linear_velocity += impulse_velocity
	angular_velocity += Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	if previous_target is PhysicsBody3D:
		add_collision_exception_with(previous_target)
		_remove_blast_exception_later(previous_target)

func _remove_blast_exception_later(body: PhysicsBody3D) -> void:
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(body) and is_instance_valid(self):
		remove_collision_exception_with(body)

func _damage_nearby_targets() -> void:
	var enhanced_blast := grenade_kind in ["gravity_bomb", "sticky_bomb"]
	var blast_radius := STICKY_BLAST_RADIUS if enhanced_blast else BLAST_RADIUS
	var max_damage := STICKY_MAX_DAMAGE if enhanced_blast else MAX_DAMAGE
	var blast_shape := SphereShape3D.new()
	blast_shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = blast_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 1 | 2 | 4 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results := get_world_3d().direct_space_state.intersect_shape(query, 128)
	var damaged_targets := {}
	for result in results:
		var collider: Object = result["collider"]
		var target: Node = collider as Node
		if target and target.get("damage_owner") != null:
			target = target.get("damage_owner") as Node
		if not target or target == self or damaged_targets.has(target.get_instance_id()):
			continue
		if grenade_kind == "gravity_bomb" and target == thrower:
			continue
		if not target.has_method("apply_damage") and not target.has_method("apply_hit"):
			continue
		damaged_targets[target.get_instance_id()] = true
		var target_position := global_position
		if target is Node3D:
			target_position = target.global_position + Vector3.UP * 0.45
		var distance := global_position.distance_to(target_position)
		if distance > blast_radius or not _has_blast_line_of_sight(target, target_position):
			continue
		var damage_multiplier := float(thrower.get("explosive_damage_multiplier")) if thrower and thrower.get("explosive_damage_multiplier") != null else 1.0
		var damage_amount := max_damage * damage_multiplier * clampf(1.0 - distance / blast_radius, 0.15, 1.0)
		var health_before = target.get("health")
		var damage_result = false
		if target.has_method("apply_damage"):
			var damage_attacker: Node = null if target == thrower else thrower
			var blast_intensity := clampf(1.0 - distance / blast_radius, 0.0, 1.0)
			if target.has_method("apply_explosion_damage"):
				damage_result = target.apply_explosion_damage(damage_amount, global_position, damage_attacker, blast_intensity)
			else:
				damage_result = target.apply_damage(damage_amount, global_position, damage_attacker)
		else:
			var hit_normal := (target_position - global_position).normalized()
			damage_result = target.apply_hit(damage_amount, target_position, hit_normal, thrower)
		var health_after = target.get("health")
		var target_destroyed: bool = damage_result == true
		var damage_applied: bool = target_destroyed or (health_before != null and health_after != null and float(health_after) < float(health_before))
		if damage_applied and _is_enemy_of_thrower(target):
			_report_enemy_hit(target_destroyed)

func _is_enemy_of_thrower(target: Node) -> bool:
	if not thrower or not target:
		return false
	var thrower_team = thrower.get("team_id")
	var target_team = target.get("team_id")
	if target_team == null and target.has_method("get_team_id"):
		target_team = target.get_team_id()
	return thrower_team != null and target_team != null and int(target_team) >= 0 and int(target_team) != int(thrower_team)

func _report_enemy_hit(destroyed: bool) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("indirect_hit_confirmed"):
		scene.indirect_hit_confirmed(thrower, destroyed)
	elif thrower and thrower.has_method("show_indirect_hitmarker"):
		thrower.show_indirect_hitmarker(destroyed)

func _has_blast_line_of_sight(target: Node, target_position: Vector3) -> bool:
	var origin := global_position + Vector3.UP * 0.18
	var query := PhysicsRayQueryParameters3D.create(origin, target_position)
	query.collision_mask = 1
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.get("collider") == target

func _build_explosion_effect() -> void:
	if DedicatedServer.active:
		return
	var flash := MeshInstance3D.new()
	flash.name = "ExplosionFlash"
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.1
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var blast_color := Color("#ff354f") if grenade_kind == "sticky_bomb" else (Color("#8c65ff") if grenade_kind == "gravity_bomb" else Color("#ff6b14"))
	material.albedo_color = Color(blast_color, 0.82)
	material.emission_enabled = true
	material.emission = blast_color
	material.emission_energy_multiplier = 4.0
	mesh.material = material
	flash.mesh = mesh
	add_child(flash)
	var light := OmniLight3D.new()
	light.light_color = blast_color
	light.light_energy = 12.0
	light.omni_range = 14.0 if grenade_kind == "sticky_bomb" else 10.0
	add_child(light)
	var tween := create_tween().set_parallel(true)
	var effect_scale := 7.5 if grenade_kind == "sticky_bomb" else (6.0 if grenade_kind == "gravity_bomb" else 5.0)
	tween.tween_property(flash, "scale", Vector3.ONE * effect_scale, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "transparency", 1.0, 0.42)
	tween.tween_property(light, "light_energy", 0.0, 0.45)
