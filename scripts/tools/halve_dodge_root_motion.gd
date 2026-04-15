@tool
extends SceneTree
## Halves the root-bone displacement between 0.4 s and 0.7 s on all four
## dodge animations, then saves the modified library back to disk.
## Backs up the original to player_combat_backup.res first.

const LIB_PATH := "res://assets/animations/animation_libraries/player_combat.res"
const BACKUP_PATH := "res://assets/animations/animation_libraries/player_combat_backup.res"

const DODGE_NAMES: Array[StringName] = [
	&"standing_dodge_forward",
	&"standing_dodge_backward",
	&"standing_dodge_left",
	&"standing_dodge_right",
]

const T_START := 0.4
const T_END := 0.7
const SCALE := 0.5  # halve the displacement in this window


func _init() -> void:
	var lib: AnimationLibrary = load(LIB_PATH)
	if not lib:
		print("ERROR: could not load ", LIB_PATH)
		quit()
		return

	# ── Backup ──────────────────────────────────────────────────────────
	if not FileAccess.file_exists(BACKUP_PATH):
		var err := ResourceSaver.save(lib, BACKUP_PATH)
		if err != OK:
			print("WARNING: backup failed (error %d), proceeding anyway" % err)
		else:
			print("Backup saved to ", BACKUP_PATH)

	# ── Process each dodge animation ────────────────────────────────────
	for anim_name in DODGE_NAMES:
		var anim: Animation = lib.get_animation(anim_name)
		if not anim:
			print("SKIP: animation '%s' not found" % anim_name)
			continue
		_scale_root_track(anim, anim_name)

	# ── Save ────────────────────────────────────────────────────────────
	var err := ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\nSaved modified library to ", LIB_PATH)
	else:
		print("ERROR: save failed (error %d)" % err)
	quit()


func _scale_root_track(anim: Animation, anim_name: StringName) -> void:
	# Find track 0: Armature/Skeleton3D:root  POSITION_3D
	var track_idx := -1
	for t in anim.get_track_count():
		if str(anim.track_get_path(t)) == "Armature/Skeleton3D:root" \
				and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
			track_idx = t
			break
	if track_idx < 0:
		print("SKIP %s: no root POSITION_3D track" % anim_name)
		return

	var key_count := anim.track_get_key_count(track_idx)

	# Find the value at T_START by interpolation (or nearest key before it).
	var anchor: Vector3 = _interpolate_pos_at(anim, track_idx, T_START)

	print("\n--- %s  (keys=%d, anchor at %.2fs = %s) ---" % [anim_name, key_count, T_START, anchor])

	for k in key_count:
		var time := anim.track_get_key_time(track_idx, k)
		if time <= T_START:
			continue  # don't touch keys at or before the window start

		var old_val: Vector3 = anim.track_get_key_value(track_idx, k)
		var delta_from_anchor := old_val - anchor

		if time < T_END:
			# Inside the window: scale displacement from anchor by SCALE
			var new_val := anchor + delta_from_anchor * SCALE
			# Keep Y untouched (vertical shouldn't change)
			new_val.y = old_val.y
			anim.track_set_key_value(track_idx, k, new_val)
			print("  key %d  t=%.4f  %s -> %s" % [k, time, old_val, new_val])
		else:
			# After the window: shift by the total displacement reduction
			# so the tail doesn't jump. The reduction at T_END is:
			var val_at_end: Vector3 = _interpolate_pos_at(anim, track_idx, T_END)
			var end_delta := val_at_end - anchor
			var offset := end_delta * (1.0 - SCALE)
			var new_val := old_val - offset
			new_val.y = old_val.y
			anim.track_set_key_value(track_idx, k, new_val)
			if k < key_count and k <= anim.track_get_key_count(track_idx):
				print("  key %d  t=%.4f  %s -> %s  (shifted)" % [k, time, old_val, new_val])


func _interpolate_pos_at(anim: Animation, track_idx: int, time: float) -> Vector3:
	## Return the root position at an arbitrary time by finding the two bracketing
	## keys and linearly interpolating.
	var key_count := anim.track_get_key_count(track_idx)
	if key_count == 0:
		return Vector3.ZERO
	# Clamp to first/last
	if time <= anim.track_get_key_time(track_idx, 0):
		return anim.track_get_key_value(track_idx, 0)
	if time >= anim.track_get_key_time(track_idx, key_count - 1):
		return anim.track_get_key_value(track_idx, key_count - 1)
	for k in range(key_count - 1):
		var t0 := anim.track_get_key_time(track_idx, k)
		var t1 := anim.track_get_key_time(track_idx, k + 1)
		if t0 <= time and time <= t1:
			var frac := (time - t0) / (t1 - t0) if (t1 - t0) > 0.0001 else 0.0
			var v0: Vector3 = anim.track_get_key_value(track_idx, k)
			var v1: Vector3 = anim.track_get_key_value(track_idx, k + 1)
			return v0.lerp(v1, frac)
	return anim.track_get_key_value(track_idx, key_count - 1)
