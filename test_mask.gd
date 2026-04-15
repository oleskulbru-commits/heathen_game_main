extends SceneTree

func _init() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var player := scene.instantiate()
	root.add_child(player)
	await process_frame
	var overlay := player.get("_draw_sheath_player") as AnimationPlayer
	print("has_draw=", overlay != null and overlay.has_animation(&"draw"))
	print("has_sheath=", overlay != null and overlay.has_animation(&"sheath"))
	if player.has_method("_play_draw_weapon"):
		player.call("_play_draw_weapon")
	await process_frame
	print("playing_after_draw=", overlay != null and overlay.is_playing())
	quit()
