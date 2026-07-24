extends Area3D

signal collected(perk_id: String, perk_name: String, collector: Node)

const PERK_COLORS := {
	"sleight_of_hand": Color("#f1c84b"),
	"juggernog": Color("#d94b47"),
	"featherfoot": Color("#55d6a5"),
	"stopping_power": Color("#ed7f38"),
	"scavenger": Color("#8ed06c"),
	"quick_fix": Color("#49d9c5"),
	"last_stand": Color("#d96b76"),
	"demolitionist": Color("#ff9c42"),
	"shockwave_ground_pound": Color("#8ee8ff")
}
const PERK_ICONS := {
	"sleight_of_hand": "res://assets/icons/perk_sleight.svg",
	"juggernog": "res://assets/icons/perk_juggernog.svg",
	"featherfoot": "res://assets/icons/perk_featherfoot.svg",
	"stopping_power": "res://assets/icons/perk_stopping.svg",
	"scavenger": "res://assets/icons/perk_sleight.svg",
	"quick_fix": "res://assets/icons/perk_juggernog.svg",
	"last_stand": "res://assets/icons/perk_juggernog.svg",
	"demolitionist": "res://assets/icons/grenade.svg",
	"shockwave_ground_pound": "res://assets/icons/grenade.svg"
}

var perk_id := ""
var perk_name := ""
var pickup_kind := "perk"
var visual_root: Node3D
var perk_light: OmniLight3D

func configure(id: String, display_name: String) -> void:
	perk_id = id
	perk_name = display_name
	name = "%sPickup" % display_name.replace(" ", "")

func _ready() -> void:
	add_to_group("collectible_pickups")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	_build_visual()

func _process(delta: float) -> void:
	visual_root.rotation.y += delta * 1.8
	visual_root.position.y = 0.22 + sin(Time.get_ticks_msec() * 0.004) * 0.07
	if perk_light:
		perk_light.light_energy = 1.8 + sin(Time.get_ticks_msec() * 0.006) * 0.45

func _build_visual() -> void:
	var color: Color = PERK_COLORS.get(perk_id, Color.WHITE)
	visual_root = Node3D.new()
	add_child(visual_root)

	if not DedicatedServer.active:
		var mesh_instance := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.36
		mesh.bottom_radius = 0.36
		mesh.height = 0.16
		var core_material := StandardMaterial3D.new()
		core_material.albedo_color = Color("#10171a")
		core_material.metallic = 0.72
		core_material.roughness = 0.24
		core_material.emission_enabled = true
		core_material.emission = Color(color, 0.35)
		core_material.emission_energy_multiplier = 0.7
		mesh.material = core_material
		mesh_instance.mesh = mesh
		visual_root.add_child(mesh_instance)

		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.37
		ring_mesh.outer_radius = 0.44
		var glow_material := StandardMaterial3D.new()
		glow_material.albedo_color = color
		glow_material.emission_enabled = true
		glow_material.emission = color
		glow_material.emission_energy_multiplier = 3.4
		ring_mesh.material = glow_material
		ring.mesh = ring_mesh
		visual_root.add_child(ring)

		perk_light = OmniLight3D.new()
		perk_light.light_color = color
		perk_light.light_energy = 2.0
		perk_light.omni_range = 2.8
		visual_root.add_child(perk_light)

		var icon_texture := load(str(PERK_ICONS.get(perk_id, PERK_ICONS["sleight_of_hand"]))) as Texture2D
		var icon_shadow := Sprite3D.new()
		icon_shadow.texture = icon_texture
		icon_shadow.position = Vector3(0.025, 0.48, 0.015)
		icon_shadow.pixel_size = 0.012
		icon_shadow.modulate = Color(0, 0, 0, 0.7)
		icon_shadow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon_shadow.no_depth_test = true
		visual_root.add_child(icon_shadow)
		var icon := Sprite3D.new()
		icon.texture = icon_texture
		icon.position = Vector3(0, 0.5, 0)
		icon.pixel_size = 0.012
		icon.modulate = color
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.no_depth_test = true
		visual_root.add_child(icon)

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	collision.shape = shape
	collision.position.y = 0.22
	add_child(collision)

func _on_body_entered(body: Node3D) -> void:
	if body.get("alive") != true or body.get("mode_infected") == true or not body.has_method("apply_perk"):
		return
	var owned_perks = body.get("active_perks")
	if owned_perks != null and perk_id in owned_perks:
		return
	if body.apply_perk(perk_id):
		set_deferred("monitoring", false)
		collected.emit(perk_id, perk_name, body)
		queue_free()
