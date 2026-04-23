extends SceneTree
## Diagnostic: test root motion output by playing animation on xbot skeleton.

var _xbot_inst: Node
var _step := 0

func _init() -> void:
	pass

func _process(_delta: float) -> bool:
	_step += 1
	if _step == 1:
		_setup()
	elif _step == 5:
		_check_root_motion()
	elif _step >= 7:
		if _xbot_inst:
			_xbot_inst.queue_free()
		quit()
	return false

func _setup() -> void:
	# Load the xbot scene (which has AnimationTree + library)
	var scene: PackedScene = load("res://scenes/xbots/xbot_root.tscn")
	_xbot_inst = scene.instantiate()
	root.add_child(_xbot_inst)

	var tree: AnimationTree = _xbot_inst.get_node("AnimationTree")
	tree.active = true

	# Force locomotion with jog
	tree.set("parameters/StateMachine/conditions/is_moving", true)
	tree.set("parameters/StateMachine/conditions/is_stopping", false)
	tree.set("parameters/StateMachine/Locomotion/blend_position", 1.0)  # jog

	print("=== Root Motion Test ===")
	print("  root_motion_track: ", tree.root_motion_track)
	print("  root_motion_local: ", tree.root_motion_local)

func _check_root_motion() -> void:
	var tree: AnimationTree = _xbot_inst.get_node("AnimationTree")
	var pos := tree.get_root_motion_position()
	var rot := tree.get_root_motion_rotation()
	print("  get_root_motion_position(): ", pos)
	print("  get_root_motion_rotation(): ", rot)
	print("  |pos| = ", pos.length())

	# Also check the skeleton's root bone pose
	var skel: Skeleton3D = _xbot_inst.get_node("Armature/Skeleton3D")
	var root_idx := skel.find_bone("root")
	var hips_idx := skel.find_bone("hips")
	print("  root bone pose: ", skel.get_bone_pose(root_idx))
	print("  root bone global_pose.origin: ", skel.get_bone_global_pose(root_idx).origin)
	print("  hips bone global_pose.origin: ", skel.get_bone_global_pose(hips_idx).origin)
