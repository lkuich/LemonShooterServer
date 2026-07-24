extends CharacterBody3D

signal killed(dog: Node, attacker: Node)
signal expired(dog: Node)

const CombatHitbox = preload("res://scripts/combat_hitbox.gd")
const FallDamage = preload("res://scripts/fall_damage.gd")
const DOG_MODEL_PATH := "res://models/dog/model.glb"
const MODEL_FIT_PATH := "res://scripts/model_fit.gd"

const MOVE_SPEED := 8.2
const ATTACK_RANGE := 1.55
const ATTACK_DAMAGE := 10000.0
const ATTACK_INTERVAL := 0.78
const BARK_DISTANCE := 17.0
const LIFETIME := 15.0

var dog_id := 0
var owner_entity_id := 0
var entity_id := 0
var streak_owner: Node
var team_id := 0
var health := 80.0
var max_health := 80.0
var alive := true
var authoritative := true
var is_human_player := false
var current_vehicle: Node

var target: Node3D
var target_refresh_timer := 0.0
var attack_cooldown := 0.0
var visual_root: Node3D
var animation_player: AnimationPlayer
var body_collision: CollisionShape3D
var hitboxes: Array[Area3D] = []
var bark_audio: AudioStreamPlayer3D
var current_animation := ""
var target_position := Vector3.ZERO
var target_yaw := 0.0
var snapshot_velocity := Vector3.ZERO
var navigation_points: Array[Vector3] = []
var bark_cooldown := 0.0
var lifetime_remaining := LIFETIME

func setup(id: int, owner_id: int, owner_node: Node, assigned_team: int, is_authoritative := true, points: Array[Vector3] = []) -> void:
	dog_id = id
	owner_entity_id = owner_id
	entity_id = owner_id
	streak_owner = owner_node
	team_id = assigned_team
	authoritative = is_authoritative
	navigation_points.assign(points)
	name = "AttackDog_%d" % dog_id

func _ready() -> void:
	add_to_group("attack_dogs")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.4
	_build_rig()
	bark_cooldown = randf_range(0.0, 1.25)
	target_position = global_position
	target_yaw = rotation.y
	_play_animation("idle")

func _physics_process(delta: float) -> void:
	if authoritative:
		lifetime_remaining -= delta
		if lifetime_remaining <= 0.0:
			expired.emit(self)
			set_physics_process(false)
			return
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	bark_cooldown = maxf(bark_cooldown - delta, 0.0)
	_update_barking()
	if not alive:
		return
	if not authoritative:
		global_position = global_position.lerp(target_position, minf(delta * 14.0, 1.0))
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 16.0, 1.0))
		velocity = snapshot_velocity
		if attack_cooldown <= 0.0:
			_play_animation("run" if Vector2(velocity.x, velocity.z).length() > 0.5 else "idle")
		return
	if not _is_valid_target(target):
		target = null
		target_refresh_timer -= delta
		if target_refresh_timer <= 0.0:
			_select_target()
	if not is_instance_valid(target):
		# Stop outright while waiting for a target so repeated scans cannot make the
		# dog twitch between headings or coast around the map.
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		_move_and_slide_with_fall_damage()
		_play_animation("idle")
		return
	var chase_position := _chase_position(target.global_position)
	var offset := chase_position - global_position
	offset.y = 0.0
	var distance := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()
	if distance <= ATTACK_RANGE and _clear_path_to(target.global_position):
		velocity.x = move_toward(velocity.x, 0.0, delta * 24.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 24.0)
		_face_direction(offset)
		if attack_cooldown <= 0.0:
			_attack_target()
	else:
		var direction := offset.normalized()
		_face_direction(direction)
		velocity.x = move_toward(velocity.x, direction.x * MOVE_SPEED, delta * 28.0)
		velocity.z = move_toward(velocity.z, direction.z * MOVE_SPEED, delta * 28.0)
		if is_on_wall() and is_on_floor():
			velocity.y = 4.2
		_play_animation("run")
	_apply_gravity(delta)
	_move_and_slide_with_fall_damage()

