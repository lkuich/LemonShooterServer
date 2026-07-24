extends Node3D

# Placeholder city kit. Replace the four _placeholder_* factories with packed
# scenes later; the arena layout, spawns, and navigation routes can stay intact.

const TrafficCar = preload("res://scripts/city_traffic_car.gd")
const Civilian = preload("res://scripts/city_civilian.gd")
const MODEL_FIT_PATH := "res://scripts/model_fit.gd"
const MAP_SURFACE_MATERIALS_PATH := "res://scripts/map_surface_materials.gd"
const TREE_MODEL_PATHS := ["res://models/trees/Tree1.glb", "res://models/trees/Tree-2.glb"]
const STOP_SIGN_PATH := "res://models/city/Stop sign.glb"
const TRAFFIC_LIGHT_PATH := "res://models/city/Traffic Light.glb"
const STREET_LIGHT_PATH := "res://models/city/Street Light.glb"

const PLAYER_SPAWNS := [
	Vector3(-22, 1, 49), Vector3(0, 1, 49), Vector3(22, 1, 49)
]
const BOT_SPAWNS := [
	Vector3(-24, 1, -49), Vector3(-12, 1, -49), Vector3(0, 1, -49),
	Vector3(12, 1, -49), Vector3(24, 1, -49)
]
const NAVIGATION_POINTS := [
	# Three north/south streets.
	Vector3(-22, 1, -49), Vector3(-22, 1, -28), Vector3(-22, 1, 0), Vector3(-22, 1, 28), Vector3(-22, 1, 49),
	Vector3(0, 1, -49), Vector3(0, 1, -28), Vector3(0, 1, 0), Vector3(0, 1, 28), Vector3(0, 1, 49),
	Vector3(22, 1, -49), Vector3(22, 1, -28), Vector3(22, 1, 0), Vector3(22, 1, 28), Vector3(22, 1, 49),
	# Three cross-town avenues and their flanking approaches.
	Vector3(-42, 1, -28), Vector3(-11, 1, -28), Vector3(11, 1, -28), Vector3(42, 1, -28),
	Vector3(-42, 1, 0), Vector3(-11, 1, 0), Vector3(11, 1, 0), Vector3(42, 1, 0),
	Vector3(-42, 1, 28), Vector3(-11, 1, 28), Vector3(11, 1, 28), Vector3(42, 1, 28)
]

const ASPHALT := Color("#30393d")
const SIDEWALK := Color("#78858a")
const DARK_CONCRETE := Color("#263238")
const WINDOW := Color("#477082")
const ROAD_LINE := Color("#d2b94f")
const TREE_TRUNK := Color("#664831")
const TREE_GREEN := Color("#48734d")

var _built := false
var _dynamic_actors: Dictionary = {}

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true
	_build_ground_and_streets()
	_build_city_blocks()
	_build_park()
	_build_street_obstacles()
	_build_city_furniture()
	_build_traffic()
	_build_civilians()

static func navigation_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in NAVIGATION_POINTS:
		result.append(point)
	return result

func _build_ground_and_streets() -> void:
	add_child(_placeholder_box("CityGround", Vector3(92, 0.4, 112), Vector3(0, -0.2, 0), ASPHALT, "asphalt"))
	add_child(_placeholder_box("NorthBoundary", Vector3(92, 3, 1), Vector3(0, 1.5, -56), DARK_CONCRETE, "painted_metal"))
	add_child(_placeholder_box("SouthBoundary", Vector3(92, 3, 1), Vector3(0, 1.5, 56), DARK_CONCRETE, "painted_metal"))
	add_child(_placeholder_box("WestBoundary", Vector3(1, 3, 112), Vector3(-46, 1.5, 0), DARK_CONCRETE, "painted_metal"))
	add_child(_placeholder_box("EastBoundary", Vector3(1, 3, 112), Vector3(46, 1.5, 0), DARK_CONCRETE, "painted_metal"))

	# Raised blocks make the road grid readable and keep vehicle lanes open.
	for x in [-35.0, -11.0, 11.0, 35.0]:
		var block_width := 18.0 if absf(x) > 20.0 else 12.0
		for z in [-42.0, -14.0, 14.0, 42.0]:
			add_child(_placeholder_box("SidewalkBlock", Vector3(block_width, 0.2, 18), Vector3(x, 0.1, z), SIDEWALK, "concrete"))

	if not NetworkSession.is_dedicated_server:
		# Dashed lane markers and crosswalks are visual-only.
		for street_x in [-22.0, 0.0, 22.0]:
			for z in range(-48, 49, 12):
				add_child(_visual_box(Vector3(0.14, 0.025, 5.0), Vector3(street_x, 0.025, z), ROAD_LINE))
		for street_z in [-28.0, 0.0, 28.0]:
			for x in range(-42, 43, 12):
				add_child(_visual_box(Vector3(5.0, 0.025, 0.14), Vector3(x, 0.03, street_z), ROAD_LINE))
		for crossing_z in [-28.0, 0.0, 28.0]:
			for crossing_x in [-22.0, 0.0, 22.0]:
				for stripe in [-3.0, -1.5, 0.0, 1.5, 3.0]:
					add_child(_visual_box(Vector3(0.65, 0.03, 3.8), Vector3(crossing_x + stripe, 0.04, crossing_z), Color("#d9dcda")))

