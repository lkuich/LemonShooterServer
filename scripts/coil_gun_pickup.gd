extends Area3D

signal collected(collector: Node)

const COIL_GUN_MODEL_PATH := "res://models/coil_gun/model.glb"

var visual_root: Node3D
var pickup_kind := "coil_gun"

func _ready() -> void:
	add_to_group("collectible_pickups")
	name = "CoilGunPickup"
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	_build_pickup()

func _process(delta: float) -> void:
	visual_root.rotation.y += delta * 0.65
	visual_root.position.y = 0.24 + sin(Time.get_ticks_msec() * 0.003) * 0.07

func _build_pickup() -> void:
	visual_root = Node3D.new()
	add_child(visual_root)
	if not DedicatedServer.active:
		var normalizer := Node3D.new()
		visual_root.add_child(normalizer)
		var model_scene := load(COIL_GUN_MODEL_PATH) as PackedScene
		if model_scene:
			var model := model_scene.instantiate() as Node3D
			normalizer.add_child(model)
			_fit_model(normalizer)

		var light := OmniLight3D.new()
		light.light_color = Color("#ba78ff")
		light.light_energy = 3.0
		light.omni_range = 3.5
		visual_root.add_child(light)
		var label := Label3D.new()
		label.text = "COIL GUN\nPICK UP"
		label.position.y = 0.82
		label.font_size = 36
		label.outline_size = 9
		label.modulate = Color("#d3a8ff")
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
	var fit_scale := 1.15 / maxf(longest, 0.001)
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
	if body.get("alive") != true or body.get("mode_infected") == true or not body.has_method("acquire_coil_gun"):
		return
	if body.acquire_coil_gun():
		_record_handoff(body)
		set_deferred("monitoring", false)
		collected.emit(body)
		queue_free()

func _record_handoff(collector: Node) -> void:
	var counts: Dictionary = collector.get_meta("powerup_handoff_counts", {}).duplicate()
	counts[pickup_kind] = int(get_meta("powerup_handoff_count", 0))
	collector.set_meta("powerup_handoff_counts", counts)
