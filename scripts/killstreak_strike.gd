extends Node3D

const AIRSTRIKE_SOUND_PATH := "res://sounds/sfx/grenade_explosion.mp3"
const NUKE_SOUND_PATH := "res://sounds/sfx/grenade_explosion.mp3"
const NUKE_DROP_DURATION := 18.25
const NUKE_SLOW_MOTION_WINDOW := 3.0

var owner_entity: Node
var cosmetic_only := false
var nuke_canvas: CanvasLayer
var nuke_countdown_card: PanelContainer
var nuke_countdown_label: Label
var nuke_flash: ColorRect
var shake_camera: Camera3D
var camera_base_h_offset := 0.0
var camera_base_v_offset := 0.0
var slow_motion_applied := false
var slow_motion_tree: SceneTree


func activate(owner: Node, target_position: Vector3, strike_type: String, cosmetic := false) -> bool:
	if strike_type == "nuke" and not get_tree().get_nodes_in_group("active_nuke_strike").is_empty():
		queue_free()
		return false
	owner_entity = owner
	cosmetic_only = cosmetic
	global_position = target_position
	if strike_type == "nuke":
		add_to_group("active_nuke_strike")
		_run_nuke()
	else:
		_run_airstrike()
	return true


func _run_airstrike() -> void:
	_play_spatial_sound(AIRSTRIKE_SOUND_PATH, 0.0, 120.0)
	await get_tree().create_timer(1.25).timeout
	var axis := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	for index in 6:
		var offset := axis * (float(index) - 2.5) * 2.8
		offset += Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		var impact := global_position + offset
		_spawn_blast_visual(impact, Color("#ff8a32"), 7.0)
		if not cosmetic_only:
			_damage_radius(impact, 7.0, 240.0)
		await get_tree().create_timer(0.18).timeout
	await get_tree().create_timer(1.5).timeout
	queue_free()


func _run_nuke() -> void:
	if not DedicatedServer.active:
		_play_global_sound(NUKE_SOUND_PATH)
		_spawn_warning_light()
		_build_nuke_overlay()
		shake_camera = get_viewport().get_camera_3d()
		if shake_camera:
			camera_base_h_offset = shake_camera.h_offset
			camera_base_v_offset = shake_camera.v_offset
	var deadline := Time.get_ticks_msec() + int(NUKE_DROP_DURATION * 1000.0)
	var remaining := NUKE_DROP_DURATION
	while remaining > 0.0 and is_inside_tree():
		remaining = maxf(float(deadline - Time.get_ticks_msec()) / 1000.0, 0.0)
		_update_nuke_countdown(remaining)
		if not DedicatedServer.active and remaining <= NUKE_SLOW_MOTION_WINDOW and not slow_motion_applied:
			_begin_nuke_slow_motion()
		_apply_countdown_shake(remaining)
		await get_tree().create_timer(0.05, true, false, true).timeout
	_end_nuke_slow_motion()
	_restore_camera_offset()
	if not DedicatedServer.active:
		_detonate_nuke_visuals()
	if not cosmetic_only:
		for target in get_tree().get_nodes_in_group("combatants"):
			if _is_nuke_target(target):
				var health_before = target.get("health")
				if target.get("invulnerable_time") != null:
					target.set("invulnerable_time", 0.0)
				target.set_meta("killstreak_exempt_death", true)
				var damage_result = target.apply_explosion_damage(10000.0, target.global_position + Vector3.UP * 20.0, owner_entity, 1.0)
				target.remove_meta("killstreak_exempt_death")
				_report_confirmed_damage(target, health_before, damage_result == true)
	if not DedicatedServer.active:
		_run_impact_shake()
	await get_tree().create_timer(3.0, true, false, true).timeout
	queue_free()


