extends Node3D

signal objective_updated(text: String)
signal status_updated(text: String)
signal prompt_updated(text: String)
signal progress_updated(text: String)
signal level_completed()

@onready var player = $Player
@onready var start_marker: Marker3D = $StartMarker
@onready var quiet_place_marker: Marker3D = $QuietPlaceMarker
@onready var rowan_area: Area3D = $RowanArea
@onready var ash_area: Area3D = $AshArea
@onready var tallow_area: Area3D = $TallowArea
@onready var silver_area: Area3D = $SilverArea
@onready var wax_area: Area3D = $WaxArea
@onready var bone_area: Area3D = $BoneArea
@onready var quiet_place_area: Area3D = $QuietPlaceArea
@onready var boat_area: Area3D = $BoatArea
@onready var rowan_prop: MeshInstance3D = $RowanProp
@onready var ash_prop: MeshInstance3D = $AshProp
@onready var tallow_prop: Node3D = $TallowCache
@onready var tallow_light: OmniLight3D = $TallowLight
@onready var silver_prop: Node3D = $SilverCache
@onready var wax_prop: MeshInstance3D = $WaxProp
@onready var bone_prop: MeshInstance3D = $BoneProp
@onready var quiet_place_light: OmniLight3D = $QuietPlaceLight
@onready var boat_light: OmniLight3D = $BoatLight
@onready var village_enforcer = $VillageEnforcer
@onready var final_enforcer = $FinalEnforcer

var _woods_components := {
	"rowan": false,
	"grave_ash": false,
	"black_tallow": false,
}
var _village_components := {
	"silver_thread": false,
	"church_wax": false,
	"saint_bone": false,
}
var _interaction_target: String = ""
var _quiet_place_bound: bool = false
var _advanced_rite_crafted: bool = false
var _advanced_rite_spent: bool = false
var _escaped: bool = false

func _ready() -> void:
	player.set_spawn_transform(start_marker.global_transform)
	player.status_changed.connect(_relay_status)
	player.rite_state_changed.connect(_on_player_rite_state_changed)
	village_enforcer.awareness_changed.connect(_on_enforcer_awareness_changed)
	final_enforcer.awareness_changed.connect(_on_enforcer_awareness_changed)
	_ensure_area_connections(rowan_area, "rowan")
	_ensure_area_connections(ash_area, "grave_ash")
	_ensure_area_connections(tallow_area, "black_tallow")
	_ensure_area_connections(silver_area, "silver_thread")
	_ensure_area_connections(wax_area, "church_wax")
	_ensure_area_connections(bone_area, "saint_bone")
	_ensure_area_connections(quiet_place_area, "quiet_place")
	_ensure_area_connections(boat_area, "boat")
	objective_updated.emit(_build_objective_text())
	status_updated.emit("Gather what the woods offer, find the Quiet Place, and do not walk into the village unprepared.")
	prompt_updated.emit("")
	progress_updated.emit(_build_progress_text())

func get_player():
	return player

func get_current_objective() -> String:
	return _build_objective_text()

func get_current_status() -> String:
	if _escaped:
		return "You clear the shoreline and push out into the fjord."
	if _advanced_rite_spent:
		return "The rite is spent. Reach the boat before the veil fully leaves the water."
	if _advanced_rite_crafted:
		return "The advanced rite is ready. Press Q to veil yourself and pass the watcher by the dock."
	if _all_village_components_gathered():
		return "Return to the Quiet Place in the hunting cabin and bind the advanced rite."
	if _quiet_place_bound and _all_woods_components_gathered():
		return "Enter the village and steal the advanced rite components without getting pinned down."
	if _all_woods_components_gathered():
		return "You have the first components. Step into the hunting cabin and bind the Quiet Place."
	return "Gather what the woods offer, find the Quiet Place, and do not walk into the village unprepared."

func get_current_prompt() -> String:
	return _build_prompt_text()

func get_current_progress_text() -> String:
	return _build_progress_text()

func _unhandled_input(event: InputEvent) -> void:
	if _escaped or _interaction_target == "":
		return
	if event.is_action_pressed("interact"):
		_handle_interaction()

func _relay_status(text: String) -> void:
	status_updated.emit(text)

