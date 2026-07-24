extends CharacterBody3D

signal destroyed(vehicle: Node)
signal seat_changed

const CombatHitbox = preload("res://scripts/combat_hitbox.gd")
const HUMMER_MODEL_PATH := "res://models/hummer/model.glb"
const SOLDIER_RIG_PATH := "res://scripts/soldier_rig.gd"
const ENGINE_START_SOUND_PATH := "res://sounds/sfx/engine_start.mp3"
const ENGINE_RUNNING_SOUND_PATH := "res://sounds/sfx/engine_running.mp3"
const KILL_SPLAT_SOUND_PATH := "res://sounds/sfx/kill-splat.mp3"

const DRIVER_SEAT := "driver"
const PASSENGER_SEAT := "passenger"
const MAX_HEALTH := 2000.0
const MAX_FORWARD_SPEED := 25.0
const MAX_REVERSE_SPEED := 9.0
const ACCELERATION := 11.0
const BRAKE_FORCE := 17.0
const COAST_DRAG := 3.5
const LETHAL_IMPACT_SPEED := 8.0
const LETHAL_IMPACT_DAMAGE := 10000.0
const DRIVER_SEAT_POSITION := Vector3(-0.55, 0.90, 0.15)
const PASSENGER_SEAT_POSITION := Vector3(0.55, 0.90, 0.15)
const HUMAN_OCCUPANT_LAYER := 1 << 19
const PORTAL_AIRBORNE_TIME := 0.35
const AIR_DRAG := 0.45
const UPRIGHT_RECOVERY_SPEED := 2.8
const CRUSH_IMPACT_SPEED := 2.5
const SUPPORT_PROBE_DEPTH := 1.45
const SUPPORT_OFFSETS := [
	Vector3(-1.05, 0.35, -1.8), Vector3(1.05, 0.35, -1.8),
	Vector3(-1.05, 0.35, 1.8), Vector3(1.05, 0.35, 1.8)
]

var driver: Node
var passenger: Node
var max_health := MAX_HEALTH
var health := MAX_HEALTH
var alive := true
var current_speed := 0.0
var ai_drive_target := Vector3.ZERO
var has_ai_drive_target := false
var model_root: Node3D
var body_collision: CollisionShape3D
var damage_hitbox: Area3D
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var chase_camera: Camera3D
var impact_cooldowns: Dictionary = {}
var routing_occupant_hit := false
var occupant_visuals: Dictionary = {}
var engine_start_audio: AudioStreamPlayer3D
var engine_running_audio: AudioStreamPlayer3D
var engine_sequence := 0
var roadkill_audio: AudioStreamPlayer3D
var network_mode := false
var network_driver_input := Vector3.ZERO
var network_id := 0
var portal_airborne_time := 0.0
var tipping_velocity := Vector2.ZERO

func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	_build_body()
	if not NetworkSession.is_dedicated_server:
		_build_camera()
	_build_engine_audio()

func _build_body() -> void:
	body_collision = CollisionShape3D.new()
	var chassis := BoxShape3D.new()
	chassis.size = Vector3(2.55, 1.8, 4.6)
	body_collision.shape = chassis
	body_collision.position.y = 0.9
	add_child(body_collision)
	model_root = Node3D.new()
	model_root.name = "HummerModel"
	model_root.rotation_degrees.y = -90.0
	add_child(model_root)
	if not NetworkSession.is_dedicated_server:
		var hummer_model = load(HUMMER_MODEL_PATH)
		model_root.add_child(hummer_model.instantiate())
	var hit_shape := BoxShape3D.new()
	hit_shape.size = Vector3(2.65, 1.9, 4.7)
	damage_hitbox = CombatHitbox.new()
	damage_hitbox.configure(self, "vehicle", 1.0, hit_shape, Vector3(0, 0.95, 0))
	add_child(damage_hitbox)

func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "DriverCameraPivot"
	camera_pivot.position = Vector3(0, 2.35, 0.65)
	camera_pivot.rotation.x = deg_to_rad(-12.0)
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 6.0
	spring_arm.margin = 0.2
	spring_arm.collision_mask = 1
	camera_pivot.add_child(spring_arm)
	chase_camera = Camera3D.new()
	chase_camera.name = "DriverCamera"
	chase_camera.fov = 75.0
	chase_camera.current = false
	spring_arm.add_child(chase_camera)

func _input(event: InputEvent) -> void:
	if not alive or not driver or not _is_human(driver) or not chase_camera.current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * driver.mouse_sensitivity
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - event.relative.y * driver.mouse_sensitivity, deg_to_rad(-55), deg_to_rad(20))