func _build_city_blocks() -> void:
	var tower_data := [
		["NorthWestTower", Vector3(-35, 0.2, -42), Vector2(16, 15), 25.0, Color("#596970")],
		["NorthStudio", Vector3(-11, 0.2, -42), Vector2(10, 14), 12.0, Color("#78675c")],
		["NorthGlass", Vector3(11, 0.2, -42), Vector2(10, 14), 19.0, Color("#496875")],
		["NorthEastTower", Vector3(35, 0.2, -42), Vector2(16, 15), 22.0, Color("#6c6269")],
		["WestOffices", Vector3(-35, 0.2, -14), Vector2(16, 14), 15.0, Color("#5f6d70")],
		["CornerShops", Vector3(-11, 0.2, -14), Vector2(10, 13), 7.0, Color("#846b51")],
		["CivicTower", Vector3(11, 0.2, -14), Vector2(10, 13), 24.0, Color("#536a75")],
		["EastApartments", Vector3(35, 0.2, -14), Vector2(16, 14), 13.0, Color("#71645b")],
		["MidtownOffices", Vector3(-11, 0.2, 14), Vector2(10, 13), 11.0, Color("#61757a")],
		["MetroTower", Vector3(11, 0.2, 14), Vector2(10, 13), 20.0, Color("#4d6670")],
		["EastSpire", Vector3(35, 0.2, 14), Vector2(16, 14), 27.0, Color("#625d70")],
		["SouthWestTower", Vector3(-35, 0.2, 42), Vector2(16, 15), 18.0, Color("#6b645b")],
		["SouthCenter", Vector3(-11, 0.2, 42), Vector2(10, 14), 23.0, Color("#556b73")],
		["SouthMarket", Vector3(11, 0.2, 42), Vector2(10, 14), 9.0, Color("#78634f")],
		["SouthEastTower", Vector3(35, 0.2, 42), Vector2(16, 15), 16.0, Color("#59666b")]
	]
	for data in tower_data:
		add_child(_placeholder_tower(data[0], data[1], data[2], data[3], data[4]))

func _build_park() -> void:
	# The south-west mid block is a green pocket with staggered sightline cover.
	if not NetworkSession.is_dedicated_server:
		add_child(_visual_box(Vector3(16, 0.08, 18), Vector3(-35, 0.24, 14), Color("#526f4b"), "grass"))
	for position in [
		Vector3(-41, 0.2, 8), Vector3(-34, 0.2, 9), Vector3(-28, 0.2, 8),
		Vector3(-41, 0.2, 16), Vector3(-29, 0.2, 17), Vector3(-37, 0.2, 21)
	]:
		add_child(_placeholder_tree(position))

func _build_street_obstacles() -> void:
	# Street furniture now comes from the imported city asset set. Keep this
	# hook for future destructible props without leaving placeholder geometry.
	pass

