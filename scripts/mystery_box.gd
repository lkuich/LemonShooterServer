extends StaticBody3D

const MODEL_FIT_PATH := "res://scripts/model_fit.gd"
const ROLL_DURATION := 5.0
const WEAPON_MODELS := {
	"ak47": ["res://models/ak472/model.glb", -90.0],
	"ar15": ["res://models/ar15/model.glb", 90.0],
	"smg": ["res://models/uzi/model.glb", 0.0],
	"shotgun": ["res://models/shotgun/model.glb", 90.0],
	"sniper": ["res://content/core/weapons/sniper/model/model.glb", 0.0]
}

var used_by: Dictionary = {}
var status_label: Label3D
var status_timer := 0.0
var roulette_root: Node3D
var roulette_models: Dictionary = {}
var roulette_audio: AudioStreamPlayer3D
var rolling := false
var cycle_timer := 0.0
var displayed_weapon := ""
var selected_weapon := ""
var pending_actor: Node
var reveal_timer := 0.0
var roll_time_remaining := 0.0


func _ready() -> void:
	name = "MysteryBox"
	add_to_group("world_interactables")
	collision_layer = 1
	collision_mask = 0
	_build_chest()
	_build_roulette()


func _process(delta: float) -> void:
	if rolling:
		roll_time_remaining = maxf(roll_time_remaining - delta, 0.0)
		roulette_root.rotation.y += delta * 4.2
		roulette_root.position.y = 1.42 + sin(Time.get_ticks_msec() * 0.006) * 0.08
		cycle_timer -= delta
		if cycle_timer <= 0.0:
			cycle_timer = 0.18
			_cycle_preview()
		if roll_time_remaining <= 0.0:
			_finish_roll()
	elif reveal_timer > 0.0:
		reveal_timer = maxf(reveal_timer - delta, 0.0)
		roulette_root.rotation.y += delta * 1.8
		if reveal_timer <= 0.0:
			roulette_root.visible = false
	status_timer = maxf(status_timer - delta, 0.0)
	if status_timer <= 0.0 and status_label:
		status_label.text = "MYSTERY BOX"


func interact(actor: Node) -> bool:
	if not actor or actor.get("alive") != true or not actor.has_method("grant_mystery_weapon"):
		return false
	var actor_key := actor.get_instance_id()
	if used_by.has(actor_key):
		status_label.text = "ALREADY USED"
		status_timer = 2.0
		return false
	if rolling or not actor.has_method("roll_mystery_weapon"):
		return false
	used_by[actor_key] = true
	pending_actor = actor
	selected_weapon = str(actor.roll_mystery_weapon())
	if selected_weapon.is_empty() or not WEAPON_MODELS.has(selected_weapon):
		used_by.erase(actor_key)
		pending_actor = null
		return false
	rolling = true
	roll_time_remaining = ROLL_DURATION
	cycle_timer = 0.0
	reveal_timer = 0.0
	status_timer = 0.0
	status_label.text = "ROLLING..."
	roulette_root.visible = true
	_cycle_preview()
	return true


func get_interaction_label(actor: Node = null) -> String:
	if rolling:
		return "MYSTERY BOX — ROLLING"
	if actor and used_by.has(actor.get_instance_id()):
		return "MYSTERY BOX — USED"
	return "USE MYSTERY BOX"


func _build_chest() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.05, 1.05)
	collision.shape = shape
	collision.position.y = 0.53
	add_child(collision)

	if not DedicatedServer.active:
		var dark := Color("#20180e")
		var wood := Color("#67411f")
		var gold := Color("#d9ad38")
		add_child(_panel("ChestBody", Vector3(1.8, 0.78, 1.05), Vector3(0, 0.42, 0), wood))
		add_child(_panel("ChestLid", Vector3(1.92, 0.24, 1.16), Vector3(0, 0.93, 0), dark))
		for x in [-0.72, 0.0, 0.72]:
			add_child(_panel("MetalBand", Vector3(0.10, 1.08, 1.18), Vector3(x, 0.54, 0), gold))
		add_child(_panel("Latch", Vector3(0.28, 0.34, 0.10), Vector3(0, 0.61, -0.58), gold))

	status_label = Label3D.new()
	status_label.text = "MYSTERY BOX"
	status_label.position = Vector3(0, 2.05, 0)
	status_label.font_size = 32
	status_label.outline_size = 7
	status_label.modulate = Color("#f1ca4f")
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.no_depth_test = true
	add_child(status_label)


func _build_roulette() -> void:
	roulette_root = Node3D.new()
	roulette_root.name = "WeaponRoulette"
	roulette_root.position.y = 1.42
	roulette_root.visible = false
	add_child(roulette_root)
	if DedicatedServer.active:
		return
	var model_fit_script := load(MODEL_FIT_PATH) as Script
	for weapon_id in WEAPON_MODELS:
		var data: Array = WEAPON_MODELS[weapon_id]
		var model_scene := load(str(data[0])) as PackedScene
		if not model_scene:
			continue
		var model: Node3D = model_scene.instantiate()
		model.name = "%sPreview" % weapon_id.capitalize()
		roulette_root.add_child(model)
		if model_fit_script:
			model_fit_script.fit_to_size(model, 0.46, 1.18)
		model.rotation.y = deg_to_rad(float(data[1]))
		model.visible = false
		roulette_models[weapon_id] = model


func _cycle_preview() -> void:
	var weapon_ids := WEAPON_MODELS.keys()
	if weapon_ids.size() > 1:
		weapon_ids.erase(displayed_weapon)
	_show_preview(str(weapon_ids.pick_random()))


func _show_preview(weapon_id: String) -> void:
	for id in roulette_models:
		roulette_models[id].visible = str(id) == weapon_id
	displayed_weapon = weapon_id


func _finish_roll() -> void:
	if not rolling:
		return
	rolling = false
	roll_time_remaining = 0.0
	if roulette_audio:
		roulette_audio.stop()
	_show_preview(selected_weapon)
	reveal_timer = 2.6
	var weapon_name := ""
	if is_instance_valid(pending_actor) and pending_actor.get("alive") == true:
		weapon_name = str(pending_actor.grant_mystery_weapon(selected_weapon))
	status_label.text = weapon_name.to_upper() if not weapon_name.is_empty() else "ROLL LOST"
	status_timer = reveal_timer
	pending_actor = null


func _panel(panel_name: String, size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = panel_name
	panel.position = local_position
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	mesh.material = material
	panel.mesh = mesh
	return panel