func _physics_process(delta: float) -> void:
	_update_impact_cooldowns(delta)
	_sync_occupants()
	if engine_running_audio and engine_running_audio.playing:
		var engine_load := clampf(absf(current_speed) / MAX_FORWARD_SPEED, 0.0, 1.0)
		engine_running_audio.pitch_scale = lerpf(0.88, 1.24, engine_load)
	if not alive:
		velocity.x = move_toward(velocity.x, 0.0, delta * COAST_DRAG)
		velocity.z = move_toward(velocity.z, 0.0, delta * COAST_DRAG)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	if network_mode and not multiplayer.is_server():
		velocity = Vector3.ZERO
		_sync_occupants()
		return
	var throttle := 0.0
	var steering := 0.0
	var braking := false
	if driver:
		if _is_human(driver):
			if network_mode:
				throttle = network_driver_input.x
				steering = network_driver_input.y
				braking = network_driver_input.z > 0.5
			else:
				throttle = Input.get_axis("move_back", "move_forward")
				steering = Input.get_axis("move_left", "move_right")
				braking = Input.is_action_pressed("jump")
		else:
			var ai_input := _get_ai_input()
			throttle = ai_input.x
			steering = ai_input.y
			braking = ai_input.z > 0.5
	portal_airborne_time = maxf(portal_airborne_time - delta, 0.0)
	var support := _sample_ground_support()
	var falling := portal_airborne_time > 0.0 or not is_on_floor() or int(support["count"]) < 3
	if falling:
		_apply_falling_motion(delta, support)
	else:
		_apply_drive(throttle, steering, braking, delta)
	var landing_speed := maxf(-velocity.y, 0.0)
	var impact_speed := Vector2(velocity.x, velocity.z).length() if falling else absf(current_speed)
	var drive_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var drive_speed := current_speed
	move_and_slide()
	_settle_after_fall(delta, falling, landing_speed)
	if _process_road_impacts(impact_speed, landing_speed):
		# CharacterBody collision recovery shortens velocity when it meets another
		# body. A roadkill should not act like a solid crash after the victim dies.
		velocity.x = drive_velocity.x
		velocity.z = drive_velocity.z
		current_speed = drive_speed
	_sync_occupants()

func begin_portal_travel(outgoing_velocity: Vector3, outgoing_basis: Basis) -> void:
	velocity = outgoing_velocity
	global_basis = outgoing_basis.orthonormalized()
	portal_airborne_time = PORTAL_AIRBORNE_TIME

func _apply_falling_motion(delta: float, support: Dictionary) -> void:
	velocity += get_gravity() * delta
	velocity.x = move_toward(velocity.x, 0.0, AIR_DRAG * delta)
	velocity.z = move_toward(velocity.z, 0.0, AIR_DRAG * delta)
	var support_count := int(support["count"])
	if support_count > 0 and support_count < 3:
		var local_support := global_basis.inverse() * (support["average"] as Vector3 - global_position)
		var target_tipping := Vector2(clampf(-local_support.z * 0.85, -1.8, 1.8), clampf(local_support.x * 0.85, -1.8, 1.8))
		tipping_velocity = tipping_velocity.lerp(target_tipping, minf(delta * 5.0, 1.0))
	else:
		tipping_velocity = tipping_velocity.lerp(Vector2.ZERO, minf(delta * 0.7, 1.0))
	rotation.x += tipping_velocity.x * delta
	rotation.z += tipping_velocity.y * delta

func _settle_after_fall(delta: float, was_falling: bool, landing_speed: float) -> void:
	if not is_on_floor() or int(_sample_ground_support()["count"]) < 3:
		return
	if was_falling:
		portal_airborne_time = 0.0
		var landing_damping := clampf(1.0 - landing_speed * 0.012, 0.68, 0.96)
		velocity.x *= landing_damping
		velocity.z *= landing_damping
	tipping_velocity = tipping_velocity.lerp(Vector2.ZERO, minf(delta * 8.0, 1.0))
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

func _apply_drive(throttle: float, steering: float, braking: bool, delta: float) -> void:
	var forward := -global_transform.basis.z
	current_speed = Vector2(velocity.x, velocity.z).dot(Vector2(forward.x, forward.z))
	if braking:
		current_speed = move_toward(current_speed, 0.0, BRAKE_FORCE * delta)
	elif absf(throttle) > 0.05:
		var target_speed := MAX_FORWARD_SPEED if throttle > 0.0 else -MAX_REVERSE_SPEED
		current_speed = move_toward(current_speed, target_speed, ACCELERATION * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, COAST_DRAG * delta)
	if absf(current_speed) > 0.15 and absf(steering) > 0.02:
		var speed_ratio := clampf(absf(current_speed) / MAX_FORWARD_SPEED, 0.0, 1.0)
		var turn_rate := lerpf(1.65, 0.55, speed_ratio)
		rotation.y -= steering * turn_rate * delta * signf(current_speed)
	forward = -global_transform.basis.z
	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

