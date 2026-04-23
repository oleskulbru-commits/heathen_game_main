class_name AnimationResolver
## Static utility for fuzzy animation name resolution.
## Handles library prefix variations (npc_axe/, player_combat/, etc.),
## underscore/slash mismatches, and keyword-based fallback matching.
##
## Usage:
##   var resolved := AnimationResolver.resolve(&"npc_axe/standing_melee_attack_downward", anim_player)


## Resolve an animation name against an AnimationPlayer's library.
## Tries exact match first, then common prefix/separator variants, then
## normalized key matching, then keyword-based fallback.
static func resolve(raw_name: StringName, anim_player: AnimationPlayer) -> StringName:
	if not anim_player:
		return raw_name
	var raw := str(raw_name)
	# Stage 1: direct candidates from common prefix/separator swaps
	var candidates: Array[String] = [raw]
	if raw.contains("npc/axe/"):
		candidates.append(raw.replace("npc/axe/", "npc_axe/"))
	if raw.contains("/"):
		candidates.append(raw.replace("/", "_"))
	if raw.begins_with("npc_axe_"):
		candidates.append(raw.replace("npc_axe_", "npc_axe/"))
	if raw.begins_with("player_combat_"):
		candidates.append(raw.replace("player_combat_", "player_combat/"))
	if raw.begins_with("PlayerDeaths/"):
		candidates.append(raw.replace("PlayerDeaths/", "player_deaths/"))
	elif raw.begins_with("player_deaths/"):
		candidates.append(raw.replace("player_deaths/", "PlayerDeaths/"))
	if raw.contains(" "):
		candidates.append(raw.replace(" ", "_"))
	if raw.contains(" from ") or raw.contains(" left") or raw.contains(" right"):
		var normalized := raw.replace(" from ", "_from_")
		normalized = normalized.replace(" left", "_left")
		normalized = normalized.replace(" right", "_right")
		candidates.append(normalized)
		if normalized.begins_with("npc_axe_"):
			candidates.append(normalized.replace("npc_axe_", "npc_axe/"))
	for candidate in candidates:
		var animation_name := StringName(candidate)
		if anim_player.has_animation(animation_name):
			return animation_name

	# Stage 2: normalized key matching (strip all non-alphanumeric)
	var target_key := _normalize_key(raw)
	var best_suffix := StringName()
	for anim_name in anim_player.get_animation_list():
		var anim_key := _normalize_key(str(anim_name))
		if anim_key == target_key:
			return anim_name
		if anim_key.ends_with(target_key) or target_key.ends_with(anim_key):
			best_suffix = anim_name
	if not best_suffix.is_empty():
		return best_suffix

	# Stage 3: keyword-based fallback
	for anim_name in anim_player.get_animation_list():
		var anim_key := _normalize_key(str(anim_name))
		# Attack anims
		if target_key.contains("downward") and anim_key.contains("meleeattack") and anim_key.contains("downward"):
			return anim_name
		if target_key.contains("backhand") and anim_key.contains("meleeattack") and anim_key.contains("backhand"):
			return anim_name
		if target_key.contains("horizontal") and anim_key.contains("meleeattack") and anim_key.contains("horizontal"):
			return anim_name
		if target_key.contains("360high") and anim_key.contains("360"):
			return anim_name
		if target_key.contains("kick") and anim_key.contains("kick"):
			return anim_name
		# Hit reacts
		if target_key.contains("reactlarge") and anim_key.contains("react") and anim_key.contains("large"):
			if target_key.contains("gut") and anim_key.contains("gut"):
				return anim_name
			if target_key.contains("left") and anim_key.contains("left"):
				return anim_name
			if target_key.contains("right") and anim_key.contains("right"):
				return anim_name
		# Block
		if target_key.contains("block") and anim_key.contains("block"):
			return anim_name
		# Dodge / dive
		if target_key.contains("dodge") and anim_key.contains("dodge"):
			return anim_name
		if target_key.contains("dive") and anim_key.contains("dive"):
			return anim_name

	# Nothing found — return last candidate (most likely the original)
	return StringName(candidates[-1])


## Strip everything except lowercase letters and digits.
static func _normalize_key(value: String) -> String:
	var lowered := value.to_lower()
	var result := ""
	for ch in lowered:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			result += ch
	return result
