extends Node

const MIN_DAMAGE_SPEED := 10.0
const ACTIVE_LIFETIME_MSEC := 3000

var source_body: RigidBody3D
var attacker: Node
var expires_at := 0

func configure(body: RigidBody3D, damage_attacker: Node) -> void:
	source_body = body
	attacker = damage_attacker
	expires_at = Time.get_ticks_msec() + ACTIVE_LIFETIME_MSEC
	source_body.contact_monitor = true
	source_body.max_contacts_reported = maxi(source_body.max_contacts_reported, 8)
	if not source_body.body_entered.is_connected(_on_body_entered):
		source_body.body_entered.connect(_on_body_entered)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(source_body) or Time.get_ticks_msec() >= expires_at:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(source_body) or body == attacker:
		return
	var target: Node = body
	var damage_owner = body.get("damage_owner")
	if damage_owner is Node:
		target = damage_owner
	if not target.is_in_group("combatants") or target.get("alive") != true:
		return
	var impact_speed := source_body.linear_velocity.length()
	if impact_speed < MIN_DAMAGE_SPEED:
		return
	var damage := clampf((impact_speed - 8.0) * 4.0, 10.0, 85.0)
	var target_node := target as Node3D
	if not target_node:
		return
	var direction := (target_node.global_position - source_body.global_position).normalized()
	if target.has_method("receive_zone_hit"):
		target.receive_zone_hit(damage, "impact", target_node.global_position, direction, attacker)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage, source_body.global_position, attacker)
	queue_free()
