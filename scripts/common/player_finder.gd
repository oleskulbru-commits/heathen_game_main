extends RefCounted
## Single source of truth for locating the player node.

static func find(tree: SceneTree) -> CharacterBody3D:
	var players := tree.get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as CharacterBody3D
	var p := tree.root.find_child("Player", true, false)
	if p is CharacterBody3D:
		return p
	return null
