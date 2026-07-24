extends Node3D

const PortalSurface = preload("res://scripts/portal_surface.gd")
const BLUE := Color("#27a8ff")
const ORANGE := Color("#ff8a22")
const PORTAL_RANGE := 160.0
const EXIT_CLEARANCE := 0.82
const BULLET_EXIT_CLEARANCE := 0.08
const MAX_BULLET_PORTAL_HOPS := 4
const PORTAL_HALF_WIDTH := 0.78
const PORTAL_HALF_HEIGHT := 1.18
const PORTAL_SNAP_STEP := 0.12
const PORTAL_MAX_SNAP_DISTANCE := 2.4

var viewer: Camera3D
var player_body: CharacterBody3D
var portals: Array[Area3D] = [null, null]
var teleporting := {}

func setup(camera: Camera3D, body: CharacterBody3D) -> void:
	viewer = camera
	player_body = body

func place_portal(index: int) -> bool:
	if not is_instance_valid(viewer) or index < 0 or index > 1:
		return false
	var origin := viewer.global_position
	var direction := -viewer.global_transform.basis.z
	var exclusions: Array[RID] = []
	if is_instance_valid(player_body):
		exclusions.append(player_body.get_rid())
	return place_portal_from(index, origin, direction, PORTAL_RANGE, exclusions)

func place_portal_from(index: int, origin: Vector3, direction: Vector3, max_distance := PORTAL_RANGE, exclusions: Array[RID] = []) -> bool:
	if index < 0 or index > 1 or direction.length_squared() < 0.001:
		return false
	direction = direction.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_distance)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = exclusions
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider is not StaticBody3D:
		return false
	var normal: Vector3 = hit.normal.normalized()
	var portal_transform := Transform3D(_portal_basis(normal, direction), hit.position + normal * 0.035)
	var fitted := _find_fitting_portal_transform(portal_transform, hit.collider)
	if fitted.is_empty():
		return false
	portal_transform = fitted["transform"]
	place_portal_transform(index, portal_transform)
	_spawn_placement_flash(portal_transform.origin, BLUE if index == 0 else ORANGE)
	return true

func place_portal_transform(index: int, portal_transform: Transform3D) -> bool:
	if index < 0 or index > 1 or not portal_transform.origin.is_finite():
		return false
	if is_instance_valid(portals[index]): portals[index].queue_free()
	var portal := PortalSurface.new()
	portal.name = "BluePortal" if index == 0 else "OrangePortal"
	get_tree().current_scene.add_child(portal)
	portal.global_transform = portal_transform
	portal.configure(BLUE if index == 0 else ORANGE, get_viewport().world_3d)
	portal.traveler_entered.connect(_on_traveler_entered)
	portals[index] = portal
	_link_portals()
	return true

func remove_portal(index: int) -> void:
	if index < 0 or index > 1:
		return
	if is_instance_valid(portals[index]):
		portals[index].queue_free()
	portals[index] = null
	_link_portals()

func _portal_basis(normal: Vector3, shot_direction: Vector3) -> Basis:
	var up := Vector3.UP - normal * Vector3.UP.dot(normal)
	if up.length_squared() < 0.04: up = shot_direction - normal * shot_direction.dot(normal)
	if up.length_squared() < 0.04: up = Vector3.FORWARD - normal * Vector3.FORWARD.dot(normal)
	up = up.normalized()
	return Basis(up.cross(normal).normalized(), up, normal).orthonormalized()

func _portal_fits(portal_transform: Transform3D, collider: Object) -> bool:
	var state := get_world_3d().direct_space_state
	for offset: Vector2 in [Vector2(-0.68,-1.02),Vector2(0.68,-1.02),Vector2(-0.68,1.02),Vector2(0.68,1.02),Vector2(-0.76,0),Vector2(0.76,0),Vector2(0,-1.12),Vector2(0,1.12)]:
		var point: Vector3 = portal_transform.origin + portal_transform.basis.x * offset.x + portal_transform.basis.y * offset.y
		var normal: Vector3 = portal_transform.basis.z
		var probe := PhysicsRayQueryParameters3D.create(point + normal * 0.22, point - normal * 0.30)
		probe.collision_mask = 1
		var result := state.intersect_ray(probe)
		if result.is_empty() or result.collider != collider or result.normal.dot(normal) < 0.82: return false
	return true