func _build_nuke_overlay() -> void:
	nuke_canvas = CanvasLayer.new()
	nuke_canvas.layer = 85
	add_child(nuke_canvas)
	nuke_flash = ColorRect.new()
	nuke_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nuke_flash.color = Color(1.0, 0.98, 0.82, 0.0)
	nuke_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nuke_canvas.add_child(nuke_flash)
	nuke_countdown_card = PanelContainer.new()
	nuke_countdown_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	nuke_countdown_card.position = Vector2(-138, 72)
	nuke_countdown_card.size = Vector2(276, 68)
	nuke_countdown_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.02, 0.012, 0.82)
	style.border_color = Color(1.0, 0.72, 0.18, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	nuke_countdown_card.add_theme_stylebox_override("panel", style)
	nuke_canvas.add_child(nuke_countdown_card)
	nuke_countdown_label = Label.new()
	nuke_countdown_label.text = "NUKE INBOUND"
	nuke_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nuke_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nuke_countdown_label.add_theme_font_size_override("font_size", 18)
	nuke_countdown_label.add_theme_color_override("font_color", Color("#ffd65a"))
	nuke_countdown_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	nuke_countdown_label.add_theme_constant_override("shadow_offset_x", 2)
	nuke_countdown_label.add_theme_constant_override("shadow_offset_y", 2)
	nuke_countdown_card.add_child(nuke_countdown_label)


func _update_nuke_countdown(remaining: float) -> void:
	if not nuke_countdown_label:
		return
	var display_time := "%04.1f" % remaining if remaining < 5.0 else "%02d" % int(ceil(remaining))
	nuke_countdown_label.text = "NUKE INBOUND\nIMPACT  %s" % display_time
	var urgency := clampf(1.0 - remaining / NUKE_DROP_DURATION, 0.0, 1.0)
	nuke_countdown_card.modulate = Color(1.0, 1.0 - urgency * 0.28, 1.0 - urgency * 0.55, 1.0)
	if remaining <= NUKE_SLOW_MOTION_WINDOW:
		nuke_countdown_card.scale = Vector2.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.018) * 0.035)


func _begin_nuke_slow_motion() -> void:
	if slow_motion_applied:
		return
	slow_motion_applied = true
	var tree := get_tree()
	slow_motion_tree = tree
	var active_count := int(tree.get_meta("nuke_slow_motion_count", 0))
	if active_count == 0:
		tree.set_meta("nuke_previous_time_scale", Engine.time_scale)
	tree.set_meta("nuke_slow_motion_count", active_count + 1)
	Engine.time_scale = minf(Engine.time_scale, 0.34)


func _end_nuke_slow_motion() -> void:
	if not slow_motion_applied or not slow_motion_tree:
		return
	slow_motion_applied = false
	var tree := slow_motion_tree
	var active_count := maxi(int(tree.get_meta("nuke_slow_motion_count", 1)) - 1, 0)
	tree.set_meta("nuke_slow_motion_count", active_count)
	if active_count == 0:
		Engine.time_scale = float(tree.get_meta("nuke_previous_time_scale", 1.0))
	slow_motion_tree = null


func _apply_countdown_shake(remaining: float) -> void:
	if not is_instance_valid(shake_camera):
		return
	var progress := clampf(1.0 - remaining / NUKE_DROP_DURATION, 0.0, 1.0)
	var amplitude := lerpf(0.002, 0.035, progress)
	if remaining <= NUKE_SLOW_MOTION_WINDOW:
		amplitude = lerpf(0.05, 0.16, 1.0 - remaining / NUKE_SLOW_MOTION_WINDOW)
	shake_camera.h_offset = camera_base_h_offset + randf_range(-amplitude, amplitude)
	shake_camera.v_offset = camera_base_v_offset + randf_range(-amplitude, amplitude)


func _restore_camera_offset() -> void:
	if is_instance_valid(shake_camera):
		shake_camera.h_offset = camera_base_h_offset
		shake_camera.v_offset = camera_base_v_offset


func _run_impact_shake() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var base_h := camera.h_offset
	var base_v := camera.v_offset
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline and is_instance_valid(camera):
		var remaining := float(deadline - Time.get_ticks_msec()) / 1500.0
		var amplitude := 0.34 * remaining * remaining
		camera.h_offset = base_h + randf_range(-amplitude, amplitude)
		camera.v_offset = base_v + randf_range(-amplitude, amplitude)
		await get_tree().create_timer(0.025, true, false, true).timeout
	if is_instance_valid(camera):
		camera.h_offset = base_h
		camera.v_offset = base_v


