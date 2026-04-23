class_name WeaponManager
extends Node
## Handles weapon draw/sheath animations using a bone-filtered AnimationPlayer
## layered on top of the main AnimationTree.

@export var draw_weapon_anim: StringName = &"npc_sword_shield/draw_sword_2"
@export var sheath_weapon_anim: StringName = &"npc_sword_shield/sheath_sword_1"

var _weapon_drawn: bool = false
var _draw_sheath_active: bool = false
var _drawing_weapon: bool = false
var _seax_node: Node
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _right_arm_indices: Array[int] = []
var _right_arm_bone_names: Array[String] = []
var _draw_sheath_player: AnimationPlayer


func _ready() -> void:
	var player := get_parent() as CharacterBody3D
	if not player:
		return
	_anim_player = player.get_node_or_null("xbot_root/AnimationPlayer") as AnimationPlayer
	_skeleton = player.get_node_or_null("xbot_root/Armature/Skeleton3D") as Skeleton3D
	var visual_root := player.get_node_or_null("xbot_root") as Node3D
	_seax_node = player.find_child("Seax", true, false)
	if _seax_node:
		_seax_node.visible = false
	_init_right_arm_bones()
	_init_draw_sheath_player(visual_root)


func is_weapon_drawn() -> bool:
	return _weapon_drawn


func is_animating() -> bool:
	return _draw_sheath_active


func toggle_weapon(in_combat: bool = false) -> void:
	if _weapon_drawn:
		sheath_weapon(in_combat)
	else:
		draw_weapon()


func draw_weapon() -> void:
	if _weapon_drawn or _draw_sheath_active:
		return
	if not _draw_sheath_player or not _draw_sheath_player.has_animation(&"draw"):
		_weapon_drawn = true
		if _seax_node:
			_seax_node.visible = true
		return
	_drawing_weapon = true
	_draw_sheath_active = true
	if _seax_node:
		_seax_node.visible = true
	_draw_sheath_player.play_with_capture(&"draw", 0.2)


func sheath_weapon(in_combat: bool) -> void:
	if not _weapon_drawn or _draw_sheath_active:
		return
	if in_combat:
		return
	if not _draw_sheath_player or not _draw_sheath_player.has_animation(&"sheath"):
		push_warning("[WeaponManager] Missing filtered sheath animation")
		_weapon_drawn = false
		if _seax_node:
			_seax_node.visible = false
		return
	_drawing_weapon = false
	_draw_sheath_active = true
	_draw_sheath_player.play_with_capture(&"sheath", 0.2)


func cancel() -> void:
	if _draw_sheath_player:
		_draw_sheath_player.stop()
	_draw_sheath_active = false
	if _drawing_weapon and _seax_node:
		_seax_node.visible = false


func _on_draw_sheath_finished(_anim_name: StringName) -> void:
	_draw_sheath_active = false
	_weapon_drawn = _drawing_weapon
	if not _weapon_drawn and _seax_node:
		_seax_node.visible = false


func _init_right_arm_bones() -> void:
	if not _skeleton:
		return
	for candidate in ["shoulder.R", "arm.R", "upper_arm.R", "UpperArm.R", "RightArm", "right_upper_arm"]:
		var idx := _skeleton.find_bone(candidate)
		if idx >= 0:
			_right_arm_indices = _collect_bone_descendants_sorted(idx)
			for bone_idx in _right_arm_indices:
				_right_arm_bone_names.append(_skeleton.get_bone_name(bone_idx))
			break
	for spine_bone in ["spine", "spine1", "spine2", "neck", "head", "headtop_end",
			"Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]:
		var idx := _skeleton.find_bone(spine_bone)
		if idx >= 0 and spine_bone not in _right_arm_bone_names:
			_right_arm_bone_names.append(spine_bone)
	if _right_arm_bone_names.is_empty():
		push_warning("[WeaponManager] Could not find right arm or spine bones.")


func _collect_bone_descendants_sorted(parent_idx: int) -> Array[int]:
	var result: Array[int] = [parent_idx]
	for child_idx in _skeleton.get_bone_children(parent_idx):
		result.append_array(_collect_bone_descendants_sorted(child_idx))
	result.sort()
	return result


func _init_draw_sheath_player(visual_root: Node3D) -> void:
	if not visual_root:
		return
	_draw_sheath_player = AnimationPlayer.new()
	_draw_sheath_player.name = "DrawSheathPlayer"
	visual_root.add_child(_draw_sheath_player)
	_draw_sheath_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_draw_sheath_player.animation_finished.connect(_on_draw_sheath_finished)
	var lib := AnimationLibrary.new()
	var draw_filtered := _create_arm_filtered_animation(draw_weapon_anim)
	if draw_filtered:
		lib.add_animation(&"draw", draw_filtered)
	var sheath_filtered := _create_arm_filtered_animation(sheath_weapon_anim)
	if sheath_filtered:
		lib.add_animation(&"sheath", sheath_filtered)
	_draw_sheath_player.add_animation_library(&"", lib)


func _create_arm_filtered_animation(source_name: StringName) -> Animation:
	if not _anim_player or not _anim_player.has_animation(source_name):
		push_warning("[WeaponManager] Source animation '%s' not found for arm filter" % source_name)
		return null
	var source := _anim_player.get_animation(source_name)
	if not source:
		return null
	var filtered := Animation.new()
	filtered.length = source.length
	filtered.loop_mode = source.loop_mode
	for t in source.get_track_count():
		var path_str := str(source.track_get_path(t))
		var colon := path_str.rfind(":")
		if colon < 0:
			continue
		var bone_name := path_str.substr(colon + 1)
		if bone_name not in _right_arm_bone_names:
			continue
		var idx := filtered.add_track(source.track_get_type(t))
		filtered.track_set_path(idx, source.track_get_path(t))
		filtered.track_set_interpolation_type(idx, source.track_get_interpolation_type(t))
		for k in source.track_get_key_count(t):
			filtered.track_insert_key(
				idx,
				source.track_get_key_time(t, k),
				source.track_get_key_value(t, k),
				source.track_get_key_transition(t, k)
			)
	if filtered.get_track_count() == 0:
		push_warning("[WeaponManager] No right-arm tracks found in '%s' (arm bones: %s)" % [source_name, _right_arm_bone_names])
		return null
	return filtered
