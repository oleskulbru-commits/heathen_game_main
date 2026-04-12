## Shared constants and helpers for bandit component scripts.
## Preload with:  const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")

const LIB_NAME := &"Searching"
const LIB_PATH := "res://assets/animations/animation_libraries/npc_searching.res"

const LEFT_ARM_BONES: Array[String] = [
	"shoulder.L", "upper_arm.L", "forearm.L", "hand.L",
	"thumb.01.L", "thumb.02.L", "thumb.03.L",
	"f_index.01.L", "f_index.02.L", "f_index.03.L",
	"f_middle.01.L", "f_middle.02.L", "f_middle.03.L",
	"f_ring.01.L", "f_ring.02.L", "f_ring.03.L",
	"f_pinky.01.L", "f_pinky.02.L", "f_pinky.03.L",
]

const LOOK_AROUND_ANIMS: Array[String] = [
	"look_around_02",
	"look_around_03",
	"look_around_04",
	"looking_around",
]

const TORCH_GROUPS: Array[String] = ["torch", "flame"]

const BANDIT_EYE_HEIGHT := Vector3(0.0, 1.5, 0.0)
const PLAYER_CHEST_HEIGHT := Vector3(0.0, 1.0, 0.0)


static func reactivate_tree(anim_tree: AnimationTree) -> void:
	if anim_tree and not anim_tree.active:
		anim_tree.active = true


static func load_searching_library(anim_player: AnimationPlayer) -> void:
	if not anim_player:
		return
	var lib := load(LIB_PATH) as AnimationLibrary
	if lib and not anim_player.has_animation_library(LIB_NAME):
		anim_player.add_animation_library(LIB_NAME, lib)


static func get_all_torches(tree: SceneTree) -> Array[Node]:
	var torches: Array[Node] = []
	for group_name in TORCH_GROUPS:
		torches.append_array(tree.get_nodes_in_group(group_name))
		if not torches.is_empty():
			break
	return torches


static func resolve_visual_nodes(bandit: Node) -> Dictionary:
	var result := {"visual_root": null, "anim_player": null, "anim_tree": null, "skeleton": null}
	var vr: Node3D = bandit.get_node_or_null("ybot_root")
	if not vr:
		return result
	result["visual_root"] = vr
	result["anim_player"] = vr.get_node_or_null("AnimationPlayer")
	result["anim_tree"] = vr.get_node_or_null("AnimationTree")
	result["skeleton"] = vr.get_node_or_null("Armature/Skeleton3D")
	return result


static func suspicion_color(sus: float, tc: float, ta: float, tb: float) -> Color:
	if sus <= 0.0:
		return Color(0.2, 0.8, 0.2, 0.12)
	elif sus < tc:
		return Color(0.2, 0.8, 0.2, 0.12).lerp(Color(1.0, 0.9, 0.3, 0.18), sus / tc)
	elif sus < ta:
		return Color(1.0, 0.9, 0.3, 0.18).lerp(Color(1.0, 0.5, 0.0, 0.22), (sus - tc) / (ta - tc))
	elif sus < tb:
		return Color(1.0, 0.5, 0.0, 0.22).lerp(Color(1.0, 0.1, 0.1, 0.28), (sus - ta) / (tb - ta))
	else:
		return Color(1.0, 0.1, 0.1, 0.28)
