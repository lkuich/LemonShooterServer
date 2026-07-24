extends Area3D

var damage_owner: Node
var zone_name := "torso"
var damage_multiplier := 1.0

func configure(owner_node: Node, zone: String, multiplier: float, shape: Shape3D, local_position: Vector3) -> void:
	damage_owner = owner_node
	zone_name = zone
	damage_multiplier = multiplier
	position = local_position
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

func apply_hit(amount: float, hit_position: Vector3, hit_normal: Vector3, attacker: Node) -> bool:
	if damage_owner and damage_owner.has_method("receive_zone_hit"):
		return damage_owner.receive_zone_hit(amount * damage_multiplier, zone_name, hit_position, hit_normal, attacker)
	return false
