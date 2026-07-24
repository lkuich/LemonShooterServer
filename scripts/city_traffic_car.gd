extends CharacterBody3D

const CombatHitbox = preload("res://scripts/combat_hitbox.gd")
const MODEL_FIT_PATH := "res://scripts/model_fit.gd"

const VEHICLE_PROFILES := {
	"sports": {"name": "Sports Car", "scene_path": "res://models/vehicles/sports_car.glb", "speed": 36.0, "reverse": 11.0, "acceleration": 19.0, "brake": 24.0, "handling": 1.85, "cruise": 14.0, "health": 140.0, "height": 1.35, "length": 4.5},
	"fast": {"name": "Fast Car", "scene_path": "res://models/vehicles/fast_car.glb", "speed": 32.0, "reverse": 10.0, "acceleration": 17.0, "brake": 22.0, "handling": 1.45, "cruise": 12.5, "health": 160.0, "height": 1.4, "length": 4.6},
	"mazda": {"name": "Mazda", "scene_path": "res://models/vehicles/mazda_car.glb", "speed": 24.0, "reverse": 9.0, "acceleration": 12.0, "brake": 18.0, "handling": 2.05, "cruise": 10.0, "health": 190.0, "height": 1.35, "length": 4.35},
	"police": {"name": "Police Car", "scene_path": "res://models/vehicles/police_car.glb", "speed": 28.0, "reverse": 10.0, "acceleration": 15.0, "brake": 21.0, "handling": 1.75, "cruise": 11.0, "health": 230.0, "height": 1.4, "length": 4.4}
}

const MAX_HEALTH := 180.0
const CRUISE_SPEED := 10.0
const IMPACT_DAMAGE := 38.0
const IMPACT_PUSH := 21.0
const WRECK_LIFETIME := 7.0
const RESPAWN_DELAY := 4.0
const PORTAL_AIRBORNE_TIME := 0.35
const AIR_DRAG := 0.4
const UPRIGHT_RECOVERY_SPEED := 3.2
const CRUSH_IMPACT_SPEED := 2.5
const SUPPORT_PROBE_DEPTH := 1.35
const SUPPORT_OFFSETS := [
	Vector3(-0.9, 0.3, -1.75), Vector3(0.9, 0.3, -1.75),
	Vector3(-0.9, 0.3, 1.75), Vector3(0.9, 0.3, 1.75)
]

var actor_id := 0
var team_id := -1
var max_health := MAX_HEALTH
var health := MAX_HEALTH
var alive := true
var despawned := false
var route: Array[Vector3] = []
var route_index := 0
var vehicle_type := "mazda"
var vehicle_display_name := "Car"
var current_speed := 0.0
var driver: Node
var passenger: Node
var network_mode := false
var network_id := 0
var network_driver_input := Vector3.ZERO

var _hitbox: Area3D
var _body_collision: CollisionShape3D
var _visual_root: Node3D
var _impact_cooldowns: Dictionary = {}
var _target_position := Vector3.ZERO
var _target_yaw := 0.0
var _lifecycle_timer := 0.0
var _profile: Dictionary
var _camera_pivot: Node3D
var _chase_camera: Camera3D
var _portal_airborne_time := 0.0
var _tipping_velocity := Vector2.ZERO

func setup(id: int, points: Array[Vector3], start_index: int, profile_id: String) -> void:
	actor_id = id
	route = points.duplicate()
	route_index = posmod(start_index, route.size()) if not route.is_empty() else 0
	vehicle_type = profile_id if VEHICLE_PROFILES.has(profile_id) else "mazda"
	_profile = VEHICLE_PROFILES[vehicle_type]
	vehicle_display_name = _profile["name"]
	max_health = float(_profile["health"])
	health = max_health
	name = "TrafficCar_%02d" % id
	if not route.is_empty():
		position = route[route_index]
		route_index = (route_index + 1) % route.size()
		var initial_direction: Vector3 = (route[route_index] - position).normalized()
		rotation.y = atan2(-initial_direction.x, -initial_direction.z)

func _ready() -> void:
	add_to_group("city_damageables")
	add_to_group("vehicles")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	_build_placeholder()
	if not NetworkSession.is_dedicated_server:
		_build_camera()
	_target_position = global_position
	_target_yaw = rotation.y