func _ensure_area_connections(area: Area3D, interaction_id: String) -> void:
	area.body_entered.connect(_on_interaction_area_entered.bind(interaction_id))
	area.body_exited.connect(_on_interaction_area_exited.bind(interaction_id))

func _on_interaction_area_entered(body: Node3D, interaction_id: String) -> void:
	if body != player:
		return
	_interaction_target = interaction_id
	prompt_updated.emit(_build_prompt_text())
	if interaction_id == "boat" and _advanced_rite_spent and not _escaped:
		status_updated.emit("The boat is ready. Push off before the enforcers close in.")

func _on_interaction_area_exited(body: Node3D, interaction_id: String) -> void:
	if body != player or _interaction_target != interaction_id:
		return
	_interaction_target = ""
	prompt_updated.emit("")

func _handle_interaction() -> void:
	match _interaction_target:
		"rowan":
			_collect_component(_woods_components, "rowan", rowan_prop, "You strip rowan bark from a wind-cut trunk and wrap it in cloth.")
		"grave_ash":
			_collect_component(_woods_components, "grave_ash", ash_prop, "You gather grave ash from a cold patch of disturbed earth.")
		"black_tallow":
			_collect_tallow()
		"silver_thread":
			_collect_village_component("silver_thread", silver_prop, "You steal silver thread from a loom left too close to the quay light.")
		"church_wax":
			_collect_village_component("church_wax", wax_prop, "You cut church wax from a shrine lamp and hide it inside your sleeve.")
		"saint_bone":
			_collect_village_component("saint_bone", bone_prop, "You pocket the carved saint bone before the village can catch the theft.")
		"quiet_place":
			_use_quiet_place()
		"boat":
			_use_boat()

func _on_enforcer_awareness_changed(_state: String, message: String) -> void:
	if message == "":
		return
	status_updated.emit(message)

func _on_player_rite_state_changed(available: bool, active: bool) -> void:
	if active:
		status_updated.emit("The rite veils your shape. Slip past the dock watcher now.")
		return
	if available and _advanced_rite_crafted and not _advanced_rite_spent:
		status_updated.emit("The advanced rite is waiting. Press Q when you are ready to pass the watcher.")

func _collect_component(state: Dictionary, component_id: String, prop: MeshInstance3D, message: String) -> void:
	if state[component_id]:
		return
	state[component_id] = true
	prop.visible = false
	status_updated.emit(message)
	_after_progress_change()

func _collect_tallow() -> void:
	if _woods_components["black_tallow"]:
		return
	_woods_components["black_tallow"] = true
	_set_visuals_visible(tallow_prop, false)
	tallow_light.light_energy = 0.4
	status_updated.emit("You lift black tallow from a hunter's cache and seal it before the smell travels.")
	_after_progress_change()

func _collect_village_component(component_id: String, prop: Node, message: String) -> void:
	if _village_components[component_id]:
		return
	if not _quiet_place_bound:
		status_updated.emit("Find the Quiet Place in the hunting cabin before you risk what the village holds.")
		return
	if not _all_woods_components_gathered():
		status_updated.emit("The first bindings are incomplete. Finish the woods gathering before stealing what completes the rite.")
		return
	_village_components[component_id] = true
	if prop is MeshInstance3D:
		prop.visible = false
	else:
		_set_visuals_visible(prop, false)
	status_updated.emit(message)
	_after_progress_change()

func _use_quiet_place() -> void:
	player.rest_at_quiet_place(quiet_place_marker.global_transform)
	if not _quiet_place_bound:
		_quiet_place_bound = true
		quiet_place_light.light_energy = 2.1
		status_updated.emit("You bind the Quiet Place. The blood sigil holds your path back to this cabin.")
	elif _all_village_components_gathered() and not _advanced_rite_crafted:
		_advanced_rite_crafted = true
		player.grant_advanced_rite()
		status_updated.emit("You bind the advanced rite inside the blood sign. It will veil you long enough to pass the watcher.")
	_after_progress_change()

func _use_boat() -> void:
	if not _advanced_rite_crafted:
		status_updated.emit("The dock is still sealed by the watcher. Return to the Quiet Place and bind the advanced rite first.")
		return
	if not player.is_veiled() and not _advanced_rite_spent:
		status_updated.emit("The watcher still owns the dock line. Use the advanced rite and slip past him before you board.")
		return
	if _escaped:
		return
	if player.is_veiled() and not _advanced_rite_spent:
		_advanced_rite_spent = true
		player.consume_advanced_rite()
	_escaped = true
	boat_light.light_energy = 2.7
	objective_updated.emit("Prototype complete")
	progress_updated.emit("Escape: at sea")
	prompt_updated.emit("")
	status_updated.emit("You shove off from the shoreline and let the fjord carry you beyond the village lights.")
	level_completed.emit()

