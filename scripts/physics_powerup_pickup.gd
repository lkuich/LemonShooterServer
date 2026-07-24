extends Area3D

signal collected(kind: String, collector: Node)

const GLOVE_MODEL_PATH := "res://models/glove/model.glb"
const MODEL_FIT_PATH := "res://scripts/model_fit.gd"
const ENHANCED_GRENADE_VISUAL_PATH := "res://scripts/enhanced_grenade_visual.gd"

const COLORS := {
	"ricochet": Color("#ffcf45"),
	"force": Color("#63e6ff"),
	"gravity_bomb": Color("#956dff"),
	"sticky_bomb": Color("#ff4058")
}
const LABELS := {
	"ricochet": "RICOCHET\n30 SECONDS",
	"force": "FORCE MANIPULATOR",
	"gravity_bomb": "GRAVITY BOMBS\nGRENADE REPLACEMENT",
	"sticky_bomb": "STICKY BOMBS\nGRENADE REPLACEMENT"
}

var pickup_kind := "ricochet"
var visual_root: Node3D

func configure(kind: String) -> void:
	pickup_kind = kind
	name = "%sPickup" % kind.capitalize()

func _ready() -> void:
	add_to_group("collectible_pickups")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	_build_visual()

func _process(delta: float) -> void:
	visual_root.rotation.y += delta * 1.1
	visual_root.position.y = 0.26 + sin(Time.get_ticks_msec() * 0.0035) * 0.08

func _build_visual() -> void:
	var color: Color = COLORS.get(pickup_kind, Color.WHITE)
	visual_root = Node3D.new()
	add_child(visual_root)
	if not DedicatedServer.active:
		if pickup_kind in ["gravity_bomb", "sticky_bomb"]:
			var grenade_visual_script := load(ENHANCED_GRENADE_VISUAL_PATH) as Script
			if grenade_visual_script:
				var grenade_visual: Node3D = grenade_visual_script.new()
				grenade_visual.configure(pickup_kind, 0.32, 28)
				visual_root.add_child(grenade_visual)
		elif pickup_kind == "force":
			var hand_holder := Node3D.new()
			hand_holder.rotation = Vector3(deg_to_rad(-18.0), PI, deg_to_rad(-8.0))
			visual_root.add_child(hand_holder)
			var glove_scene := load(GLOVE_MODEL_PATH) as PackedScene
			var model_fit_script := load(MODEL_FIT_PATH) as Script
			if glove_scene and model_fit_script:
				var hand_model := glove_scene.instantiate() as Node3D
				hand_holder.add_child(hand_model)
				model_fit_script.fit_to_size(hand_model, 0.78, 0.92)
				hand_model.scale.x *= -1.0
				hand_model.position.y -= 0.39
		else:
			var core := MeshInstance3D.new()
			var core_mesh := BoxMesh.new()
			core_mesh.size = Vector3(0.72, 0.18, 0.72)
			core_mesh.material = _material(color.darkened(0.62), color)
			core.mesh = core_mesh
			visual_root.add_child(core)
		if pickup_kind not in ["gravity_bomb", "sticky_bomb"]:
			var ring := MeshInstance3D.new()
			var ring_mesh := TorusMesh.new()
			ring_mesh.inner_radius = 0.42
			ring_mesh.outer_radius = 0.5
			ring_mesh.material = _material(color, color)
			ring.mesh = ring_mesh
			ring.rotation.x = PI * 0.5
			visual_root.add_child(ring)
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 3.0
		light.omni_range = 3.5
		visual_root.add_child(light)
		var label := Label3D.new()
		label.text = str(LABELS.get(pickup_kind, pickup_kind.to_upper()))
		label.position.y = 0.9
		label.font_size = 34
		label.outline_size = 9
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		visual_root.add_child(label)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.9
	collision.shape = shape
	collision.position.y = 0.25
	add_child(collision)

func _material(color: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.65
	material.roughness = 0.25
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 2.4
	return material

func _on_body_entered(body: Node3D) -> void:
	if body.get("alive") != true or body.get("mode_infected") == true:
		return
	var accepted := false
	if pickup_kind == "ricochet" and body.has_method("acquire_ricochet"):
		accepted = body.acquire_ricochet()
	elif pickup_kind == "force" and body.has_method("acquire_physics_utility"):
		accepted = body.acquire_physics_utility(pickup_kind)
	elif pickup_kind in ["gravity_bomb", "sticky_bomb"] and body.has_method("acquire_grenade_powerup"):
		accepted = body.acquire_grenade_powerup(pickup_kind)
	if accepted:
		var counts: Dictionary = body.get_meta("powerup_handoff_counts", {}).duplicate()
		counts[pickup_kind] = int(get_meta("powerup_handoff_count", 0))
		body.set_meta("powerup_handoff_counts", counts)
		set_deferred("monitoring", false)
		collected.emit(pickup_kind, body)
		queue_free()