func _physics_process(delta: float) -> void:
	_update_impact_cooldowns(delta)
	if not alive:
		velocity = Vector3.ZERO
		if _is_authority():
			_lifecycle_timer -= delta
			if _lifecycle_timer <= 0.0:
				if despawned:
					_respawn()
			else:
				_despawn_wreck()
		return
	if _is_authority():
		_portal_airborne_time = maxf(_portal_airborne_time - delta, 0.0)
		var support := _sample_ground_support()
		var downward_impact_speed := 0.0
		if _portal_airborne_time > 0.0 or not is_on_floor() or int(support["count"]) < 3:
			downward_impact_speed = _move_while_falling(delta, support)
		else:
			_recover_upright(delta)
			if driver:
				_drive_player(delta)
			else:
				_drive_route(delta)
		_process_impacts(downward_impact_speed)
	else:
		global_position = global_position.lerp(_target_position, minf(delta * 12.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(delta * 14.0, 1.0))
		_sync_driver()

func begin_portal_travel(outgoing_velocity: Vector3, outgoing_basis: Basis) -> void:
	velocity = outgoing_velocity
	global_basis = outgoing_basis.orthonormalized()
	_portal_airborne_time = PORTAL_AIRBORNE_TIME

func _move_while_falling(delta: float, support: Dictionary) -> float:
	velocity += get_gravity() * delta
	velocity.x = move_toward(velocity.x, 0.0, AIR_DRAG * delta)
	velocity.z = move_toward(velocity.z, 0.0, AIR_DRAG * delta)
	var support_count := int(support["count"])
	if support_count > 0 and support_count < 3:
		var local_support := global_basis.inverse() * (support["average"] as Vector3 - global_position)
		var target_tipping := Vector2(clampf(-local_support.z * 0.9, -1.9, 1.9), clampf(local_support.x * 0.9, -1.9, 1.9))
		_tipping_velocity = _tipping_velocity.lerp(target_tipping, minf(delta * 5.0, 1.0))
	else:
		_tipping_velocity = _tipping_velocity.lerp(Vector2.ZERO, minf(delta * 0.7, 1.0))
	rotation.x += _tipping_velocity.x * delta
	rotation.z += _tipping_velocity.y * delta
	var landing_speed := maxf(-velocity.y, 0.0)
	move_and_slide()
	if is_on_floor() and int(_sample_ground_support()["count"]) >= 3:
		_portal_airborne_time = 0.0
		var landing_damping := clampf(1.0 - landing_speed * 0.012, 0.68, 0.96)
		velocity.x *= landing_damping
		velocity.z *= landing_damping
		_recover_upright(delta)
	_sync_driver()
	return landing_speed

func _recover_upright(delta: float) -> void:
	_tipping_velocity = _tipping_velocity.lerp(Vector2.ZERO, minf(delta * 8.0, 1.0))
	rotation.x = move_toward(rotation.x, 0.0, UPRIGHT_RECOVERY_SPEED * delta)
	rotation.z = move_toward(rotation.z, 0.0, UPRIGHT_RECOVERY_SPEED * delta)

func _sample_ground_support() -> Dictionary:
	var count := 0
	var average := Vector3.ZERO
	for raw_offset in SUPPORT_OFFSETS:
		var offset: Vector3 = raw_offset
		var origin: Vector3 = global_transform * offset
		var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * SUPPORT_PROBE_DEPTH)
		query.collision_mask = 1 | 4
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and Vector3(hit["normal"]).dot(Vector3.UP) > 0.35:
			count += 1
			average += hit["position"] as Vector3
	if count > 0:
		average /= float(count)
	return {"count": count, "average": average}

func _drive_route(delta: float) -> void:
	if route.is_empty():
		return
	var target := route[route_index]
	var flat_offset := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if flat_offset.length() < 1.8:
		route_index = (route_index + 1) % route.size()
		target = route[route_index]
		flat_offset = Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if flat_offset.length_squared() < 0.01:
		return
	var direction := flat_offset.normalized()
	var desired_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, minf(delta * 4.5, 1.0))
	var forward := -global_transform.basis.z
	current_speed = float(_profile["cruise"])
	velocity = Vector3(forward.x, 0.0, forward.z).normalized() * current_speed
	move_and_slide()
	_sync_driver()

func _drive_player(delta: float) -> void:
	var throttle := 0.0
	var steering := 0.0
	var braking := false
	if network_mode:
		throttle = network_driver_input.x
		steering = network_driver_input.y
		braking = network_driver_input.z > 0.5
	else:
		throttle = Input.get_axis("move_back", "move_forward")
		steering = Input.get_axis("move_left", "move_right")
		braking = Input.is_action_pressed("jump")
	if braking:
		current_speed = move_toward(current_speed, 0.0, float(_profile["brake"]) * delta)
	elif absf(throttle) > 0.05:
		var target_speed := float(_profile["speed"]) if throttle > 0.0 else -float(_profile["reverse"])
		current_speed = move_toward(current_speed, target_speed, float(_profile["acceleration"]) * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, 4.0 * delta)
	if absf(current_speed) > 0.2:
		var speed_ratio := clampf(absf(current_speed) / float(_profile["speed"]), 0.0, 1.0)
		var turn_rate := float(_profile["handling"]) * lerpf(1.0, 0.55, speed_ratio)
		rotation.y -= steering * turn_rate * delta * signf(current_speed)
	var forward := -global_transform.basis.z
	velocity = Vector3(forward.x * current_speed, velocity.y, forward.z * current_speed)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	_sync_driver()

