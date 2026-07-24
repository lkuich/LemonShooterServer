extends CharacterBody3D

const CombatHitbox = preload("res://scripts/combat_hitbox.gd")
const FallDamage = preload("res://scripts/fall_damage.gd")
const MODEL_FIT_PATH := "res://scripts/model_fit.gd"
const PEOPLE_MODEL_PATHS := [
	"res://models/people/Animated Woman.glb", "res://models/people/Punk.glb",
	"res://models/people/Woman in Dress.glb", "res://models/people/Beach Character.glb",
	"res://models/people/Man.glb"
]

const MAX_HEALTH := 60.0
const WALK_SPEED := 1.7
const FLEE_SPEED := 5.8
const FEAR_DURATION := 7.0
const GUNSHOT_RADIUS := 17.0
const NEAR_MISS_RADIUS := 6.0
const BODY_LIFETIME := 5.0
const RESPAWN_DELAY := 5.0

var actor_id := 0
var team_id := -1
var health := MAX_HEALTH
var alive := true
var despawned := false
var route: Array[Vector3] = []
var route_index := 0
var person_model_index := 0
var fights_back := false

var _fear_time := 0.0
var _escape_target := Vector3.ZERO
var _escape_index := 0
var _flee_direction := 1
var _patrol_direction := 1
var _hitboxes: Array[Area3D] = []
var _body_collision: CollisionShape3D
var _visual_root: Node3D
var _target_position := Vector3.ZERO
var _target_yaw := 0.0
var _lifecycle_timer := 0.0
var _animation_player: AnimationPlayer
var _retaliation_target: Node3D
var _retaliation_time := 0.0
var _punch_cooldown := 0.0
var _replicated_fighting := false
var _stuck_sample_time := 0.0
var _last_progress_position := Vector3.ZERO

func setup(id: int, points: Array[Vector3], start_index: int, model_index := 0) -> void:
	actor_id = id
	route = points.duplicate()
	route_index = posmod(start_index, route.size()) if not route.is_empty() else 0
	person_model_index = posmod(model_index, PEOPLE_MODEL_PATHS.size())
	fights_back = id % 3 == 0
	name = "Civilian_%02d" % id
	if not route.is_empty():
		position = route[route_index]
		route_index = (route_index + 1) % route.size()

func _ready() -> void:
	add_to_group("city_civilians")
	add_to_group("city_damageables")
	collision_layer = 2
	collision_mask = 1 | 4
	_build_placeholder()
	_target_position = global_position
	_target_yaw = rotation.y
	_last_progress_position = global_position

func _physics_process(delta: float) -> void:
	if not alive:
		velocity = Vector3.ZERO
		if _is_authority():
			_lifecycle_timer -= delta
			if _lifecycle_timer <= 0.0:
				if despawned:
					_respawn()
				else:
					_despawn_body()
		return
	if _is_authority():
		_fear_time = maxf(_fear_time - delta, 0.0)
		if _update_retaliation(delta):
			return
		_move_civilian(delta)
		_recover_if_stuck(delta)
	else:
		global_position = global_position.lerp(_target_position, minf(delta * 12.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(delta * 14.0, 1.0))
		_play_animation("punch" if _replicated_fighting else ("run" if _fear_time > 0.0 else "walk"))

func _move_civilian(delta: float) -> void:
	if route.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_move_and_slide_with_fall_damage(delta)
		return
	var target := _escape_target if _fear_time > 0.0 else route[route_index]
	var offset := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if offset.length() < 0.8:
		if _fear_time > 0.0:
			_escape_index = posmod(_escape_index + _flee_direction, route.size())
			_escape_target = route[_escape_index]
		else:
			route_index = posmod(route_index + _patrol_direction, route.size())
		target = _escape_target if _fear_time > 0.0 else route[route_index]
		offset = Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if offset.length_squared() < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		_move_and_slide_with_fall_damage(delta)
		return
	var direction := offset.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 8.0, 1.0))
	var speed := FLEE_SPEED if _fear_time > 0.0 else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_move_and_slide_with_fall_damage(delta)
	_play_animation("run" if _fear_time > 0.0 else "walk")