func _find_fitting_portal_transform(initial: Transform3D, collider: Object) -> Dictionary:
	if _portal_fits(initial, collider):
		return {"transform": initial}
	var step_count := ceili(PORTAL_MAX_SNAP_DISTANCE / PORTAL_SNAP_STEP)
	# Most failed placements are close to one straight surface edge. Try the
	# cardinal directions first, preferring upward snapping for low wall shots.
	for step_index in range(1, step_count + 1):
		var distance := float(step_index) * PORTAL_SNAP_STEP
		for offset: Vector2 in [Vector2(0.0, distance), Vector2(0.0, -distance), Vector2(-distance, 0.0), Vector2(distance, 0.0)]:
			var candidate := _offset_portal_transform(initial, offset)
			if _portal_fits(candidate, collider):
				return {"transform": candidate}
	# Corners and irregular surfaces can require movement on both local axes.
	# Test the remaining offsets nearest-first so the portal stays close to the
	# player's impact point instead of jumping to a distant valid patch.
	var offsets: Array[Vector2] = []
	for y_index in range(-step_count, step_count + 1):
		for x_index in range(-step_count, step_count + 1):
			if x_index == 0 or y_index == 0:
				continue
			var offset := Vector2(x_index, y_index) * PORTAL_SNAP_STEP
			if offset.length() <= PORTAL_MAX_SNAP_DISTANCE:
				offsets.append(offset)
	offsets.sort_custom(_portal_offset_precedes)
	for offset in offsets:
		var candidate := _offset_portal_transform(initial, offset)
		if _portal_fits(candidate, collider):
			return {"transform": candidate}
	return {}

func _offset_portal_transform(initial: Transform3D, offset: Vector2) -> Transform3D:
	var candidate := initial
	candidate.origin += initial.basis.x * offset.x + initial.basis.y * offset.y
	return candidate

func _portal_offset_precedes(a: Vector2, b: Vector2) -> bool:
	var a_distance := a.length_squared()
	var b_distance := b.length_squared()
	if not is_equal_approx(a_distance, b_distance):
		return a_distance < b_distance
	if not is_equal_approx(a.y, b.y):
		return a.y > b.y
	return absf(a.x) < absf(b.x)

func _link_portals() -> void:
	var blue = portals[0] if is_instance_valid(portals[0]) else null
	var orange = portals[1] if is_instance_valid(portals[1]) else null
	if blue: blue.set_linked_portal(orange)
	if orange: orange.set_linked_portal(blue)

func trace_bullet(origin: Vector3, direction: Vector3, max_distance: float, collision_mask: int, exclusions: Array[RID]) -> Dictionary:
	var segments: Array[Dictionary] = []
	var current_origin := origin
	var current_direction := direction.normalized()
	var remaining := max_distance
	var final_hit := {}
	for _hop in MAX_BULLET_PORTAL_HOPS + 1:
		var query := PhysicsRayQueryParameters3D.create(current_origin, current_origin + current_direction * remaining)
		query.collision_mask = collision_mask
		query.collide_with_areas = true
		query.exclude = exclusions
		var world_hit := get_world_3d().direct_space_state.intersect_ray(query)
		var world_distance := remaining
		if not world_hit.is_empty():
			world_distance = current_origin.distance_to(world_hit.position)
		var portal_hit := _nearest_portal_on_ray(current_origin, current_direction, remaining)
		if not portal_hit.is_empty() and float(portal_hit["distance"]) < world_distance:
			var entry: Area3D = portal_hit["portal"]
			var crossing_point: Vector3 = portal_hit["position"]
			segments.append({"from": current_origin, "to": crossing_point})
			remaining -= float(portal_hit["distance"])
			if remaining <= 0.01:
				return {"hit": {}, "segments": segments}
			var turn := Basis(Vector3.UP, PI)
			var map_basis: Basis = entry.linked_portal.global_transform.basis * turn * entry.global_transform.basis.inverse()
			var mapped_local := turn * entry.to_local(crossing_point)
			mapped_local.z = BULLET_EXIT_CLEARANCE
			current_origin = entry.linked_portal.to_global(mapped_local)
			current_direction = (map_basis * current_direction).normalized()
			continue
		var end_position: Vector3 = world_hit.position if not world_hit.is_empty() else current_origin + current_direction * remaining
		segments.append({"from": current_origin, "to": end_position})
		final_hit = world_hit
		break
	return {"hit": final_hit, "segments": segments}