func _process_impacts(downward_speed := 0.0) -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var victim := collision.get_collider()
		if not victim or not victim.has_method("apply_vehicle_impact"):
			continue
		var victim_id := victim.get_instance_id()
		if float(_impact_cooldowns.get(victim_id, 0.0)) > 0.0:
			continue
		var push_direction: Vector3 = victim.global_position - global_position
		push_direction.y = 0.0
		if push_direction.length_squared() < 0.01:
			push_direction = -global_transform.basis.z
		var crushing := downward_speed >= CRUSH_IMPACT_SPEED and collision.get_normal().dot(Vector3.UP) > 0.35
		var impact_damage := 10000.0 if crushing else clampf(18.0 + absf(current_speed) * 2.0, IMPACT_DAMAGE, 95.0)
		var push_velocity := Vector3.DOWN * downward_speed if crushing else push_direction.normalized() * maxf(IMPACT_PUSH, absf(current_speed))
		var attacker: Node = driver if driver else self
		if crushing:
			if victim.get("invulnerable_time") != null:
				victim.set("invulnerable_time", 0.0)
			if not driver:
				attacker = null
		victim.apply_vehicle_impact(impact_damage, push_velocity, attacker)
		_impact_cooldowns[victim_id] = 0.9

func receive_zone_hit(amount: float, _zone: String, hit_position: Vector3, hit_normal: Vector3, attacker: Node) -> bool:
	if not _is_authority():
		var scene := get_tree().current_scene
		if scene and scene.has_method("request_city_actor_hit"):
			var attacker_id := int(attacker.get("entity_id")) if attacker and attacker.get("entity_id") != null else 0
			scene.request_city_actor_hit(attacker_id, actor_id, amount, _zone, hit_position, hit_normal)
		return false
	if not alive:
		return false
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_destroy()
		return true
	return false

func apply_damage(amount: float, source_position: Vector3, attacker: Node) -> bool:
	return receive_zone_hit(amount, "explosion", global_position, (global_position - source_position).normalized(), attacker)

func apply_occupant_damage(amount: float, attacker: Node) -> void:
	# The occupant applies their own armor-reduced share after routing the shot
	# here, matching the existing Hummer damage contract.
	receive_zone_hit(amount, "vehicle", global_position, Vector3.UP, attacker)

func apply_vehicle_impact(amount: float, push_velocity: Vector3, attacker: Node) -> void:
	if amount > 0.0:
		receive_zone_hit(amount, "vehicle", global_position, -push_velocity.normalized(), attacker)

func snapshot_state() -> Dictionary:
	return {"position": global_position, "yaw": rotation.y, "health": health, "alive": alive, "despawned": despawned, "route_index": route_index}

func apply_snapshot(state: Dictionary) -> void:
	_target_position = state.get("position", global_position)
	_target_yaw = float(state.get("yaw", rotation.y))
	health = float(state.get("health", health))
	route_index = int(state.get("route_index", route_index))
	var state_alive: bool = state.get("alive", alive) == true
	var state_despawned: bool = state.get("despawned", despawned) == true
	if alive and not state_alive:
		_destroy()
	if not state_alive and state_despawned and not despawned:
		_despawn_wreck()
	if not alive and state_alive:
		_respawn(state.get("position", global_position), float(state.get("yaw", rotation.y)))
	alive = state_alive
	despawned = state_despawned if not state_alive else false

func _destroy() -> void:
	if not alive:
		return
	alive = false
	despawned = false
	health = 0.0
	_lifecycle_timer = WRECK_LIFETIME
	if driver:
		leave_seat(driver, true)
	velocity = Vector3.ZERO
	if _hitbox:
		_hitbox.collision_layer = 0
	if _visual_root:
		_visual_root.rotation.z = deg_to_rad(8.0)
		var wreck_material := StandardMaterial3D.new()
		wreck_material.albedo_color = Color("#242829")
		wreck_material.roughness = 1.0
		_apply_material_override(_visual_root, wreck_material)

func _despawn_wreck() -> void:
	if despawned:
		return
	despawned = true
	_lifecycle_timer = RESPAWN_DELAY
	_visual_root.visible = false
	_body_collision.set_deferred("disabled", true)

