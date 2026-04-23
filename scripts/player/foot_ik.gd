extends Node
## Procedural foot IK for humanoid terrain adaptation.
## Raycasts below each animated foot position, adjusts hip height, and solves
## two-bone IK per leg so feet land naturally on uneven ground.
## Call update() from the owning controller after animation updates so the
## overrides land on top of the animated pose.

# ── Exports ──────────────────────────────────────────────────────────────────
@export var enabled: bool = true
@export var ik_interp_speed: float = 10.0   ## Foot target interpolation
@export var hip_interp_speed: float = 8.0   ## Hip offset interpolation
@export var ray_up: float = 0.5             ## Ray start above animated foot
@export var ray_down: float = 1.5           ## Ray end below animated foot
@export var foot_height: float = 0.05       ## Small clearance above ground
@export var max_step: float = 0.4           ## Max terrain offset we IK for
@export var ground_mask: int = 1            ## Physics collision mask for ground
@export var skeleton_path: NodePath

# ── Internal refs ────────────────────────────────────────────────────────────
var _skeleton: Skeleton3D
var _character: CharacterBody3D
var _terrain_nodes: Array[Node] = []

# ── Bone indices (discovered at runtime) ─────────────────────────────────────
var _hips_idx: int = -1
var _l_upper_idx: int = -1
var _l_lower_idx: int = -1
var _l_foot_idx: int = -1
var _r_upper_idx: int = -1
var _r_lower_idx: int = -1
var _r_foot_idx: int = -1

# ── Bone chain lengths (from rest pose) ─────────────────────────────────────
var _l_upper_len: float = 0.0
var _l_lower_len: float = 0.0
var _r_upper_len: float = 0.0
var _r_lower_len: float = 0.0

# ── Smoothed runtime state ──────────────────────────────────────────────────
var _hip_offset: float = 0.0
var _l_foot_offset: float = 0.0
var _r_foot_offset: float = 0.0
var _l_normal: Vector3 = Vector3.UP
var _r_normal: Vector3 = Vector3.UP

# ── Initialisation ───────────────────────────────────────────────────────────

func _ready() -> void:
	_character = get_parent() as CharacterBody3D
	if not _character:
		push_error("[FootIK] Parent must be CharacterBody3D")
		enabled = false
		return
	_skeleton = _resolve_skeleton()
	if not _skeleton:
		push_error("[FootIK] Skeleton3D not found for parent %s" % _character.name)
		enabled = false
		return
	_init_bones()


func _resolve_skeleton() -> Skeleton3D:
	if not skeleton_path.is_empty():
		var explicit := _character.get_node_or_null(skeleton_path) as Skeleton3D
		if explicit:
			return explicit
	for candidate in [
		^"xbot_root/Armature/Skeleton3D",
		^"ybot_root/Armature/Skeleton3D",
		^"Armature/Skeleton3D",
	]:
		var skeleton := _character.get_node_or_null(candidate) as Skeleton3D
		if skeleton:
			return skeleton
	return _character.find_child("Skeleton3D", true, false) as Skeleton3D