func _build_city_furniture() -> void:
	for data in [
		[Vector3(-27.2, 0.2, -33.0), 0.0], [Vector3(5.0, 0.2, -33.0), PI],
		[Vector3(27.2, 0.2, -5.0), PI * 0.5], [Vector3(-5.0, 0.2, 5.0), -PI * 0.5],
		[Vector3(-27.2, 0.2, 33.0), 0.0], [Vector3(27.2, 0.2, 33.0), PI]
	]:
		add_child(_model_prop("TrafficLight", TRAFFIC_LIGHT_PATH, 4.3, data[0], data[1], 0.24))
	for data in [
		[Vector3(-16.2, 0.2, -33.0), 0.0], [Vector3(16.2, 0.2, -23.0), PI],
		[Vector3(-27.0, 0.2, 5.0), PI * 0.5], [Vector3(27.0, 0.2, -5.0), -PI * 0.5],
		[Vector3(-16.2, 0.2, 33.0), 0.0], [Vector3(16.2, 0.2, 23.0), PI]
	]:
		add_child(_model_prop("StopSign", STOP_SIGN_PATH, 2.8, data[0], data[1], 0.14))
	for position in [
		Vector3(-44.2, 0.2, -40), Vector3(-44.2, 0.2, 0), Vector3(-44.2, 0.2, 40),
		Vector3(44.2, 0.2, -40), Vector3(44.2, 0.2, 0), Vector3(44.2, 0.2, 40),
		Vector3(-16.0, 0.2, -33), Vector3(16.0, 0.2, 33)
	]:
		add_child(_model_prop("StreetLight", STREET_LIGHT_PATH, 4.6, position, 0.0, 0.18))

func _build_traffic() -> void:
	# Closed one-way loops keep placeholder traffic on road lanes without needing
	# a navigation mesh. Their actor IDs are deterministic for LAN snapshots.
	var west_loop: Array[Vector3] = [
		Vector3(-23.8, 0.05, -26.2), Vector3(-2.7, 0.05, -26.2),
		Vector3(-2.7, 0.05, 26.2), Vector3(-23.8, 0.05, 26.2)
	]
	var east_loop: Array[Vector3] = [
		Vector3(23.8, 0.05, 26.2), Vector3(2.7, 0.05, 26.2),
		Vector3(2.7, 0.05, -26.2), Vector3(23.8, 0.05, -26.2)
	]
	var outer_loop: Array[Vector3] = [
		Vector3(-44.1, 0.05, -26.2), Vector3(-20.2, 0.05, -26.2),
		Vector3(20.2, 0.05, -26.2), Vector3(44.1, 0.05, -26.2),
		Vector3(44.1, 0.05, 26.2), Vector3(20.2, 0.05, 26.2),
		Vector3(-20.2, 0.05, 26.2), Vector3(-44.1, 0.05, 26.2)
	]
	var traffic_data := [
		[west_loop, 0, "sports"], [west_loop, 2, "mazda"],
		[east_loop, 0, "fast"], [east_loop, 2, "police"],
		[outer_loop, 0, "mazda"], [outer_loop, 4, "sports"]
	]
	for index in traffic_data.size():
		var data: Array = traffic_data[index]
		var car := TrafficCar.new()
		car.setup(index + 1, data[0], data[1], data[2])
		add_child(car)
		_dynamic_actors[car.actor_id] = car

func _build_civilians() -> void:
	# Each pedestrian follows one building's clear sidewalk perimeter. The old
	# cross-block routes cut directly through tower collision volumes.
	var civilian_routes: Array[Array] = [
		_sidewalk_loop(Vector2(-35, -42), 18.0), _sidewalk_loop(Vector2(-11, -42), 12.0),
		_sidewalk_loop(Vector2(11, -42), 12.0), _sidewalk_loop(Vector2(-35, -14), 18.0),
		_sidewalk_loop(Vector2(-11, -14), 12.0), _sidewalk_loop(Vector2(35, -14), 18.0),
		_sidewalk_loop(Vector2(11, 14), 12.0), _sidewalk_loop(Vector2(35, 14), 18.0),
		_sidewalk_loop(Vector2(35, 42), 18.0)
	]
	for index in civilian_routes.size():
		var route: Array[Vector3] = civilian_routes[index]
		var civilian := Civilian.new()
		civilian.setup(100 + index, route, index % route.size(), index)
		add_child(civilian)
		_dynamic_actors[civilian.actor_id] = civilian

