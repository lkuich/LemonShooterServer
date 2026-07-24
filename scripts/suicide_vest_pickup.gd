extends Area3D

signal collected(collector: Node)

const C4_MODEL_PATH := "res://models/c4/model.glb"

var visual_root: Node3D
var was_collected := false
var pickup_kind := "suicide_vest"

func _ready() -> void:
	add_to_group("collectible_pickups")
	name = "SuicideVestPickup"
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	_build_pickup()

func _process(delta: float) -> void:
	visual_root.rotation.y += delta * 0.7
	visual_root.position.y = 0.24 + sin(Time.get_ticks_msec() * 0.0032) * 0.07
	if not was_collected:
		_check_nearby_players()

func _build_pickup() -> void:
	visual_root = Node3D.new()
	add_child(visual_root)
	if not DedicatedServer.active:
		var normalizer := Node3D.new()
		visual_root.add_child(normalizer)
		var model_scene := load(C4_MODEL_PATH) as PackedScene
		if model_scene:
			normalizer.add_child(model_scene.instantiate())
			_fit_model(normalizer)

		var light := OmniLight3D.new()
		light.light_color = Color("#ff3b2f")
		light.light_energy = 3.5
		light.omni_range = 4.0
		visual_root.add_child(light)
		var label := Label3D.new()
		label.text = "SUICIDE VEST\nPICK UP"
		label.position.y = 0.88
		label.font_size = 34
		label.outline_size = 9
		label.modulate = Color("#ff655a")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		visual_root.add_child(label)

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.9
	collision.shape = shape
	collision.position.y = 0.24
	add_child(collision)

func _fit_model(root: Node3D) -> void:
	var points: Array[Vector3] = []
	_collect_mesh_bounds(root, Transform3D.IDENTITY, points)
	if points.is_empty():
		root.scale = Vector3.ONE * 0.4
		return
	var minimum: Vector3 = points[0]
	var maximum: Vector3 = points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var size := maximum - minimum
	var longest := maxf(size.x, maxf(size.y, size.z))
	var fit_scale := 1.05 / maxf(longest, 0.001)
	root.scale = Vector3.ONE * fit_scale
	root.position = -(minimum + maximum) * 0.5 * fit_scale

func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, points: Array[Vector3]) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var bounds: AABB = mesh_instance.mesh.get_aabb()
			for corner_index in 8:
				var corner := bounds.position + Vector3(
					bounds.size.x if (corner_index & 1) != 0 else 0.0,
					bounds.size.y if (corner_index & 2) != 0 else 0.0,
					bounds.size.z if (corner_index & 4) != 0 else 0.0
				)
				points.append(node_transform * corner)
	for child in node.get_children():
		_collect_mesh_bounds(child, node_transform, points)

func _on_body_entered(body: Node3D) -> void:
	_try_collect(body)

func _check_nearby_players() -> void:
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if candidate is Node3D and global_position.distance_squared_to(candidate.global_position) <= 1.65 * 1.65:
			if _try_collect(candidate):
				return

func _try_collect(body: Node) -> bool:
	if was_collected:
		return false
	if body.get("alive") != true or body.get("mode_infected") == true or not body.has_method("acquire_suicide_vest"):
		return false
	if body.acquire_suicide_vest():
		var counts: Dictionary = body.get_meta("powerup_handoff_counts", {}).duplicate()
		counts[pickup_kind] = int(get_meta("powerup_handoff_count", 0))
		body.set_meta("powerup_handoff_counts", counts)
		was_collected = true
		set_deferred("monitoring", false)
		collected.emit(body)
		queue_free()
		return true
	return false