func _init_bones() -> void:
	_hips_idx = _find_bone(["hips", "Hips", "pelvis", "mixamorig_Hips", "mixamorig:Hips"])
	var left_chain := _resolve_leg_chain(
		["LeftFoot", "foot.L", "left_foot", "mixamorig_LeftFoot", "mixamorig:LeftFoot"],
		["LeftLeg", "lower_leg.L", "leg.L", "shin.L", "calf.L", "left_lower_leg", "mixamorig_LeftLeg", "mixamorig:LeftLeg"],
		["LeftUpLeg", "upper_leg.L", "upperleg.L", "thigh.L", "left_upper_leg", "mixamorig_LeftUpLeg", "mixamorig:LeftUpLeg"]
	)
	_l_upper_idx = int(left_chain.get("upper", -1))
	_l_lower_idx = int(left_chain.get("lower", -1))
	_l_foot_idx = int(left_chain.get("foot", -1))
	var right_chain := _resolve_leg_chain(
		["RightFoot", "foot.R", "right_foot", "mixamorig_RightFoot", "mixamorig:RightFoot"],
		["RightLeg", "lower_leg.R", "leg.R", "shin.R", "calf.R", "right_lower_leg", "mixamorig_RightLeg", "mixamorig:RightLeg"],
		["RightUpLeg", "upper_leg.R", "upperleg.R", "thigh.R", "right_upper_leg", "mixamorig_RightUpLeg", "mixamorig:RightUpLeg"]
	)
	_r_upper_idx = int(right_chain.get("upper", -1))
	_r_lower_idx = int(right_chain.get("lower", -1))
	_r_foot_idx = int(right_chain.get("foot", -1))

	var all_ok := (_hips_idx >= 0 and _l_upper_idx >= 0 and _l_lower_idx >= 0
		and _l_foot_idx >= 0 and _r_upper_idx >= 0 and _r_lower_idx >= 0
		and _r_foot_idx >= 0)
	if not all_ok:
		push_warning("[FootIK] Missing bones – IK disabled. Dumping skeleton:")
		for i in _skeleton.get_bone_count():
			print("  [%d] %s" % [i, _skeleton.get_bone_name(i)])
		enabled = false
		return

	# Bone lengths from rest pose
	_l_upper_len = _skeleton.get_bone_global_rest(_l_upper_idx).origin.distance_to(
		_skeleton.get_bone_global_rest(_l_lower_idx).origin)
	_l_lower_len = _skeleton.get_bone_global_rest(_l_lower_idx).origin.distance_to(
		_skeleton.get_bone_global_rest(_l_foot_idx).origin)
	_r_upper_len = _skeleton.get_bone_global_rest(_r_upper_idx).origin.distance_to(
		_skeleton.get_bone_global_rest(_r_lower_idx).origin)
	_r_lower_len = _skeleton.get_bone_global_rest(_r_lower_idx).origin.distance_to(
		_skeleton.get_bone_global_rest(_r_foot_idx).origin)

	print("[FootIK] Ready  L_upper=%.3f L_lower=%.3f  R_upper=%.3f R_lower=%.3f" % [
		_l_upper_len, _l_lower_len, _r_upper_len, _r_lower_len])

func _find_bone(names: Array) -> int:
	for bone_name in names:
		var idx := _find_bone_normalized(str(bone_name))
		if idx >= 0:
			return idx
	push_warning("[FootIK] Bone not found, tried: %s" % str(names))
	return -1


func _find_bone_normalized(bone_name: String) -> int:
	var exact := _skeleton.find_bone(bone_name)
	if exact >= 0:
		return exact
	var target := _normalize_bone_name(bone_name)
	for idx in _skeleton.get_bone_count():
		if _normalize_bone_name(_skeleton.get_bone_name(idx)) == target:
			return idx
	return -1


func _normalize_bone_name(bone_name: String) -> String:
	var normalized := bone_name.to_lower()
	normalized = normalized.replace("mixamorig:", "")
	normalized = normalized.replace("mixamorig_", "")
	normalized = normalized.replace("-", "")
	normalized = normalized.replace("_", "")
	normalized = normalized.replace(".", "")
	normalized = normalized.replace(" ", "")
	return normalized


func _resolve_leg_chain(foot_names: Array, lower_names: Array, upper_names: Array) -> Dictionary:
	var foot_idx := _find_bone(foot_names)
	var lower_idx := _find_bone(lower_names)
	var upper_idx := _find_bone(upper_names)
	if foot_idx >= 0 and lower_idx < 0:
		lower_idx = _skeleton.get_bone_parent(foot_idx)
	if lower_idx >= 0 and upper_idx < 0:
		upper_idx = _skeleton.get_bone_parent(lower_idx)
	if foot_idx < 0 and lower_idx >= 0:
		for child_idx in _skeleton.get_bone_count():
			if _skeleton.get_bone_parent(child_idx) == lower_idx:
				var child_name := _normalize_bone_name(_skeleton.get_bone_name(child_idx))
				if child_name.contains("foot"):
					foot_idx = child_idx
					break
	return {
		"upper": upper_idx,
		"lower": lower_idx,
		"foot": foot_idx,
	}

# ── Public API (called by player_controller before head-look) ───────────────

func update(delta: float) -> void:
	if not enabled:
		return
	if not _character.is_on_floor():
		_fade_out(delta)
		return
	_apply_foot_ik(delta)


func clear_overrides() -> void:
	_hip_offset = 0.0
	_l_foot_offset = 0.0
	_r_foot_offset = 0.0
	_clear_overrides()

