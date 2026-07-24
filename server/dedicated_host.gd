extends Node

func _ready() -> void:
	if not DedicatedServer.active:
		get_tree().change_scene_to_file("res://root.tscn")