func _after_progress_change() -> void:
	objective_updated.emit(_build_objective_text())
	progress_updated.emit(_build_progress_text())
	prompt_updated.emit(_build_prompt_text())
	if _all_village_components_gathered() and not _advanced_rite_crafted:
		status_updated.emit("You have what the advanced rite needs. Return to the Quiet Place and bind it.")
	elif _quiet_place_bound and _all_woods_components_gathered() and not _all_village_components_gathered():
		status_updated.emit("The first binding holds. Move into the village and steal what completes the rite.")

func _all_woods_components_gathered() -> bool:
	for gathered in _woods_components.values():
		if not gathered:
			return false
	return true

func _all_village_components_gathered() -> bool:
	for gathered in _village_components.values():
		if not gathered:
			return false
	return true

func _count_gathered(state: Dictionary) -> int:
	var count := 0
	for gathered in state.values():
		if gathered:
			count += 1
	return count

func _build_objective_text() -> String:
	if _escaped:
		return "Prototype complete"
	if _advanced_rite_spent or _advanced_rite_crafted:
		return "Use the advanced rite to pass the watcher and board the boat."
	if _all_village_components_gathered():
		return "Return to the Quiet Place and craft the advanced rite."
	if _quiet_place_bound and _all_woods_components_gathered():
		return "Slip through the village and steal the advanced rite components."
	if _all_woods_components_gathered():
		return "Enter the hunting cabin and bind the Quiet Place."
	return "Gather the three woods components and find the Quiet Place in the hunting cabin."

func _build_progress_text() -> String:
	if _escaped:
		return "Escape: at sea"
	if _advanced_rite_spent:
		return "Rite: spent | Boat ahead"
	if _advanced_rite_crafted:
		return "Rite: crafted | Press Q to veil"
	if _all_village_components_gathered():
		return "Village theft: 3/3 | Return to cabin"
	if _quiet_place_bound and _all_woods_components_gathered():
		return "Village theft: %d/3" % _count_gathered(_village_components)
	if _all_woods_components_gathered():
		return "Quiet Place: unbound"
	return "Woods components: %d/3" % _count_gathered(_woods_components)

func _build_prompt_text() -> String:
	match _interaction_target:
		"rowan":
			return "Press E to gather rowan bark" if not _woods_components["rowan"] else ""
		"grave_ash":
			return "Press E to gather grave ash" if not _woods_components["grave_ash"] else ""
		"black_tallow":
			return "Press E to gather black tallow" if not _woods_components["black_tallow"] else ""
		"silver_thread":
			if _village_components["silver_thread"]:
				return ""
			return "Press E to steal silver thread" if _quiet_place_bound and _all_woods_components_gathered() else "Bind the Quiet Place before stealing village components"
		"church_wax":
			if _village_components["church_wax"]:
				return ""
			return "Press E to steal church wax" if _quiet_place_bound and _all_woods_components_gathered() else "Bind the Quiet Place before stealing village components"
		"saint_bone":
			if _village_components["saint_bone"]:
				return ""
			return "Press E to steal saint bone" if _quiet_place_bound and _all_woods_components_gathered() else "Bind the Quiet Place before stealing village components"
		"quiet_place":
			if _all_village_components_gathered() and not _advanced_rite_crafted:
				return "Press E to rest, bind the cabin, and craft the advanced rite"
			if not _quiet_place_bound:
				return "Press E to rest and bind the Quiet Place"
			return "Press E to rest and renew your checkpoint"
		"boat":
			if _escaped:
				return ""
			if not _advanced_rite_crafted:
				return "Craft the advanced rite before trying to escape"
			if not _advanced_rite_spent and not player.is_veiled():
				return "Use the advanced rite before boarding"
			return "Press E to push off and escape"
		_:
			return ""

func _set_visuals_visible(root: Node, visible: bool) -> void:
	for child in root.get_children():
		if child is VisualInstance3D:
			child.visible = visible