# ── Core IK logic ────────────────────────────────────────────────────────────

func _fade_out(delta: float) -> void:
	var t := clampf(ik_interp_speed * delta, 0.0, 1.0)
	_hip_offset = lerpf(_hip_offset, 0.0, t)
	_l_foot_offset = lerpf(_l_foot_offset, 0.0, t)
	_r_foot_offset = lerpf(_r_foot_offset, 0.0, t)
	if absf(_hip_offset) < 0.001 and absf(_l_foot_offset) < 0.001 and absf(_r_foot_offset) < 0.001:
		_clear_overrides()

func _apply_foot_ik(delta: float) -> void:
	var skel_xform := _skeleton.global_transform

	# ── 1. Clear our overrides so we get clean animated poses ────────────
	_clear_overrides()

	# ── 2. Read animated bone poses (skeleton space) ─────────────────────
	var hips_pose   := _skeleton.get_bone_global_pose(_hips_idx)
	var l_up_pose   := _skeleton.get_bone_global_pose(_l_upper_idx)
	var l_lo_pose   := _skeleton.get_bone_global_pose(_l_lower_idx)
	var l_ft_pose   := _skeleton.get_bone_global_pose(_l_foot_idx)
	var r_up_pose   := _skeleton.get_bone_global_pose(_r_upper_idx)
	var r_lo_pose   := _skeleton.get_bone_global_pose(_r_lower_idx)
	var r_ft_pose   := _skeleton.get_bone_global_pose(_r_foot_idx)

	# ── 3. World-space foot positions & ground raycasts ──────────────────
	var l_foot_world: Vector3 = skel_xform * l_ft_pose.origin
	var r_foot_world: Vector3 = skel_xform * r_ft_pose.origin

	var l_hit := _raycast_ground(l_foot_world)
	var r_hit := _raycast_ground(r_foot_world)

	# ── 4. Compute raw offsets (+ = foot needs to go up, – = down) ───────
	var l_raw := 0.0
	var l_norm := Vector3.UP
	if l_hit:
		l_raw = (l_hit.position.y + foot_height) - l_foot_world.y
		l_norm = l_hit.normal
		l_raw = clampf(l_raw, -max_step, max_step)

	var r_raw := 0.0
	var r_norm := Vector3.UP
	if r_hit:
		r_raw = (r_hit.position.y + foot_height) - r_foot_world.y
		r_norm = r_hit.normal
		r_raw = clampf(r_raw, -max_step, max_step)

	# ── 5. Smooth offsets ────────────────────────────────────────────────
	var t := clampf(ik_interp_speed * delta, 0.0, 1.0)
	_l_foot_offset = lerpf(_l_foot_offset, l_raw, t)
	_r_foot_offset = lerpf(_r_foot_offset, r_raw, t)
	_l_normal = _l_normal.lerp(l_norm, t).normalized()
	_r_normal = _r_normal.lerp(r_norm, t).normalized()

	# ── 6. Lower hips only when a foot target is actually out of reach ──
	var target_hip := _compute_required_hip_lowering(
		skel_xform,
		l_up_pose,
		r_up_pose,
		l_foot_world + Vector3(0.0, _l_foot_offset, 0.0),
		r_foot_world + Vector3(0.0, _r_foot_offset, 0.0)
	)
	_hip_offset = lerpf(_hip_offset, target_hip, clampf(hip_interp_speed * delta, 0.0, 1.0))

	# ── 7. Apply hips override ───────────────────────────────────────────
	var hip_offset_skel: Vector3 = skel_xform.basis.inverse() * Vector3(0.0, _hip_offset, 0.0)
	var hips_mod := hips_pose
	hips_mod.origin += hip_offset_skel
	_skeleton.set_bone_global_pose_override(_hips_idx, hips_mod, 1.0, true)

	# ── 8. Solve each leg ────────────────────────────────────────────────
	# Foot target in world, then convert to skeleton space
	var l_adj := _l_foot_offset - _hip_offset
	var l_target_world := l_foot_world + Vector3(0.0, l_adj, 0.0)
	var l_target_skel: Vector3 = skel_xform.affine_inverse() * l_target_world
	_solve_leg(l_up_pose, l_lo_pose, l_ft_pose, l_target_skel,
		_l_upper_idx, _l_lower_idx, _l_foot_idx,
		_l_upper_len, _l_lower_len, _l_normal, hip_offset_skel, skel_xform)

	var r_adj := _r_foot_offset - _hip_offset
	var r_target_world := r_foot_world + Vector3(0.0, r_adj, 0.0)
	var r_target_skel: Vector3 = skel_xform.affine_inverse() * r_target_world
	_solve_leg(r_up_pose, r_lo_pose, r_ft_pose, r_target_skel,
		_r_upper_idx, _r_lower_idx, _r_foot_idx,
		_r_upper_len, _r_lower_len, _r_normal, hip_offset_skel, skel_xform)


