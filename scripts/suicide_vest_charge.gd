extends Node3D

signal detonated

const EXPLOSION_SOUND_PATH := "res://sounds/sfx/grenade_explosion.mp3"
const WARNING_DELAY := 1.0
const BLAST_RADIUS := 18.0
const LETHAL_DAMAGE := 10000.0

var wearer: Node3D
var authoritative := true
var elapsed := 0.0
var exploded := false
var warning_audio: AudioStreamPlayer3D
var explosion_audio: AudioStreamPlayer3D

func _ready() -> void:
	name = "SuicideVestCharge"
	explosion_audio = AudioStreamPlayer3D.new()
	if not DedicatedServer.active:
		explosion_audio.stream = load(EXPLOSION_SOUND_PATH) as AudioStream
	explosion_audio.bus = "SFX"
	explosion_audio.volume_db = 6.0
	explosion_audio.max_distance = 150.0
	add_child(explosion_audio)

func arm(owner: Node3D, apply_damage: bool) -> void:
	wearer = owner
	authoritative = apply_damage
	if is_instance_valid(wearer):
		global_position = wearer.global_position + Vector3.UP * 0.8
	if warning_audio:
		warning_audio.play()
	else:
		call_deferred("_play_warning")

func _play_warning() -> void:
	if warning_audio and not exploded:
		warning_audio.play()

func _process(delta: float) -> void:
	if exploded:
		return
	if is_instance_valid(wearer):
		global_position = wearer.global_position + Vector3.UP * 0.8
	elapsed += delta
	if elapsed >= WARNING_DELAY:
		_explode()

func _explode() -> void:
	if exploded:
		return
	exploded = true
	if warning_audio:
		warning_audio.stop()
	explosion_audio.play()
	if authoritative:
		_damage_everyone_nearby()
	_build_explosion_effect()
	detonated.emit()
	await get_tree().create_timer(3.0).timeout
	queue_free()

func _damage_everyone_nearby() -> void:
	var blast_shape := SphereShape3D.new()
	blast_shape.radius = BLAST_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = blast_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 1 | 2 | 4 | 8
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results := get_world_3d().direct_space_state.intersect_shape(query, 256)
	var damaged_targets := {}
	# The wearer may have collision disabled while occupying a vehicle, so damage
	# them explicitly instead of relying on the overlap query to find them.
	if is_instance_valid(wearer) and wearer.has_method("apply_damage"):
		damaged_targets[wearer.get_instance_id()] = true
		if wearer.has_method("apply_explosion_damage"):
			wearer.apply_explosion_damage(LETHAL_DAMAGE, global_position, null, 1.0)
		else:
			wearer.apply_damage(LETHAL_DAMAGE, global_position, null)
	for result in results:
		var target: Node = result["collider"] as Node
		if target and target.get("damage_owner") != null:
			target = target.get("damage_owner") as Node
		if not target or target == self or damaged_targets.has(target.get_instance_id()):
			continue
		if not target.has_method("apply_damage") and not target.has_method("apply_hit"):
			continue
		var target_position := global_position
		if target is Node3D:
			target_position = target.global_position + Vector3.UP * 0.45
		if global_position.distance_to(target_position) > BLAST_RADIUS:
			continue
		damaged_targets[target.get_instance_id()] = true
		var attacker: Node = wearer
		if target == wearer:
			attacker = null
		if target.has_method("apply_damage"):
			if target.has_method("apply_explosion_damage"):
				target.apply_explosion_damage(LETHAL_DAMAGE, global_position, attacker, 1.0)
			else:
				target.apply_damage(LETHAL_DAMAGE, global_position, attacker)
		else:
			var hit_normal := (target_position - global_position).normalized()
			target.apply_hit(LETHAL_DAMAGE, target_position, hit_normal, attacker)

func _build_explosion_effect() -> void:
	if DedicatedServer.active:
		return
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.28, 0.03, 0.88)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.08, 0.01)
	material.emission_energy_multiplier = 8.0
	for index in 3:
		var flash := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.8
		mesh.height = 1.6
		mesh.material = material
		flash.mesh = mesh
		flash.scale = Vector3.ONE * (1.0 + index * 0.3)
		add_child(flash)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(flash, "scale", Vector3.ONE * (12.0 + index * 3.0), 0.42 + index * 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(flash, "transparency", 1.0, 0.62 + index * 0.08)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff5522")
	light.light_energy = 28.0
	light.omni_range = 28.0
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.75)