func _detonate_nuke_visuals() -> void:
	if nuke_countdown_card:
		nuke_countdown_card.hide()
	if nuke_flash:
		nuke_flash.color.a = 1.0
		var flash_tween := nuke_flash.create_tween()
		flash_tween.tween_property(nuke_flash, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_spawn_blast_visual(global_position, Color("#fffceb"), 58.0)
	_spawn_blast_visual(global_position + Vector3.UP * 5.0, Color("#ffd66b"), 44.0)
	_spawn_blast_visual(global_position + Vector3.UP * 14.0, Color("#ff9a3d"), 30.0)
	_spawn_nuke_shockwave()
	var light := DirectionalLight3D.new()
	light.light_color = Color("#fff4bf")
	light.light_energy = 18.0
	add_child(light)
	var light_tween := light.create_tween()
	light_tween.tween_property(light, "light_energy", 0.0, 1.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	light_tween.tween_callback(light.queue_free)


func _spawn_nuke_shockwave() -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.8
	mesh.outer_radius = 1.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.88, 0.52, 0.88)
	material.emission_enabled = true
	material.emission = Color("#ffd76d")
	material.emission_energy_multiplier = 8.0
	mesh.material = material
	ring.mesh = mesh
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3.UP * 0.35
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 52.0, 1.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, 1.25)
	tween.chain().tween_callback(ring.queue_free)


func _exit_tree() -> void:
	_end_nuke_slow_motion()
	_restore_camera_offset()


func _is_enemy_target(target: Node) -> bool:
	if not is_instance_valid(target) or target == owner_entity or target.get("alive") != true:
		return false
	return target.has_method("apply_explosion_damage")


func _is_nuke_target(target: Node) -> bool:
	return is_instance_valid(target) and target != owner_entity and target.get("alive") == true and target.has_method("apply_explosion_damage")


func _damage_radius(origin: Vector3, radius: float, maximum_damage: float) -> void:
	if owner_entity and owner_entity.get("explosive_damage_multiplier") != null:
		maximum_damage *= float(owner_entity.get("explosive_damage_multiplier"))
	for target in get_tree().get_nodes_in_group("combatants"):
		if not _is_enemy_target(target) or target is not Node3D:
			continue
		var distance := origin.distance_to(target.global_position)
		if distance > radius:
			continue
		var damage := maximum_damage * clampf(1.0 - distance / radius, 0.35, 1.0)
		var health_before = target.get("health")
		var damage_result = target.apply_explosion_damage(damage, origin, owner_entity, clampf(1.0 - distance / radius, 0.0, 1.0))
		_report_confirmed_damage(target, health_before, damage_result == true)


func _report_confirmed_damage(target: Node, health_before, destroyed: bool) -> void:
	var health_after = target.get("health")
	if not destroyed and (health_before == null or health_after == null or float(health_after) >= float(health_before)):
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("indirect_hit_confirmed"):
		scene.indirect_hit_confirmed(owner_entity, destroyed)
	elif owner_entity and owner_entity.has_method("show_indirect_hitmarker"):
		owner_entity.show_indirect_hitmarker(destroyed)


func _play_spatial_sound(stream_path: String, volume_db: float, max_distance: float) -> void:
	if DedicatedServer.active:
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = load(stream_path) as AudioStream
	audio.bus = "SFX"
	audio.volume_db = volume_db
	audio.max_distance = max_distance
	add_child(audio)
	audio.play()


func _play_global_sound(stream_path: String) -> void:
	if DedicatedServer.active:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = load(stream_path) as AudioStream
	audio.bus = "SFX"
	add_child(audio)
	audio.play()


func _spawn_warning_light() -> void:
	if DedicatedServer.active:
		return
	var light := DirectionalLight3D.new()
	light.light_color = Color("#ffe66d")
	light.light_energy = 0.4
	add_child(light)
	var tween := create_tween().set_loops(int(NUKE_DROP_DURATION * 2.0))
	tween.tween_property(light, "light_energy", 2.5, 0.25)
	tween.tween_property(light, "light_energy", 0.25, 0.25)


func _spawn_blast_visual(position: Vector3, color: Color, scale_size: float) -> void:
	if DedicatedServer.active:
		return
	var blast := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, 0.88)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 5.0
	mesh.material = material
	blast.mesh = mesh
	get_tree().current_scene.add_child(blast)
	blast.global_position = position + Vector3.UP * 0.5
	var tween := blast.create_tween().set_parallel(true)
	tween.tween_property(blast, "scale", Vector3.ONE * scale_size, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(blast, "transparency", 1.0, 0.65)
	tween.chain().tween_callback(blast.queue_free)