func _compute_required_hip_lowering(
	skell_xform: Transform3D,
	l_up_pose: Transform3D,
	r_up_pose: Transform3D,
	l_target_world: Vector3,
	r_target_world: Vector3
) -> float:
	var left_needed := _get_leg_required_lowering(skell_xform, l_up_pose.origin, l_target_world, _l_upper_len, _l_lower_len)
	var right_needed := _get_leg_required_lowering(skell_xform, r_up_pose.origin, r_target_world, _r_upper_len, _r_lower_len)
	var required := maxf(left_needed, right_needed)
	return -minf(required, max_step)


func _get_leg_required_lowering(
	skel_xform: Transform3D,
	hip_origin_skel: Vector3,
	foot_target_world: Vector3,
	upper_len: float,
	lower_len: float
) -> float:
	var hip_world: Vector3 = skel_xform * hip_origin_skel
	var max_reach := maxf(upper_len + lower_len - 0.01, 0.01)
	var dist := hip_world.distance_to(foot_target_world)
	if dist <= max_reach:
		return 0.0
	return dist - max_reach

# ── Two-bone IK solver ──────────────────────────────────────────────────────

func _solve_leg(
	upper_pose: Transform3D, lower_pose: Transform3D, foot_pose: Transform3D,
	foot_target: Vector3,
	upper_idx: int, lower_idx: int, foot_idx: int,
	upper_len: float, lower_len: float,
	_ground_normal: Vector3,
	hip_offset_skel: Vector3,
	_skel_xform: Transform3D
) -> void:
	# Joint positions in skeleton space (shifted by hip offset)
	var hip_pos: Vector3  = upper_pose.origin + hip_offset_skel
	var knee_pos: Vector3 = lower_pose.origin + hip_offset_skel
	var foot_pos: Vector3 = foot_pose.origin + hip_offset_skel

	# Direction & distance to target
	var to_target := foot_target - hip_pos
	var dist := to_target.length()

	# Clamp to reachable range
	var max_reach := upper_len + lower_len - 0.01
	var min_reach := absf(upper_len - lower_len) + 0.01
	dist = clampf(dist, min_reach, max_reach)
	to_target = to_target.normalized() * dist
	var clamped_target := hip_pos + to_target

	# ── Law of cosines: angle at hip ────────────────────────────────────
	var cos_hip := (upper_len * upper_len + dist * dist - lower_len * lower_len) / (2.0 * upper_len * dist)
	cos_hip = clampf(cos_hip, -1.0, 1.0)
	var hip_angle := acos(cos_hip)

	# ── Pole direction (keep knee bending in original direction) ─────────
	var fwd := to_target.normalized()
	var pole_hint := knee_pos - hip_pos
	pole_hint = pole_hint - fwd * pole_hint.dot(fwd)  # Project onto plane ⊥ fwd
	if pole_hint.length_squared() < 0.0001:
		pole_hint = Vector3.FORWARD
	pole_hint = pole_hint.normalized()

	# ── New knee position ────────────────────────────────────────────────
	var new_knee := hip_pos + fwd * (cos(hip_angle) * upper_len) + pole_hint * (sin(hip_angle) * upper_len)

	# ── Apply upper-leg rotation override ────────────────────────────────
	var old_dir := (knee_pos - hip_pos)
	var new_dir := (new_knee - hip_pos)
	if old_dir.length_squared() > 0.0001 and new_dir.length_squared() > 0.0001:
		old_dir = old_dir.normalized()
		new_dir = new_dir.normalized()
		var rot := _quat_between(old_dir, new_dir)
		var mod := Transform3D()
		mod.origin = hip_pos
		mod.basis = Basis(rot) * upper_pose.basis
		_skeleton.set_bone_global_pose_override(upper_idx, mod, 1.0, true)

	# ── Apply lower-leg rotation override ────────────────────────────────
	var old_lower_dir := (foot_pos - knee_pos)
	var new_lower_dir := (clamped_target - new_knee)
	if old_lower_dir.length_squared() > 0.0001 and new_lower_dir.length_squared() > 0.0001:
		old_lower_dir = old_lower_dir.normalized()
		new_lower_dir = new_lower_dir.normalized()
		var rot := _quat_between(old_lower_dir, new_lower_dir)
		var mod := Transform3D()
		mod.origin = new_knee
		mod.basis = Basis(rot) * lower_pose.basis
		_skeleton.set_bone_global_pose_override(lower_idx, mod, 1.0, true)

	# Preserve the animated ankle orientation. This rig's foot axis does not
	# match the solver's old "basis.y is sole-up" assumption, which bends feet.
	var foot_mod := Transform3D()
	foot_mod.origin = clamped_target
	foot_mod.basis = foot_pose.basis
	_skeleton.set_bone_global_pose_override(foot_idx, foot_mod, 1.0, true)