func _sidewalk_loop(center: Vector2, block_width: float) -> Array[Vector3]:
	var half_x := block_width * 0.5 - 0.5
	var half_z := 8.5
	return [
		Vector3(center.x - half_x, 0.22, center.y - half_z),
		Vector3(center.x + half_x, 0.22, center.y - half_z),
		Vector3(center.x + half_x, 0.22, center.y + half_z),
		Vector3(center.x - half_x, 0.22, center.y + half_z)
	]

func get_dynamic_actor(actor_id: int) -> Node:
	var actor: Node = _dynamic_actors.get(actor_id)
	return actor if is_instance_valid(actor) else null

func dynamic_actor_snapshot() -> Dictionary:
	var result := {}
	for actor_id in _dynamic_actors:
		var actor: Node = _dynamic_actors[actor_id]
		if is_instance_valid(actor) and actor.has_method("snapshot_state"):
			result[actor_id] = actor.snapshot_state()
	return result

func apply_dynamic_actor_snapshot(states: Dictionary) -> void:
	for actor_id in states:
		var actor := get_dynamic_actor(int(actor_id))
		if actor and actor.has_method("apply_snapshot"):
			actor.apply_snapshot(states[actor_id])

func alert_civilians(origin: Vector3, end_position: Vector3) -> void:
	for actor in _dynamic_actors.values():
		if is_instance_valid(actor) and actor.has_method("consider_gunshot"):
			actor.consider_gunshot(origin, end_position)

func _placeholder_tower(node_name: String, ground_position: Vector3, footprint: Vector2, height: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = ground_position
	root.add_child(_placeholder_box("BuildingMass", Vector3(footprint.x, height, footprint.y), Vector3(0, height * 0.5, 0), color, "stucco"))
	root.add_child(_placeholder_box("RooftopUnit", Vector3(footprint.x * 0.38, 1.4, footprint.y * 0.32), Vector3(0, height + 0.7, 0), DARK_CONCRETE, "painted_metal"))
	if not NetworkSession.is_dedicated_server:
		for band_y in range(3, int(height) - 1, 4):
			root.add_child(_visual_box(Vector3(footprint.x + 0.03, 0.55, footprint.y + 0.03), Vector3(0, band_y, 0), WINDOW, "glass"))
	return root

func _placeholder_tree(ground_position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "CityTree"
	root.position = ground_position
	if not NetworkSession.is_dedicated_server:
		var model_index := posmod(int(absf(ground_position.x + ground_position.z)), TREE_MODEL_PATHS.size())
		var tree_scene = load(TREE_MODEL_PATHS[model_index])
		var model: Node3D = tree_scene.instantiate()
		root.add_child(model)
		var model_fit = load(MODEL_FIT_PATH)
		model_fit.fit_to_size(model, 5.6)
	var trunk := StaticBody3D.new()
	trunk.name = "TreeTrunkCollision"
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.38
	shape.height = 3.0
	collision.shape = shape
	collision.position.y = 1.5
	trunk.add_child(collision)
	root.add_child(trunk)
	return root

func _model_prop(node_name: String, scene_path: String, target_height: float, world_position: Vector3, yaw: float, pole_radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = world_position
	root.rotation.y = yaw
	if not NetworkSession.is_dedicated_server:
		var prop_scene = load(scene_path)
		var model: Node3D = prop_scene.instantiate()
		root.add_child(model)
		var model_fit = load(MODEL_FIT_PATH)
		model_fit.fit_to_size(model, target_height)
	if pole_radius > 0.0:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = pole_radius
		shape.height = target_height
		collision.shape = shape
		collision.position.y = target_height * 0.5
		body.add_child(collision)
		root.add_child(body)
	return root

func _placeholder_box(node_name: String, size: Vector3, position: Vector3, color: Color, surface := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	if not NetworkSession.is_dedicated_server:
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _material(color, surface)
		mesh_instance.mesh = mesh
		body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _visual_box(size: Vector3, position: Vector3, color: Color, surface := "") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color, surface)
	instance.mesh = mesh
	return instance

func _material(color: Color, surface := "") -> StandardMaterial3D:
	var map_surface_materials = load(MAP_SURFACE_MATERIALS_PATH)
	return map_surface_materials.create(color, surface)
