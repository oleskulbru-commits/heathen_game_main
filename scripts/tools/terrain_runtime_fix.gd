@tool
extends Node
## Disables Terrain3D's automatic checkered debug view at runtime and in the editor.
## When using a shader override with no painted textures, Terrain3D keeps
## re-enabling show_checkered. This script polls and disables it continuously.

var _terrain: Node = null
var _terrain_mat = null

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = _find_terrain(get_tree().root)
		if _terrain == null:
			return
		_terrain_mat = _terrain.get("material")

	# Disable on the Terrain3D node itself
	if _terrain.get("show_checkered"):
		_terrain.set("show_checkered", false)

	# Disable on the material
	if _terrain_mat and _terrain_mat.get("show_checkered"):
		_terrain_mat.set("show_checkered", false)


func _find_terrain(node):
	if node.get_class() == "Terrain3D":
		return node
	for child in node.get_children():
		var found = _find_terrain(child)
		if found:
			return found
	return null