func _respawn(forced_position = null, forced_yaw = null) -> void:
	var spawn_index := _best_respawn_route_index()
	if forced_position == null and not route.is_empty():
		position = route[spawn_index]
		route_index = (spawn_index + 1) % route.size()
	else:
		global_position = forced_position
	if forced_yaw == null and not route.is_empty():
		var direction: Vector3 = (route[route_index] - position).normalized()
		rotation.y = atan2(-direction.x, -direction.z)
	else:
		rotation.y = float(forced_yaw)
	health = max_health
	alive = true
	despawned = false
	_lifecycle_timer = 0.0
	velocity = Vector3.ZERO
	_target_position = global_position
	_target_yaw = rotation.y
	_visual_root.visible = true
	_visual_root.rotation.z = 0.0
	_apply_material_override(_visual_root, null)
	_body_collision.set_deferred("disabled", false)
	_hitbox.collision_layer = 8

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
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(2.2, 1.25, 4.4)
	_body_collision.shape = body_shape
	_body_collision.position.y = 0.75
	add_child(_body_collision)

	_visual_root = Node3D.new()
	_visual_root.name = "VehicleModel"
	add_child(_visual_root)
	if not NetworkSession.is_dedicated_server:
		var vehicle_scene = load(str(_profile["scene_path"]))
		var model: Node3D = vehicle_scene.instantiate()
		_visual_root.add_child(model)
		var model_fit = load(MODEL_FIT_PATH)
		model_fit.fit_to_size(model, float(_profile["height"]), float(_profile["length"]))
		# The imported vehicle scenes face +Z while gameplay forward is -Z.
		model.rotation.y = PI

	_hitbox = CombatHitbox.new()
	var hit_shape := BoxShape3D.new()
	hit_shape.size = Vector3(2.25, 1.55, 4.45)
	_hitbox.configure(self, "vehicle", 1.0, hit_shape, Vector3(0, 0.85, 0))
	add_child(_hitbox)

func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.position = Vector3(0, 2.1, 0.5)
	_camera_pivot.rotation.x = deg_to_rad(-12.0)
	add_child(_camera_pivot)
	var spring_arm := SpringArm3D.new()
	spring_arm.spring_length = 5.5
	spring_arm.collision_mask = 1
	_camera_pivot.add_child(spring_arm)
	_chase_camera = Camera3D.new()
	_chase_camera.current = false
	spring_arm.add_child(_chase_camera)

func request_seat(actor: Node) -> bool:
	if not alive or driver or not actor:
		return false
	driver = actor
	# Taking the wheel cancels autonomous momentum so the car cannot drag the
	# player through an intersection during the camera/seat handoff.
	current_speed = 0.0
	velocity = Vector3.ZERO
	if actor.has_method("enter_vehicle"):
		actor.enter_vehicle(self, "driver")
	return true

func get_open_seat_for(actor: Node) -> String:
	return "driver" if alive and not driver and actor and actor.get("is_human_player") == true else ""

func get_open_seat() -> String:
	return "driver" if alive and not driver else ""

func leave_seat(actor: Node, force := false) -> bool:
	if actor != driver:
		return false
	var exit_position := global_position + global_transform.basis.x * -2.0 + Vector3.UP * 0.9
	driver = null
	if actor.has_method("leave_vehicle"):
		actor.leave_vehicle(exit_position, force)
	_resume_nearest_route()
	return true

func activate_driver_camera(active: bool) -> void:
	if not _chase_camera:
		return
	_chase_camera.current = active
	if active:
		_camera_pivot.rotation = Vector3(deg_to_rad(-12.0), 0, 0)

func get_shot_exclusions() -> Array[RID]:
	return [get_rid(), _hitbox.get_rid()]

func set_network_driver_input(value: Vector3) -> void:
	network_driver_input = Vector3(clampf(value.x, -1.0, 1.0), clampf(value.y, -1.0, 1.0), 1.0 if value.z > 0.5 else 0.0)

func get_interaction_label() -> String:
	return "HIJACK %s" % vehicle_display_name.to_upper()

func _sync_driver() -> void:
	if driver and is_instance_valid(driver):
		driver.global_position = global_position + Vector3.UP * 0.8

func _resume_nearest_route() -> void:
	var nearest_index := 0
	var nearest_distance := INF
	for index in route.size():
		var distance := global_position.distance_squared_to(route[index])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	route_index = nearest_index

func _create_occupant_visual(_seat: String, _actor: Node) -> void:
	pass

func _remove_occupant_visual(_seat: String) -> void:
	pass

func _start_engine() -> void:
	pass

func _stop_engine() -> void:
	pass

func _apply_material_override(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_apply_material_override(child, material)

func _box_mesh(size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.position = local_position
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material = material
	instance.mesh = mesh
	return instance

func _update_impact_cooldowns(delta: float) -> void:
	for victim_id in _impact_cooldowns.keys():
		_impact_cooldowns[victim_id] = float(_impact_cooldowns[victim_id]) - delta
		if float(_impact_cooldowns[victim_id]) <= 0.0:
			_impact_cooldowns.erase(victim_id)

func _is_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