# ── Helpers ──────────────────────────────────────────────────────────────────

func _clear_overrides() -> void:
	for idx in [_hips_idx, _l_upper_idx, _l_lower_idx, _l_foot_idx,
			_r_upper_idx, _r_lower_idx, _r_foot_idx]:
		if idx >= 0:
			_skeleton.set_bone_global_pose_override(idx, Transform3D.IDENTITY, 0.0, true)

func _raycast_ground(foot_world: Vector3) -> Dictionary:
	var space := _character.get_world_3d().direct_space_state
	var from := foot_world + Vector3.UP * ray_up
	var to := foot_world - Vector3.UP * ray_down
	var query := PhysicsRayQueryParameters3D.create(from, to, ground_mask)
	query.exclude = [_character.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return hit
	return _sample_terrain_ground(foot_world, from.y, to.y)


func _sample_terrain_ground(foot_world: Vector3, max_y: float, min_y: float) -> Dictionary:
	var best_hit: Dictionary = {}
	var best_y := -INF
	for terrain in _get_terrain_nodes():
		if not is_instance_valid(terrain) or not ("data" in terrain):
			continue
		var data = terrain.data
		if data == null or not data.has_method("get_height"):
			continue
		var sample_pos := Vector3(foot_world.x, 0.0, foot_world.z)
		var height: float = data.get_height(sample_pos)
		if is_nan(height):
			continue
		if height > max_y or height < min_y:
			continue
		if height <= best_y:
			continue
		var hit_pos := Vector3(foot_world.x, height, foot_world.z)
		var normal := Vector3.UP
		if data.has_method("get_normal"):
			var sample_normal: Vector3 = data.get_normal(hit_pos)
			if not is_nan(sample_normal.x):
				normal = sample_normal.normalized()
		best_y = height
		best_hit = {
			"position": hit_pos,
			"normal": normal,
			"node": terrain,
		}
	return best_hit


func _get_terrain_nodes() -> Array[Node]:
	var needs_refresh := _terrain_nodes.is_empty()
	if not needs_refresh:
		for terrain in _terrain_nodes:
			if not is_instance_valid(terrain):
				needs_refresh = true
				break
	if not needs_refresh:
		return _terrain_nodes
	_terrain_nodes.clear()
	var grouped := get_tree().get_nodes_in_group("Terrain3D")
	for node in grouped:
		if node is Node:
			_terrain_nodes.append(node)
	if _terrain_nodes.is_empty():
		_find_terrains_recursive(get_tree().root)
	return _terrain_nodes


func _find_terrains_recursive(node: Node) -> void:
	if node.get_class() == "Terrain3D":
		_terrain_nodes.append(node)
		return
	for child in node.get_children():
		_find_terrains_recursive(child)

func _quat_between(from: Vector3, to: Vector3) -> Quaternion:
	var d := from.dot(to)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var perp := Vector3.RIGHT if absf(from.x) < 0.9 else Vector3.UP
		return Quaternion(from.cross(perp).normalized(), PI)
	return Quaternion(from.cross(to).normalized(), acos(clampf(d, -1.0, 1.0)))