func _move_and_slide_with_fall_damage(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	var was_airborne := not is_on_floor()
	var landing_speed := maxf(-velocity.y, 0.0)
	move_and_slide()
	if not alive or not was_airborne or not is_on_floor():
		return
	var damage := FallDamage.calculate(landing_speed)
	if damage > 0.0:
		receive_zone_hit(damage, "fall", global_position, Vector3.UP, null)

func consider_gunshot(origin: Vector3, end_position: Vector3) -> void:
	if not _is_authority() or not alive:
		return
	var close_to_sound := global_position.distance_to(origin) <= GUNSHOT_RADIUS
	var close_to_shot := _distance_to_segment(global_position, origin, end_position) <= NEAR_MISS_RADIUS
	if close_to_sound or close_to_shot:
		var instigator := _combatant_near(origin, 4.0)
		if fights_back and instigator:
			_start_retaliation(instigator)
		else:
			scare(origin)

func scare(source_position: Vector3) -> void:
	if not alive:
		return
	_fear_time = FEAR_DURATION
	_choose_escape_target(source_position)

func _choose_escape_target(source_position: Vector3) -> void:
	if route.is_empty():
		return
	var forward_index := route_index
	var backward_index := posmod(route_index - 2, route.size())
	if route[forward_index].distance_squared_to(source_position) >= route[backward_index].distance_squared_to(source_position):
		_escape_index = forward_index
		_flee_direction = 1
	else:
		_escape_index = backward_index
		_flee_direction = -1
	_escape_target = route[_escape_index]

func receive_zone_hit(amount: float, zone: String, hit_position: Vector3, hit_normal: Vector3, attacker: Node) -> bool:
	if not _is_authority():
		var scene := get_tree().current_scene
		if scene and scene.has_method("request_city_actor_hit"):
			var attacker_id := int(attacker.get("entity_id")) if attacker and attacker.get("entity_id") != null else 0
			scene.request_city_actor_hit(attacker_id, actor_id, amount, zone, hit_position, hit_normal)
		return false
	if not alive:
		return false
	if fights_back and attacker is Node3D and attacker.get("alive") == true:
		_start_retaliation(attacker)
	else:
		scare(attacker.global_position if attacker else hit_position)
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_die()
		return true
	return false

func apply_damage(amount: float, source_position: Vector3, attacker: Node) -> bool:
	return receive_zone_hit(amount, "explosion", global_position, (global_position - source_position).normalized(), attacker)

func apply_vehicle_impact(amount: float, push_velocity: Vector3, attacker: Node) -> void:
	velocity.x = push_velocity.x
	velocity.z = push_velocity.z
	if amount > 0.0:
		receive_zone_hit(amount, "vehicle", global_position, -push_velocity.normalized(), attacker)

func snapshot_state() -> Dictionary:
	return {"position": global_position, "yaw": rotation.y, "health": health, "alive": alive, "despawned": despawned, "fear": _fear_time, "fighting": is_instance_valid(_retaliation_target), "route_index": route_index}

func apply_snapshot(state: Dictionary) -> void:
	_target_position = state.get("position", global_position)
	_target_yaw = float(state.get("yaw", rotation.y))
	health = float(state.get("health", health))
	_fear_time = float(state.get("fear", _fear_time))
	_replicated_fighting = state.get("fighting", false) == true
	route_index = int(state.get("route_index", route_index))
	var state_alive: bool = state.get("alive", alive) == true
	var state_despawned: bool = state.get("despawned", despawned) == true
	if alive and not state_alive:
		_die()
	if not state_alive and state_despawned and not despawned:
		_despawn_body()
	if not alive and state_alive:
		_respawn(state.get("position", global_position), float(state.get("yaw", rotation.y)))
	alive = state_alive
	despawned = state_despawned if not state_alive else false

func _die() -> void:
	if not alive:
		return
	alive = false
	despawned = false
	health = 0.0
	_lifecycle_timer = BODY_LIFETIME
	velocity = Vector3.ZERO
	if _body_collision:
		_body_collision.set_deferred("disabled", true)
	for hitbox in _hitboxes:
		hitbox.collision_layer = 0
	_play_animation("death")

func _despawn_body() -> void:
	if despawned:
		return
	despawned = true
	_lifecycle_timer = RESPAWN_DELAY
	if _visual_root:
		_visual_root.visible = false

func _respawn(forced_position = null, forced_yaw = null) -> void:
	var spawn_index := _best_respawn_route_index()
	if forced_position == null and not route.is_empty():
		position = route[spawn_index]
		_patrol_direction = 1
		route_index = (spawn_index + _patrol_direction) % route.size()
	else:
		global_position = forced_position
	if forced_yaw == null and not route.is_empty():
		var direction: Vector3 = (route[route_index] - position).normalized()
		rotation.y = atan2(-direction.x, -direction.z)
	else:
		rotation.y = float(forced_yaw)
	health = MAX_HEALTH
	alive = true
	despawned = false
	_fear_time = 0.0
	_lifecycle_timer = 0.0
	velocity = Vector3.ZERO
	_target_position = global_position
	_target_yaw = rotation.y
	_last_progress_position = global_position
	_stuck_sample_time = 0.0
	if _visual_root:
		_visual_root.visible = true
		_visual_root.rotation = Vector3.ZERO
		_visual_root.position = Vector3.ZERO
	_body_collision.set_deferred("disabled", false)
	for hitbox in _hitboxes:
		hitbox.collision_layer = 8
	_retaliation_target = null
	_replicated_fighting = false
	_play_animation("idle")

func _best_respawn_route_index() -> int:
	if route.is_empty():
		return 0
	var best_index := 0
	var best_clearance := -1.0
	for index in route.size():
		var clearance := 1000000.0
		for combatant in get_tree().get_nodes_in_group("combatants"):
			if combatant.get("alive") == true:
				clearance = minf(clearance, route[index].distance_squared_to(combatant.global_position))
		if clearance > best_clearance:
			best_clearance = clearance
			best_index = index
	return best_index

func _build_placeholder() -> void:
	_body_collision = CollisionShape3D.new()
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.38
	body_shape.height = 1.62
	_body_collision.shape = body_shape
	_body_collision.position.y = 0.84
	add_child(_body_collision)

	_visual_root = Node3D.new()
	_visual_root.name = "CivilianModel"
	add_child(_visual_root)
	if not NetworkSession.is_dedicated_server:
		var person_scene = load(PEOPLE_MODEL_PATHS[person_model_index])
		var model: Node3D = person_scene.instantiate()
		_visual_root.add_child(model)
		var model_fit = load(MODEL_FIT_PATH)
		model_fit.fit_to_size(model, 1.68)
		# Imported characters face +Z; civilian movement treats -Z as forward.
		model.rotation.y = PI
		_animation_player = model_fit.find_animation_player(model)
		_play_animation("walk")

	_add_hitbox("torso", 1.0, Vector3(0.72, 0.96, 0.50), Vector3(0, 0.97, 0))
	_add_hitbox("head", 2.0, Vector3(0.58, 0.58, 0.58), Vector3(0, 1.66, 0))

func _add_hitbox(zone: String, multiplier: float, size: Vector3, local_position: Vector3) -> void:
	var hitbox := CombatHitbox.new()
	var shape := BoxShape3D.new()
	shape.size = size
	hitbox.configure(self, zone, multiplier, shape, local_position)
	add_child(hitbox)
	_hitboxes.append(hitbox)

func _box_mesh(size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.position = local_position
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	instance.mesh = mesh
	return instance

func _distance_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	if segment.length_squared() < 0.001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)

func _update_retaliation(delta: float) -> bool:
	if not is_instance_valid(_retaliation_target) or _retaliation_target.get("alive") != true:
		_retaliation_target = null
		return false
	_retaliation_time -= delta
	_punch_cooldown = maxf(_punch_cooldown - delta, 0.0)
	if _retaliation_time <= 0.0:
		_retaliation_target = null
		return false
	var offset: Vector3 = _retaliation_target.global_position - global_position
	offset.y = 0.0
	if offset.length() > 1.45:
		var direction := offset.normalized()
		look_at(global_position + direction, Vector3.UP)
		velocity.x = direction.x * 4.2
		velocity.z = direction.z * 4.2
		_move_and_slide_with_fall_damage(delta)
		_play_animation("run")
	else:
		velocity = Vector3.ZERO
		_move_and_slide_with_fall_damage(delta)
		if offset.length_squared() > 0.0001:
			look_at(Vector3(_retaliation_target.global_position.x, global_position.y, _retaliation_target.global_position.z), Vector3.UP)
		if _punch_cooldown <= 0.0:
			_punch_cooldown = 0.9
			_play_animation("punch")
			if _retaliation_target.has_method("receive_zone_hit"):
				_retaliation_target.receive_zone_hit(12.0, "torso", _retaliation_target.global_position, (global_position - _retaliation_target.global_position).normalized(), self)
			elif _retaliation_target.has_method("apply_damage"):
				_retaliation_target.apply_damage(12.0, global_position, self)
	return true

func _start_retaliation(target: Node3D) -> void:
	_retaliation_target = target
	_retaliation_time = 8.0
	_fear_time = 0.0

func _combatant_near(point: Vector3, radius: float) -> Node3D:
	var nearest: Node3D
	var nearest_distance := radius * radius
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if candidate is not Node3D or candidate.get("alive") != true:
			continue
		var distance := point.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest

func _recover_if_stuck(delta: float) -> void:
	_stuck_sample_time += delta
	if _stuck_sample_time < 0.9:
		return
	var moved := Vector2(global_position.x - _last_progress_position.x, global_position.z - _last_progress_position.z).length()
	var movement_target := _escape_target if _fear_time > 0.0 else route[route_index]
	var trying_to_move := Vector2(movement_target.x - global_position.x, movement_target.z - global_position.z).length() > 0.5
	if trying_to_move and moved < 0.16 and not route.is_empty():
		if _fear_time > 0.0:
			_flee_direction *= -1
			_escape_index = posmod(_escape_index + _flee_direction, route.size())
			_escape_target = route[_escape_index]
		else:
			var old_direction := _patrol_direction
			_patrol_direction *= -1
			route_index = posmod(route_index - old_direction * 2, route.size())
	_last_progress_position = global_position
	_stuck_sample_time = 0.0

func _play_animation(kind: String) -> void:
	if not _animation_player:
		return
	var fragments: Array[String]
	match kind:
		"walk": fragments = ["|walk"]
		"run": fragments = ["|run"]
		"punch": fragments = ["punch_left", "female_punch", "man_punch", "|punch"]
		"death": fragments = ["|death", "female_death", "man_death"]
		_: fragments = ["idle_neutral", "female_idle", "man_idle", "|idle"]
	var model_fit = load(MODEL_FIT_PATH)
	var animation_name: StringName = model_fit.animation_matching(_animation_player, fragments)
	if animation_name.is_empty() or _animation_player.current_animation == animation_name:
		return
	var animation := _animation_player.get_animation(animation_name)
	if animation and kind in ["walk", "run", "idle"]:
		animation.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(animation_name, 0.16)

func _is_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