func _nearest_portal_on_ray(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var nearest := {}
	var nearest_distance := max_distance + 1.0
	for entry in portals:
		if not is_instance_valid(entry) or not is_instance_valid(entry.linked_portal):
			continue
		var normal: Vector3 = entry.global_transform.basis.z.normalized()
		var denominator := direction.dot(normal)
		if absf(denominator) < 0.0001:
			continue
		var distance := (entry.global_position - origin).dot(normal) / denominator
		if distance <= 0.015 or distance >= nearest_distance or distance > max_distance:
			continue
		var position := origin + direction * distance
		var local_position: Vector3 = entry.to_local(position)
		var normalized_radius := Vector2(local_position.x / PORTAL_HALF_WIDTH, local_position.y / PORTAL_HALF_HEIGHT)
		if normalized_radius.length_squared() > 1.0:
			continue
		nearest_distance = distance
		nearest = {"portal": entry, "position": position, "distance": distance}
	return nearest

func _process(_delta: float) -> void:
	if is_instance_valid(portals[0]): portals[0].update_portal_camera(viewer)
	if is_instance_valid(portals[1]): portals[1].update_portal_camera(viewer)
	var now := Time.get_ticks_msec()
	for key in teleporting.keys():
		if int(teleporting[key]) <= now: teleporting.erase(key)

func _on_traveler_entered(entry: Area3D, body: Node3D) -> void:
	if not is_instance_valid(entry.linked_portal): return
	var id := body.get_instance_id()
	if teleporting.has(id): return
	var motion := _get_velocity(body)
	var entry_normal := entry.global_transform.basis.z.normalized()
	var approach_speed := motion.dot(entry_normal)
	var is_floor_portal := entry_normal.dot(Vector3.UP) > 0.72
	if approach_speed > -0.5:
		# Contact is enough to traverse. Add a small push through the surface when
		# the body is moving sideways or standing still; floor portals use a stronger
		# downward step to overcome the unchanged graybox floor collider.
		var contact_push := 4.0 if is_floor_portal else 2.5
		motion -= entry_normal * (contact_push + maxf(approach_speed, 0.0))
	teleporting[id] = Time.get_ticks_msec() + 300
	call_deferred("_teleport", entry, entry.linked_portal, body, motion)

func _teleport(entry: Area3D, exit: Area3D, body: Node3D, incoming_velocity: Vector3) -> void:
	if not is_instance_valid(entry) or not is_instance_valid(exit) or not is_instance_valid(body): return
	var turn := Basis(Vector3.UP, PI)
	var map_basis := exit.global_transform.basis * turn * entry.global_transform.basis.inverse()
	var mapped_local := turn * entry.to_local(body.global_position)
	mapped_local.z = _exit_clearance(body)
	var destination := exit.to_global(mapped_local)
	var outgoing_velocity := map_basis * incoming_velocity
	var outgoing_basis := (map_basis * body.global_basis).orthonormalized()
	if body.has_method("set_portal_fall_credit"):
		body.set_portal_fall_credit(player_body)
	var scene := get_tree().current_scene
	if scene and scene.has_method("request_portal_travel"):
		scene.request_portal_travel(body, entry.global_position, destination, outgoing_velocity, outgoing_basis, player_body)
	body.global_position = destination
	_set_velocity(body, outgoing_velocity)
	if body == player_body: _orient_player(map_basis)
	elif body is RigidBody3D or body.is_in_group("vehicles"): body.global_basis = outgoing_basis
	if body.has_method("begin_portal_travel"):
		body.begin_portal_travel(outgoing_velocity, outgoing_basis)
	teleporting[body.get_instance_id()] = Time.get_ticks_msec() + 300

func _exit_clearance(body: Node3D) -> float:
	# The portal is deliberately allowed to swallow objects larger than its visual
	# opening. Spawn vehicles beyond the exit plane so their chassis does not remain
	# embedded in the wall and immediately collide or re-enter.
	return 3.2 if body.is_in_group("vehicles") else EXIT_CLEARANCE

func _orient_player(map_basis: Basis) -> void:
	var new_forward := (map_basis * -viewer.global_transform.basis.z).normalized()
	var horizontal := Vector3(new_forward.x, 0, new_forward.z)
	if horizontal.length_squared() > 0.001: player_body.look_at(player_body.global_position + horizontal.normalized(), Vector3.UP)
	var head := player_body.get("head") as Node3D
	if head: head.rotation.x = clampf(asin(clampf(new_forward.y,-1.0,1.0)),deg_to_rad(-88),deg_to_rad(88))

func _get_velocity(body: Node3D) -> Vector3:
	if body is RigidBody3D: return body.linear_velocity
	if body is CharacterBody3D: return body.velocity
	return Vector3.ZERO

func _set_velocity(body: Node3D, value: Vector3) -> void:
	if body is RigidBody3D: body.linear_velocity = value
	elif body is CharacterBody3D: body.velocity = value

func _spawn_placement_flash(position: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 7.0
	light.omni_range = 4.5
	get_tree().current_scene.add_child(light)
	light.global_position = position
	_expire_flash(light)

func _expire_flash(light: OmniLight3D) -> void:
	await get_tree().create_timer(0.13).timeout
	if is_instance_valid(light): light.queue_free()

func clear_portals() -> void:
	for portal in portals:
		if is_instance_valid(portal): portal.queue_free()
	portals = [null, null]
