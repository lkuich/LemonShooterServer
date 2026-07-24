extends RigidBody3D

const AXE_MODEL_PATH := "res://models/axe/model.glb"
const THROW_SOUND_PATH := "res://sounds/sfx/throw.mp3"
const IMPACT_SOUND_PATH := "res://sounds/sfx/knife-impact.mp3"

var thrower: Node
var stuck := false
var lifetime := 8.0
var model_root: Node3D
var throw_audio: AudioStreamPlayer3D
var impact_audio: AudioStreamPlayer3D
var pickup_area: Area3D
var network_cosmetic := false
var has_ricocheted := false
var ricochet_cooldown := 0.0
var settle_time := 0.0

func _ready() -> void:
	add_to_group("physics_projectiles")
	name = "ThrowingAxe"
	mass = 0.7
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = 32
	collision_mask = 1 | 2 | 4
	var physics_material := PhysicsMaterial.new()
	physics_material.bounce = 0.72
	physics_material.friction = 0.22
	physics_material.rough = false
	physics_material.absorbent = false
	physics_material_override = physics_material
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# The axe rotates in its local Y/Z plane, with the thin edge on local X.
	shape.size = Vector3(0.12, 0.70, 0.30)
	collision.shape = shape
	add_child(collision)
	model_root = Node3D.new()
	model_root.name = "AxeModel"
	model_root.scale = Vector3.ONE * 0.22
	model_root.rotation_degrees.y = 90.0
	add_child(model_root)
	if not DedicatedServer.active:
		var axe_scene := load(AXE_MODEL_PATH) as PackedScene
		if axe_scene:
			model_root.add_child(axe_scene.instantiate())
	throw_audio = _audio_player("ThrowAudio", THROW_SOUND_PATH, -2.0)
	impact_audio = _audio_player("ImpactAudio", IMPACT_SOUND_PATH, -1.0)
	pickup_area = Area3D.new()
	pickup_area.name = "PickupArea"
	pickup_area.collision_layer = 0
	pickup_area.collision_mask = 2
	pickup_area.monitoring = false
	var pickup_collision := CollisionShape3D.new()
	var pickup_shape := SphereShape3D.new()
	pickup_shape.radius = 0.75
	pickup_collision.shape = pickup_shape
	pickup_area.add_child(pickup_collision)
	add_child(pickup_area)
	pickup_area.body_entered.connect(_on_pickup_body_entered)
	body_entered.connect(_on_body_entered)

func launch(owner: Node, start_position: Vector3, launch_velocity: Vector3, spin_axis: Vector3, excluded_bodies: Array[PhysicsBody3D] = []) -> void:
	thrower = owner
	global_position = start_position
	var flight_direction := launch_velocity.normalized()
	var local_x := spin_axis.normalized()
	var local_z := -flight_direction
	var local_y := local_z.cross(local_x).normalized()
	local_x = local_y.cross(local_z).normalized()
	global_basis = Basis(local_x, local_y, local_z)
	linear_velocity = launch_velocity
	angular_velocity = spin_axis.normalized() * 15.0
	for body in excluded_bodies:
		if is_instance_valid(body):
			add_collision_exception_with(body)
	throw_audio.play()

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if stuck:
		return
	ricochet_cooldown = maxf(ricochet_cooldown - delta, 0.0)
	if has_ricocheted and (sleeping or (linear_velocity.length() < 1.15 and angular_velocity.length() < 2.5)):
		settle_time += delta
		if settle_time >= 0.55:
			_settle_for_pickup()
	else:
		settle_time = 0.0

func _on_body_entered(body: Node) -> void:
	if stuck or body == thrower:
		return
	# Human players and combat bots expose this property. Character impacts
	# embed the axe; every non-character collision keeps the rigid body live so
	# the physics material can produce wall, floor, prop, and vehicle ricochets.
	if body.get("is_human_player") == null:
		_ricochet(body)
		return
	stuck = true
	impact_audio.pitch_scale = 1.0
	impact_audio.play()
	var impact_direction := linear_velocity.normalized()
	if network_cosmetic:
		pass
	elif body.has_method("apply_damage"):
		body.apply_damage(9999.0, global_position, thrower)
	elif body.has_method("apply_hit"):
		body.apply_hit(9999.0, global_position, -impact_direction, thrower)
	_settle_for_pickup()

func _ricochet(body: Node) -> void:
	has_ricocheted = true
	settle_time = 0.0
	# Once the axe has genuinely struck something, its thrower may catch it while
	# it is still airborne. Other combatants can only collect it after it settles.
	if not network_cosmetic and is_instance_valid(pickup_area):
		pickup_area.set_deferred("monitoring", true)
	if ricochet_cooldown <= 0.0:
		ricochet_cooldown = 0.09
		impact_audio.pitch_scale = randf_range(1.08, 1.24)
		impact_audio.play()
	if network_cosmetic:
		return
	var impact_direction := linear_velocity.normalized()
	if body.has_method("apply_damage"):
		body.apply_damage(100.0, global_position, thrower)
	elif body.has_method("apply_hit"):
		body.apply_hit(100.0, global_position, -impact_direction, thrower)

func _settle_for_pickup() -> void:
	if stuck and freeze:
		return
	stuck = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	collision_layer = 0
	collision_mask = 0
	lifetime = 5.0
	_enable_pickup_after_delay()

func apply_explosion_impulse(impulse_velocity: Vector3) -> void:
	stuck = false
	has_ricocheted = true
	settle_time = 0.0
	lifetime = maxf(lifetime, 4.0)
	freeze = false
	sleeping = false
	collision_layer = 32
	collision_mask = 1 | 2 | 4
	if pickup_area:
		pickup_area.set_deferred("monitoring", false)
	linear_velocity += impulse_velocity
	angular_velocity += Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))

func _enable_pickup_after_delay() -> void:
	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(pickup_area) and stuck:
		pickup_area.set_deferred("monitoring", true)

func _on_pickup_body_entered(body: Node) -> void:
	if network_cosmetic or not body.has_method("collect_throwing_axe"):
		return
	var can_collect := stuck or (has_ricocheted and body == thrower)
	if can_collect and body.collect_throwing_axe():
		queue_free()

func _audio_player(node_name: String, stream_path: String, volume: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	if not DedicatedServer.active:
		player.stream = load(stream_path) as AudioStream
	player.bus = "SFX"
	player.volume_db = volume
	player.max_distance = 50.0
	player.max_polyphony = 4
	add_child(player)
	return player
