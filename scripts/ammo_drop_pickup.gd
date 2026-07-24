extends Area3D

signal collected(collector: Node)

var pickup_kind := "ammo_drop"
var visual_root: Node3D
var status_label: Label3D


func _ready() -> void:
	name = "AmmoDrop"
	add_to_group("collectible_pickups")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	_build_mystery_chest()


func _process(delta: float) -> void:
	visual_root.rotation.y += delta * 0.28
	visual_root.position.y = 0.08 + sin(Time.get_ticks_msec() * 0.003) * 0.025


func _build_mystery_chest() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.7, 1.15, 1.15)
	collision.shape = shape
	collision.position.y = 0.55
	add_child(collision)
	visual_root = Node3D.new()
	add_child(visual_root)
	var wood := Color("#67411f")
	var dark := Color("#20180e")
	var lemon := Color("#f1ca4f")
	visual_root.add_child(_panel(Vector3(1.7, 0.72, 1.0), Vector3(0, 0.4, 0), wood))
	visual_root.add_child(_panel(Vector3(1.82, 0.24, 1.1), Vector3(0, 0.88, 0), dark))
	for x in [-0.68, 0.0, 0.68]:
		visual_root.add_child(_panel(Vector3(0.09, 1.0, 1.12), Vector3(x, 0.5, 0), lemon))
	visual_root.add_child(_panel(Vector3(0.3, 0.32, 0.1), Vector3(0, 0.57, -0.56), lemon))
	status_label = Label3D.new()
	status_label.text = "AMMO DROP"
	status_label.position.y = 1.72
	status_label.font_size = 28
	status_label.outline_size = 7
	status_label.modulate = lemon
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.no_depth_test = true
	visual_root.add_child(status_label)


func _panel(size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	mesh.material = material
	panel.mesh = mesh
	return panel


func _on_body_entered(body: Node3D) -> void:
	if body.get("alive") != true or not body.has_method("collect_ammo_drop"):
		return
	if body.collect_ammo_drop():
		set_deferred("monitoring", false)
		collected.emit(body)
		queue_free()