func _get_ai_input() -> Vector3:
	if not has_ai_drive_target:
		return Vector3.ZERO
	var local_target := to_local(ai_drive_target)
	var distance := Vector2(local_target.x, local_target.z).length()
	var steering := clampf(local_target.x / maxf(absf(local_target.z), 1.0), -1.0, 1.0)
	var throttle := 1.0 if local_target.z < 1.5 else -0.65
	var braking := 1.0 if distance < 4.0 and absf(current_speed) > 5.0 else 0.0
	return Vector3(throttle, steering, braking)

func set_ai_drive_target(target: Vector3) -> void:
	ai_drive_target = target
	has_ai_drive_target = true

func clear_ai_drive_target() -> void:
	has_ai_drive_target = false

func set_network_driver_input(value: Vector3) -> void:
	network_driver_input = Vector3(clampf(value.x, -1.0, 1.0), clampf(value.y, -1.0, 1.0), 1.0 if value.z > 0.5 else 0.0)

func request_seat(actor: Node) -> bool:
	if not alive or not actor:
		return false
	if actor == driver or actor == passenger:
		return false
	var seat := get_open_seat_for(actor)
	if seat.is_empty():
		return false
	if seat == DRIVER_SEAT:
		driver = actor
	else:
		passenger = actor
	if actor.has_method("enter_vehicle"):
		actor.enter_vehicle(self, seat)
	_create_occupant_visual(seat, actor)
	if seat == DRIVER_SEAT:
		_start_engine()
	seat_changed.emit()
	return true

func get_open_seat() -> String:
	if not driver:
		return DRIVER_SEAT
	if not passenger:
		return PASSENGER_SEAT
	return ""

func get_open_seat_for(actor: Node) -> String:
	if not alive or not actor or actor == driver or actor == passenger:
		return ""
	var occupant: Node = driver if driver else passenger
	if occupant and occupant.get("team_id") != actor.get("team_id"):
		return ""
	return get_open_seat()

func leave_seat(actor: Node, force := false) -> bool:
	var seat := DRIVER_SEAT if actor == driver else (PASSENGER_SEAT if actor == passenger else "")
	if seat.is_empty():
		return false
	var exit_position = _find_exit_position(actor, seat)
	if exit_position == null and not force:
		return false
	if exit_position == null:
		exit_position = global_position + global_transform.basis.x * (2.0 if seat == PASSENGER_SEAT else -2.0) + Vector3.UP
	if actor == driver:
		driver = null
		clear_ai_drive_target()
		_stop_engine()
	else:
		passenger = null
	_remove_occupant_visual(seat)
	if actor.has_method("leave_vehicle"):
		actor.leave_vehicle(exit_position, force)
	seat_changed.emit()
	return true

func eject_all() -> void:
	if driver:
		leave_seat(driver, true)
	if passenger:
		leave_seat(passenger, true)

func activate_driver_camera(active: bool) -> void:
	if not chase_camera:
		return
	chase_camera.current = active
	if active:
		camera_pivot.rotation = Vector3(deg_to_rad(-12), 0, 0)

func get_seat_transform(seat: String) -> Transform3D:
	var local_position := DRIVER_SEAT_POSITION if seat == DRIVER_SEAT else PASSENGER_SEAT_POSITION
	return global_transform * Transform3D(Basis.IDENTITY, local_position)

func get_shot_exclusions() -> Array[RID]:
	return [get_rid(), damage_hitbox.get_rid()]

func apply_occupant_damage(amount: float, attacker: Node) -> void:
	routing_occupant_hit = true
	apply_damage(amount, global_position, attacker)
	routing_occupant_hit = false

func apply_damage(amount: float, _source_position: Vector3, attacker: Node) -> bool:
	return receive_zone_hit(amount, "vehicle", global_position, Vector3.UP, attacker)