func _move_and_slide_with_fall_damage() -> void:
	var was_airborne := not is_on_floor()
	var landing_speed := maxf(-velocity.y, 0.0)
	move_and_slide()
	if not authoritative or not alive or not was_airborne or not is_on_floor():
		return
	var damage := FallDamage.calculate(landing_speed)
	if damage > 0.0:
		receive_zone_hit(damage, "fall", global_position, Vector3.UP, null)

func _build_rig() -> void:
	body_collision = CollisionShape3D.new()
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.28
	body_shape.height = 0.95
	body_collision.shape = body_shape
	body_collision.position = Vector3(0, 0.48, 0)
	add_child(body_collision)
	if not NetworkSession.is_dedicated_server:
		visual_root = Node3D.new()
		visual_root.name = "DogRig"
		add_child(visual_root)
		var dog_model = load(DOG_MODEL_PATH)
		var model: Node3D = dog_model.instantiate()
		visual_root.add_child(model)
		var model_fit = load(MODEL_FIT_PATH)
		model_fit.fit_to_size(model, 1.05, 1.55)
		model.rotation.y = PI
		animation_player = model_fit.find_animation_player(model)
	_add_hitbox("body", 1.0, Vector3(0, 0.55, 0), Vector3(0.62, 0.72, 1.05))
	_add_hitbox("head", 1.5, Vector3(0, 0.68, -0.63), Vector3(0.48, 0.48, 0.48))

func _add_hitbox(zone: String, multiplier: float, local_position: Vector3, size: Vector3) -> void:
	var hitbox := CombatHitbox.new()
	var shape := BoxShape3D.new()
	shape.size = size
	hitbox.configure(self, zone, multiplier, shape, local_position)
	add_child(hitbox)
	hitboxes.append(hitbox)

func _select_target() -> void:
	target_refresh_timer = randf_range(0.22, 0.42)
	var nearest: Node3D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if not _is_valid_target(candidate):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	for candidate in get_tree().get_nodes_in_group("city_civilians"):
		if not _is_valid_target(candidate):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	target = nearest

func _is_valid_target(candidate: Node) -> bool:
	if not is_instance_valid(candidate) or candidate == self or candidate.get("alive") != true:
		return false
	if candidate.is_in_group("city_civilians"):
		return true
	return candidate.get("team_id") != team_id

func _attack_target() -> void:
	if not _is_valid_target(target):
		return
	attack_cooldown = ATTACK_INTERVAL
	_play_animation("attack", true)
	var hit_position := target.global_position + Vector3.UP * 0.45
	var hit_normal := (global_position - target.global_position).normalized()
	var health_before = target.get("health")
	var damage_result = false
	if target.has_method("receive_zone_hit"):
		damage_result = target.receive_zone_hit(ATTACK_DAMAGE, "torso", hit_position, hit_normal, self)
	elif target.has_method("apply_damage"):
		damage_result = target.apply_damage(ATTACK_DAMAGE, global_position, self)
	var health_after = target.get("health")
	if damage_result == true or (health_before != null and health_after != null and float(health_after) < float(health_before)):
		_report_owner_hit(damage_result == true)

func _report_owner_hit(destroyed: bool) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("indirect_hit_confirmed"):
		scene.indirect_hit_confirmed(streak_owner, destroyed)
	elif streak_owner and streak_owner.has_method("show_indirect_hitmarker"):
		streak_owner.show_indirect_hitmarker(destroyed)

func receive_zone_hit(amount: float, _zone: String, hit_position: Vector3, hit_normal: Vector3, attacker: Node) -> bool:
	if not authoritative:
		var scene := get_tree().current_scene
		if scene and scene.has_method("request_attack_dog_hit"):
			var attacker_id := int(attacker.get("entity_id")) if attacker and attacker.get("entity_id") != null else 0
			scene.request_attack_dog_hit(attacker_id, dog_id, amount, hit_position, hit_normal)
		return false
	if not alive:
		return false
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_die(attacker)
		return true
	_play_animation("hit", true)
	return false

