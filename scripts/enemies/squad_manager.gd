extends Node

## Manages a squad of bandits in a camp / area.
## Discovers nearby bandits (via "bandit" group), assigns tactical roles
## (investigator, watcher, searcher, torch-grabber), and relays group signals
## so bandits coordinate without each one needing global awareness.

enum Role { IDLE, INVESTIGATOR, WATCHER, SEARCHER, TORCH_GRABBER }

@export var recruit_radius: float = 50.0
@export var reassign_cooldown: float = 2.0

var members: Array[CharacterBody3D] = []
var _roles: Dictionary = {}  # CharacterBody3D -> Role
var _reassign_timer: float = 0.0
var _alert_active: bool = false
var _last_known_pos: Vector3 = Vector3.INF


func _ready() -> void:
	# Defer so all bandits have run _ready first.
	call_deferred("_recruit_nearby")


func _physics_process(delta: float) -> void:
	_prune_dead()
	if _reassign_timer > 0.0:
		_reassign_timer = maxf(_reassign_timer - delta, 0.0)


# --- Public API ---

func get_role(bandit: CharacterBody3D) -> Role:
	return _roles.get(bandit, Role.IDLE)


func raise_alarm(caller: CharacterBody3D, threat_pos: Vector3) -> void:
	if _alert_active and _reassign_timer > 0.0:
		return
	_alert_active = true
	_last_known_pos = threat_pos
	_reassign_timer = reassign_cooldown
	_assign_combat_roles(caller, threat_pos)


func update_threat_position(pos: Vector3) -> void:
	_last_known_pos = pos


func stand_down() -> void:
	_alert_active = false
	_last_known_pos = Vector3.INF
	for member in members:
		_roles[member] = Role.IDLE


func request_help(caller: CharacterBody3D, caller_pos: Vector3) -> void:
	for member in members:
		if member == caller:
			continue
		var brain := member.get_node_or_null("BanditBrain") as Node
		if not brain:
			continue
		if brain.alert_level >= 3:
			continue
		brain.force_combat(caller_pos)
	raise_alarm(caller, caller_pos)


# --- Internal plumbing ---

func _recruit_nearby() -> void:
	var origin := (get_parent() as Node3D).global_position if get_parent() is Node3D else Vector3.ZERO
	for node in get_tree().get_nodes_in_group("bandit"):
		if node is CharacterBody3D and node.global_position.distance_to(origin) <= recruit_radius:
			_register(node)


func _register(bandit: CharacterBody3D) -> void:
	if bandit in members:
		return
	members.append(bandit)
	_roles[bandit] = Role.IDLE
	var brain := bandit.get_node_or_null("BanditBrain") as Node
	if brain:
		if brain.has_signal("entered_combat"):
			brain.entered_combat.connect(_on_member_entered_combat.bind(bandit))
		if brain.has_signal("call_for_help"):
			brain.call_for_help.connect(_on_member_call_for_help)
		if brain.has_signal("emotional_state_changed"):
			brain.emotional_state_changed.connect(_on_member_emotion_changed.bind(bandit))


func _prune_dead() -> void:
	var i := members.size() - 1
	while i >= 0:
		var m := members[i]
		if not is_instance_valid(m):
			members.remove_at(i)
			_roles.erase(m)
		elif m is ICombatTarget and m.is_dead():
			members.remove_at(i)
			_roles.erase(m)
		i -= 1


func _assign_combat_roles(caller: CharacterBody3D, threat_pos: Vector3) -> void:
	var alive := _get_alive_members()
	if alive.is_empty():
		return

	# 1. Caller is the investigator (closest / first responder).
	if caller in alive:
		_roles[caller] = Role.INVESTIGATOR
		alive.erase(caller)

	# 2. Find best torch-grabber: pick the one nearest a torch (if any).
	var torch_grabber: CharacterBody3D = null
	var best_torch_dist := INF
	for member in alive:
		var ts := member.get_node_or_null("BanditTorchSearch") as Node
		if ts and ts.has_method("get_nearest_torch_distance"):
			var d: float = ts.get_nearest_torch_distance()
			if d < best_torch_dist:
				best_torch_dist = d
				torch_grabber = member
	if torch_grabber:
		_roles[torch_grabber] = Role.TORCH_GRABBER
		alive.erase(torch_grabber)

	# 3. Distribute remaining: closest half become searchers, rest watchers.
	alive.sort_custom(func(a, b):
		return a.global_position.distance_squared_to(threat_pos) < b.global_position.distance_squared_to(threat_pos)
	)
	var searcher_count := ceili(alive.size() / 2.0)
	for idx in alive.size():
		if idx < searcher_count:
			_roles[alive[idx]] = Role.SEARCHER
		else:
			_roles[alive[idx]] = Role.WATCHER

	# 4. Push search positions to brains.
	var searchers: Array[CharacterBody3D] = []
	for member in members:
		if _roles.get(member, Role.IDLE) == Role.SEARCHER:
			searchers.append(member)
	var positions := _fan_search_positions(threat_pos, searchers.size())
	for j in searchers.size():
		var brain := searchers[j].get_node_or_null("BanditBrain") as Node
		if brain and j < positions.size():
			brain.remember_last_known_position(positions[j])


func _fan_search_positions(center: Vector3, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var radius := 10.0
	for i in count:
		var angle := TAU * float(i) / float(count)
		out.append(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return out


func _get_alive_members() -> Array[CharacterBody3D]:
		var alive: Array[CharacterBody3D] = []
		for m in members:
			if is_instance_valid(m) and (not (m is ICombatTarget) or not m.is_dead()):
				alive.append(m)
		return alive


# --- Signal callbacks ---

func _on_member_entered_combat(bandit: CharacterBody3D) -> void:
	var brain := bandit.get_node_or_null("BanditBrain") as Node
	var pos: Vector3 = brain.get_player_position() if brain else bandit.global_position
	raise_alarm(bandit, pos)


func _on_member_call_for_help(caller: CharacterBody3D, caller_pos: Vector3) -> void:
	request_help(caller, caller_pos)


func _on_member_emotion_changed(new_state: int, bandit: CharacterBody3D) -> void:
	# If a member is terrified, remove them from active roles.
	if new_state == 1:  # TERRIFIED
		_roles[bandit] = Role.IDLE
