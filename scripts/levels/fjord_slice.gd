extends Node3D

signal objective_updated(text: String)
signal status_updated(text: String)
signal prompt_updated(text: String)
signal progress_updated(text: String)
signal level_completed()

@onready var player = $Player
@onready var start_marker: Marker3D = $StartMarker
@onready var food_area: Area3D = $FoodArea
@onready var bandage_area: Area3D = $BandageArea
@onready var oil_area: Area3D = $OilArea
@onready var village_area: Area3D = $VillageArea
@onready var boat_area: Area3D = $BoatArea
@onready var food_prop: MeshInstance3D = $FoodProp
@onready var bandage_prop: MeshInstance3D = $BandageProp
@onready var oil_prop: Node3D = $OilCache
@onready var oil_light: OmniLight3D = $OilLight
@onready var boat_light: OmniLight3D = $BoatLight
@onready var enforcer = $Enforcer
@onready var village_enforcer = $VillageEnforcer

var _supplies := {
	"food": false,
	"bandages": false,
	"oil": false,
}
var _interaction_target: String = ""
var _entered_village: bool = false
var _escaped: bool = false

func _ready() -> void:
	player.set_spawn_transform(start_marker.global_transform)
	player.status_changed.connect(_relay_status)
	enforcer.awareness_changed.connect(_on_enforcer_awareness_changed)
	village_enforcer.awareness_changed.connect(_on_enforcer_awareness_changed)
	_ensure_area_connections(food_area, "food")
	_ensure_area_connections(bandage_area, "bandages")
	_ensure_area_connections(oil_area, "oil")
	_ensure_area_connections(boat_area, "boat")
	village_area.body_entered.connect(_on_village_area_entered)
	objective_updated.emit(_build_objective_text())
	status_updated.emit("Stay under the trees, gather what you need, then slip past the waterside village to the boat.")
	prompt_updated.emit("")
	progress_updated.emit(_build_progress_text())

func get_player():
	return player

func get_current_objective() -> String:
	return _build_objective_text()

func get_current_status() -> String:
	if _escaped:
		return "You clear the shoreline and push out into the fjord."
	if _entered_village:
		return "The boat is close. Stay unseen or fight through the last stretch."
	if _all_supplies_gathered():
		return "Supplies secured. Cross the village and reach the boat on the shoreline."
	return "Stay under the trees, gather what you need, then slip past the waterside village to the boat."

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
	if interaction_id == "boat" and _all_supplies_gathered() and _entered_village and not _escaped:
		status_updated.emit("The boat is ready. Push off before the enforcers close in.")

func _on_interaction_area_exited(body: Node3D, interaction_id: String) -> void:
	if body != player or _interaction_target != interaction_id:
		return
	_interaction_target = ""
	prompt_updated.emit("")

func _on_village_area_entered(body: Node3D) -> void:
	if body != player or _entered_village or not _all_supplies_gathered():
		return
	_entered_village = true
	objective_updated.emit(_build_objective_text())
	progress_updated.emit(_build_progress_text())
	status_updated.emit("You reach the waterside village. Keep low, or cut through and run for the boat.")
	prompt_updated.emit(_build_prompt_text())

func _handle_interaction() -> void:
	match _interaction_target:
		"food":
			_collect_supply("food", food_prop, "You take dried fish and hard bread from a hunter's wrap beneath the pines.")
		"bandages":
			_collect_supply("bandages", bandage_prop, "You tear clean cloth from an abandoned bundle and knot it into field bandages.")
		"oil":
			_collect_oil()
		"boat":
			_use_boat()

func _on_enforcer_awareness_changed(_state: String, message: String) -> void:
	if message == "":
		return
	status_updated.emit(message)

func _collect_supply(supply_id: String, prop: MeshInstance3D, message: String) -> void:
	if _supplies[supply_id]:
		return
	_supplies[supply_id] = true
	prop.visible = false
	status_updated.emit(message)
	_after_progress_change()

func _collect_oil() -> void:
	if _supplies["oil"]:
		return
	_supplies["oil"] = true
	_set_visuals_visible(oil_prop, false)
	oil_light.light_energy = 0.4
	status_updated.emit("You siphon lamp oil from a cache above the shore and cork it before the village sees your light.")
	_after_progress_change()

func _use_boat() -> void:
	if not _all_supplies_gathered():
		status_updated.emit("You are not leaving empty-handed. Gather the supplies hidden in the woods first.")
		return
	if not _entered_village:
		status_updated.emit("The shoreline boat is your exit, but you still have to cross the village to reach it cleanly.")
		return
	if _escaped:
		return
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
	if _all_supplies_gathered() and not _entered_village:
		status_updated.emit("Supplies secured. Cross the waterside village and reach the boat.")

func _all_supplies_gathered() -> bool:
	for gathered in _supplies.values():
		if not gathered:
			return false
	return true

func _supply_count() -> int:
	var count := 0
	for gathered in _supplies.values():
		if gathered:
			count += 1
	return count

func _build_objective_text() -> String:
	if _escaped:
		return "Prototype complete"
	if _all_supplies_gathered():
		return "Cross the waterside village and reach the shoreline boat."
	return "Gather three supplies in the woods before entering the village."

func _build_progress_text() -> String:
	if _escaped:
		return "Escape: at sea"
	if _all_supplies_gathered():
		return "Escape: boat ahead" if _entered_village else "Supplies: 3/3 | Village ahead"
	return "Supplies: %d/3" % _supply_count()

func _build_prompt_text() -> String:
	match _interaction_target:
		"food":
			return "Press E to gather food" if not _supplies["food"] else ""
		"bandages":
			return "Press E to gather bandages" if not _supplies["bandages"] else ""
		"oil":
			return "Press E to gather lamp oil" if not _supplies["oil"] else ""
		"boat":
			if _escaped:
				return ""
			if not _all_supplies_gathered():
				return "Gather all 3 supplies before escaping"
			return "Press E to push off and escape" if _entered_village else "Cross the village before using the boat"
		_:
			return ""

func _set_visuals_visible(root: Node, visible: bool) -> void:
	for child in root.get_children():
		if child is VisualInstance3D:
			child.visible = visible