func receive_zone_hit(amount: float, _zone: String, _hit_position: Vector3, _hit_normal: Vector3, attacker: Node) -> bool:
	if network_mode and not multiplayer.is_server():
		var scene := get_tree().current_scene
		if scene and scene.has_method("request_network_vehicle_hit"):
			var attacker_id := int(attacker.get("entity_id")) if attacker and attacker.get("entity_id") != null else 0
			scene.request_network_vehicle_hit(attacker_id, network_id, amount, _hit_position, _hit_normal)
		return false
	if not alive:
		return false
	health = maxf(health - amount, 0.0)
	if not routing_occupant_hit:
		var occupants: Array[Node] = []
		if driver:
			occupants.append(driver)
		if passenger:
			occupants.append(passenger)
		if not occupants.is_empty():
			var protected_occupant: Node = occupants.pick_random()
			if protected_occupant.has_method("receive_vehicle_protected_damage"):
				protected_occupant.receive_vehicle_protected_damage(amount, global_position, attacker)
	if health <= 0.0:
		_destroy()
		return true
	return false

func get_team_id() -> int:
	var occupant: Node = driver if driver else passenger
	return int(occupant.get("team_id")) if occupant else -1

func _destroy() -> void:
	alive = false
	current_speed = 0.0
	damage_hitbox.collision_layer = 0
	activate_driver_camera(false)
	eject_all()
	var tint := StandardMaterial3D.new()
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.albedo_color = Color(0.05, 0.05, 0.05, 0.45)
	_apply_overlay(model_root, tint)
	destroyed.emit(self)

