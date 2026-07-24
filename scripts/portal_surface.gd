extends Area3D

signal traveler_entered(portal: Area3D, body: Node3D)

const HALF_WIDTH := 0.78
const HALF_HEIGHT := 1.18
const VISUAL_LAYER := 1 << 18
const MAX_RENDER_DIMENSION := 960

var linked_portal: Area3D
var portal_camera: Camera3D
var portal_viewport: SubViewport
var surface: MeshInstance3D

func configure(color: Color, world: World3D) -> void:
	portal_viewport = SubViewport.new()
	portal_viewport.size = _portal_viewport_size()
	portal_viewport.msaa_3d = Viewport.MSAA_2X
	portal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	portal_viewport.world_3d = world
	add_child(portal_viewport)
	portal_camera = Camera3D.new()
	portal_camera.current = true
	portal_camera.near = 0.08
	portal_camera.cull_mask &= ~VISUAL_LAYER
	portal_viewport.add_child(portal_camera)
	surface = MeshInstance3D.new()
	surface.layers = VISUAL_LAYER
	var quad := QuadMesh.new()
	quad.size = Vector2(HALF_WIDTH * 2.0, HALF_HEIGHT * 2.0)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D portal_view : source_color; uniform vec4 rim_color : source_color; uniform float linked = 0.0; void fragment(){ vec2 p=(UV-vec2(0.5))*2.0; float r=dot(p,p); if(r>1.0){discard;} float rim=smoothstep(0.73,0.98,r); vec3 view_color=texture(portal_view,SCREEN_UV).rgb; vec3 dormant=vec3(0.012,0.018,0.025); ALBEDO=mix(mix(dormant,view_color,linked),rim_color.rgb,rim); EMISSION=rim_color.rgb*rim*4.0+view_color*linked*0.12; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("portal_view", portal_viewport.get_texture())
	material.set_shader_parameter("rim_color", color)
	quad.material = material
	surface.mesh = quad
	surface.position.z = 0.025
	add_child(surface)
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 2.4
	glow.omni_range = 3.2
	glow.position.z = 0.18
	add_child(glow)
	collision_layer = 0
	# World-layer rigid bodies include physics props. Static map bodies overlap the
	# portal too, so `_on_body_entered` filters those before emitting traversal.
	collision_mask = 1 | 2 | 4 | 16 | 32
	monitoring = true
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_WIDTH * 1.75, HALF_HEIGHT * 1.75, 1.25)
	collision.shape = shape
	collision.position.z = 0.48
	add_child(collision)
	body_entered.connect(_on_body_entered)

func set_linked_portal(other: Area3D) -> void:
	linked_portal = other
	var material := surface.get_active_material(0) as ShaderMaterial
	if material:
		material.set_shader_parameter("linked", 1.0 if is_instance_valid(other) else 0.0)

func contains_traveler(body: Node3D) -> bool:
	var local := to_local(body.global_position)
	return absf(local.x) <= HALF_WIDTH * 0.88 and absf(local.y) <= HALF_HEIGHT * 0.84

func update_portal_camera(viewer: Camera3D) -> void:
	if not is_instance_valid(linked_portal) or not is_instance_valid(viewer):
		return
	var desired_size := _portal_viewport_size()
	if portal_viewport.size != desired_size:
		portal_viewport.size = desired_size
	var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var mapped := linked_portal.global_transform * turn * global_transform.affine_inverse() * viewer.global_transform
	portal_camera.global_transform = mapped
	portal_camera.fov = viewer.fov
	portal_camera.near = _portal_near_distance()

func _portal_near_distance() -> float:
	# The correctly mapped camera sits behind the exit portal. Move its near plane
	# beyond the entire elliptical opening so the host wall cannot occlude the
	# view when the player looks through the portal from an oblique angle.
	var exit_basis: Basis = linked_portal.global_transform.basis.orthonormalized()
	var plane_center: Vector3 = linked_portal.global_position + exit_basis.z * 0.065
	var camera_forward := -portal_camera.global_transform.basis.z.normalized()
	var center_depth := (plane_center - portal_camera.global_position).dot(camera_forward)
	var horizontal_depth := HALF_WIDTH * camera_forward.dot(exit_basis.x)
	var vertical_depth := HALF_HEIGHT * camera_forward.dot(exit_basis.y)
	var ellipse_depth_span := sqrt(horizontal_depth * horizontal_depth + vertical_depth * vertical_depth)
	return clampf(center_depth + ellipse_depth_span + 0.025, 0.08, portal_camera.far - 0.1)

func _portal_viewport_size() -> Vector2i:
	var main_size := Vector2i(get_viewport().get_visible_rect().size)
	if main_size.x <= 0 or main_size.y <= 0:
		return Vector2i(MAX_RENDER_DIMENSION, MAX_RENDER_DIMENSION)
	var render_scale := minf(1.0, float(MAX_RENDER_DIMENSION) / float(maxi(main_size.x, main_size.y)))
	return Vector2i(maxi(1, roundi(main_size.x * render_scale)), maxi(1, roundi(main_size.y * render_scale)))

func _on_body_entered(body: Node3D) -> void:
	if body is not RigidBody3D and body is not CharacterBody3D and not body.is_in_group("vehicles"):
		return
	traveler_entered.emit(self, body)