func apply_damage(amount: float, source_position: Vector3, attacker: Node) -> bool:
	return receive_zone_hit(amount, "body", global_position, (global_position - source_position).normalized(), attacker)

func apply_explosion_damage(amount: float, source_position: Vector3, attacker: Node, _intensity := 1.0) -> bool:
	return apply_damage(amount, source_position, attacker)

func apply_vehicle_impact(amount: float, push_velocity: Vector3, attacker: Node) -> void:
	velocity = push_velocity
	if authoritative and amount > 0.0:
		receive_zone_hit(amount, "body", global_position, -push_velocity.normalized(), attacker)

func _die(attacker: Node) -> void:
	alive = false
	velocity = Vector3.ZERO
	body_collision.set_deferred("disabled", true)
	for hitbox in hitboxes:
		hitbox.collision_layer = 0
	_play_animation("death", true)
	killed.emit(self, attacker)

func snapshot_state() -> Dictionary:
	return {
		"position": global_position, "yaw": rotation.y, "velocity": velocity,
		"alive": alive, "health": health, "owner": owner_entity_id, "team": team_id,
		"animation": current_animation
	}

func apply_snapshot(state: Dictionary) -> void:
	target_position = state.get("position", global_position)
	target_yaw = float(state.get("yaw", rotation.y))
	snapshot_velocity = state.get("velocity", Vector3.ZERO)
	health = float(state.get("health", health))
	var replicated_animation := str(state.get("animation", "")).to_lower()
	if replicated_animation.contains("attack"):
		attack_cooldown = 0.35
		_play_animation("attack")
	var state_alive: bool = state.get("alive", alive) == true
	if alive and not state_alive:
		_die(null)
	alive = state_alive

func _update_barking() -> void:
	if not bark_audio or not alive or bark_audio.playing or bark_cooldown > 0.0:
		return
	for other in get_tree().get_nodes_in_group("attack_dogs"):
		if other != self and other.get("bark_audio") is AudioStreamPlayer3D and other.get("bark_audio").playing:
			return
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if candidate.get("is_human_player") == true and candidate.get("alive") == true and global_position.distance_to(candidate.global_position) <= BARK_DISTANCE:
			bark_audio.pitch_scale = randf_range(0.92, 1.08)
			bark_audio.play()
			bark_cooldown = randf_range(3.0, 5.5)
			return

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		look_at(global_position + Vector3(direction.x, 0.0, direction.z), Vector3.UP)

func _chase_position(final_position: Vector3) -> Vector3:
	if navigation_points.is_empty() or _clear_path_to(final_position):
		return final_position
	var best := final_position
	var best_score := INF
	for point in navigation_points:
		var local_distance := Vector2(point.x - global_position.x, point.z - global_position.z).length()
		if local_distance < 1.0 or local_distance > 13.0 or absf(point.y - global_position.y) > 2.2:
			continue
		if not _clear_path_to(point):
			continue
		var score := local_distance + Vector2(final_position.x - point.x, final_position.z - point.z).length() * 0.35
		if score < best_score:
			best_score = score
			best = point
	return best

func _clear_path_to(point: Vector3) -> bool:
	var origin := global_position + Vector3.UP * 0.45
	var destination := point + Vector3.UP * 0.45
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _play_animation(kind: String, restart := false) -> void:
	if not animation_player:
		return
	var fragments: Array[String]
	match kind:
		"run": fragments = ["gallop", "walk"]
		"attack": fragments = ["attack"]
		"death": fragments = ["death"]
		"hit": fragments = ["hitreact"]
		_: fragments = ["idle"]
	var model_fit = load(MODEL_FIT_PATH)
	var animation: StringName = model_fit.animation_matching(animation_player, fragments)
	if animation == &"":
		return
	if not restart and current_animation == str(animation) and animation_player.is_playing():
		return
	current_animation = str(animation)
	animation_player.play(animation, 0.12)