func _apply_overlay(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_overlay = material
	for child in node.get_children():
		_apply_overlay(child, material)

func _sync_occupants() -> void:
	if driver and is_instance_valid(driver):
		driver.global_transform = get_seat_transform(DRIVER_SEAT)
	if passenger and is_instance_valid(passenger):
		passenger.global_transform = get_seat_transform(PASSENGER_SEAT)

func _create_occupant_visual(seat: String, actor: Node) -> void:
	_remove_occupant_visual(seat)
	if NetworkSession.is_dedicated_server:
		return
	var visual_root := Node3D.new()
	visual_root.name = "%sOccupant" % seat.capitalize()
	visual_root.position = DRIVER_SEAT_POSITION if seat == DRIVER_SEAT else PASSENGER_SEAT_POSITION
	add_child(visual_root)
	var soldier_rig_script = load(SOLDIER_RIG_PATH)
	var rig = soldier_rig_script.new()
	rig.team_color = Color("#3975a8") if actor.get("team_id") == 0 else Color("#a84d43")
	var weapon_id := "ak47"
	if actor.get("weapon_type") != null:
		weapon_id = str(actor.get("weapon_type"))
	elif actor.get("equipped_weapon_id") != null:
		weapon_id = str(actor.get("equipped_weapon_id"))
	elif actor.get("rifle") != null:
		weapon_id = str(actor.get("rifle").get("current_weapon_id"))
	rig.set_equipped_weapon(weapon_id)
	visual_root.add_child(rig)
	rig.set_seated_pose()
	# Apply this after the pose, whose reset step restores the rig origin.
	rig.position.y = -1.21
	_set_occupant_render_layer(visual_root, HUMAN_OCCUPANT_LAYER if _is_human(actor) else 1)
	occupant_visuals[seat] = visual_root

func _remove_occupant_visual(seat: String) -> void:
	if not occupant_visuals.has(seat):
		return
	var visual: Node = occupant_visuals[seat]
	occupant_visuals.erase(seat)
	if is_instance_valid(visual):
		visual.queue_free()

func _set_occupant_render_layer(node: Node, layer_mask: int) -> void:
	if node is MeshInstance3D:
		node.layers = layer_mask
	for child in node.get_children():
		_set_occupant_render_layer(child, layer_mask)

func _build_engine_audio() -> void:
	engine_start_audio = AudioStreamPlayer3D.new()
	engine_start_audio.name = "EngineStartAudio"
	if not NetworkSession.is_dedicated_server:
		engine_start_audio.stream = load(ENGINE_START_SOUND_PATH)
	engine_start_audio.bus = "SFX"
	engine_start_audio.volume_db = -7.0
	engine_start_audio.max_distance = 70.0
	add_child(engine_start_audio)
	engine_running_audio = AudioStreamPlayer3D.new()
	engine_running_audio.name = "EngineRunningAudio"
	if not NetworkSession.is_dedicated_server:
		var running_source := load(ENGINE_RUNNING_SOUND_PATH) as AudioStreamMP3
		var running_stream: AudioStreamMP3 = running_source.duplicate()
		running_stream.loop = true
		engine_running_audio.stream = running_stream
	engine_running_audio.bus = "SFX"
	engine_running_audio.volume_db = -12.0
	engine_running_audio.max_distance = 75.0
	add_child(engine_running_audio)
	roadkill_audio = AudioStreamPlayer3D.new()
	roadkill_audio.name = "RoadkillAudio"
	if not NetworkSession.is_dedicated_server:
		roadkill_audio.stream = load(KILL_SPLAT_SOUND_PATH)
	roadkill_audio.bus = "SFX"
	roadkill_audio.volume_db = -1.0
	roadkill_audio.max_distance = 60.0
	roadkill_audio.max_polyphony = 2
	add_child(roadkill_audio)

func _start_engine() -> void:
	if NetworkSession.is_dedicated_server:
		return
	engine_sequence += 1
	var sequence := engine_sequence
	engine_running_audio.stop()
	engine_start_audio.play()
	await engine_start_audio.finished
	if sequence == engine_sequence and alive and driver:
		engine_running_audio.play()

func _stop_engine() -> void:
	engine_sequence += 1
	if engine_start_audio:
		engine_start_audio.stop()
	if engine_running_audio:
		engine_running_audio.stop()

func _find_exit_position(actor: Node, seat: String):
	var side := 1.0 if seat == PASSENGER_SEAT else -1.0
	var offsets := [Vector3(side * 2.1, 0.9, 0), Vector3(-side * 2.1, 0.9, 0), Vector3(0, 0.9, 2.9), Vector3(0, 0.9, -2.9)]
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	for offset in offsets:
		var candidate: Vector3 = global_transform * offset
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, candidate)
		query.collision_mask = 1 | 2 | 4
		query.exclude = [get_rid(), actor.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return candidate
	return null

func _process_road_impacts(impact_speed: float, downward_speed := 0.0) -> bool:
	if impact_speed < 1.0 and downward_speed < CRUSH_IMPACT_SPEED:
		return false
	var preserve_vehicle_motion := false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var victim := collision.get_collider()
		if not victim or victim == driver or victim == passenger:
			continue
		if victim is RigidBody3D and victim.is_in_group("physics_objects"):
			if impact_cooldowns.get(victim.get_instance_id(), 0.0) > 0.0:
				continue
			var drive_direction := Vector3(velocity.x, 0.0, velocity.z).normalized()
			if drive_direction.is_zero_approx():
				drive_direction = -global_transform.basis.z * signf(current_speed if not is_zero_approx(current_speed) else 1.0)
			var prop_mass := maxf(victim.mass, 0.25)
			var impulse := drive_direction * impact_speed * prop_mass * 1.25 + Vector3.UP * minf(impact_speed * prop_mass * 0.08, prop_mass * 2.0)
			victim.sleeping = false
			victim.apply_impulse(impulse, collision.get_position() - victim.global_position)
			impact_cooldowns[victim.get_instance_id()] = 0.18
			preserve_vehicle_motion = true
			continue
		if not victim.has_method("apply_vehicle_impact"):
			continue
		var crushing := downward_speed >= CRUSH_IMPACT_SPEED and collision.get_normal().dot(Vector3.UP) > 0.35
		if not crushing and not driver:
			continue
		if impact_cooldowns.get(victim.get_instance_id(), 0.0) > 0.0:
			continue
		var damage := 0.0
		if crushing:
			damage = LETHAL_IMPACT_DAMAGE
		elif impact_speed >= 4.0:
			damage = LETHAL_IMPACT_DAMAGE if impact_speed >= LETHAL_IMPACT_SPEED else clampf(15.0 + (impact_speed - 4.0) * 13.5, 15.0, 150.0)
		var victim_was_alive: bool = victim.get("alive") == true
		var attacker: Node = driver if driver else self
		if crushing:
			if victim.get("invulnerable_time") != null:
				victim.set("invulnerable_time", 0.0)
			if not driver:
				attacker = null
		var push_velocity := Vector3.DOWN * downward_speed if crushing else -global_transform.basis.z * maxf(impact_speed, 4.0)
		victim.apply_vehicle_impact(damage, push_velocity, attacker)
		preserve_vehicle_motion = preserve_vehicle_motion or (victim_was_alive and victim.get("alive") == false)
		_play_roadkill_sound(victim, damage)
		impact_cooldowns[victim.get_instance_id()] = 0.75
	return preserve_vehicle_motion

func _play_roadkill_sound(victim: Node, damage: float) -> void:
	if NetworkSession.is_dedicated_server:
		return
	if damage > 0.0 and victim.get("is_human_player") != null:
		roadkill_audio.play()

func _update_impact_cooldowns(delta: float) -> void:
	for instance_id in impact_cooldowns.keys():
		impact_cooldowns[instance_id] -= delta
		if impact_cooldowns[instance_id] <= 0.0:
			impact_cooldowns.erase(instance_id)

func _is_human(actor: Node) -> bool:
	return actor.get("is_human_player") == true
