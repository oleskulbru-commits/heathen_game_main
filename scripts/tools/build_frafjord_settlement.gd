extends SceneTree
## Builds the Frafjord settlement scene.
## Keeps existing user placements (Longhouse at ~(-3, 0.26, 29), GrassPatch, Boat, Dock)
## by loading the current scene and adding new nodes.
##
## Run:
##   Godot --headless --path <project> --script res://scripts/tools/build_frafjord_settlement.gd

const SCENE_PATH := "res://assets/level/settlements/frafjord/frafjord.tscn"
const P := "res://assets/level/placeholders/"
const YBOT := "res://scenes/xbots/ybot_npc.tscn"
const XBOT := "res://scenes/xbots/xbot_npc.tscn"
const VILLAGER_SCRIPT := "res://scripts/game/villager_controller.gd"


func _init() -> void:
	print("=== Building Frafjord Settlement ===\n")

	# Load existing scene
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("ERROR: Cannot load ", SCENE_PATH)
		quit(); return
	var root := packed.instantiate()

	# ─── LAYOUT REFERENCE ───
	# The Storbonde longhouse is already placed by user at approx (-3, 0.26, 29).
	# All positions are in Frafjord local space.
	# +X = east, +Z = south (toward fjord shore), -Z = north (inland/mountains)
	# The fjord shore is roughly at Z = -40 to -50 (south of settlement)
	# Fields are north/east of the settlement.

	# ─── STRUCTURES ───

	# Cottage 1: tenant farmer, SW of longhouse
	_add_instance(root, P + "cottage.tscn", "Cottage_Tenant1",
		Vector3(-18, 0, 22), 25.0)

	# Cottage 2: tenant farmer, NE of longhouse
	_add_instance(root, P + "cottage.tscn", "Cottage_Tenant2",
		Vector3(14, 0, 36), -10.0)

	# Cottage 3: abandoned, slightly isolated NW
	_add_instance(root, P + "cottage.tscn", "Cottage_Abandoned",
		Vector3(-25, 0, 42), 5.0)

	# Stabbur (raised storehouse) near longhouse
	_add_instance(root, P + "stabbur.tscn", "Stabbur",
		Vector3(5, 0, 25), 0.0)

	# Animal pen with fence, east of longhouse
	_add_instance(root, P + "animal_pen.tscn", "AnimalPen",
		Vector3(20, 0, 28), 0.0)

	# Barn / storage building south of pen
	_add_instance(root, P + "barn.tscn", "Barn",
		Vector3(22, 0, 20), 15.0)

	# Well near the main longhouse
	_add_instance(root, P + "well.tscn", "Well",
		Vector3(-6, 0, 24), 0.0)

	# Smithy / forge, east side of settlement
	_add_instance(root, P + "smithy.tscn", "Smithy",
		Vector3(28, 0, 32), -20.0)

	# Woodpile area near smithy
	_add_instance(root, P + "woodpile.tscn", "Woodpile_Main",
		Vector3(26, 0, 35), 10.0)

	# Second woodpile near longhouse
	_add_instance(root, P + "woodpile.tscn", "Woodpile_Longhouse",
		Vector3(-7, 0, 32), 45.0)

	# Midden heap (waste pile) NE outskirts
	_add_instance(root, P + "midden_heap.tscn", "MiddenHeap",
		Vector3(30, 0, 42), 0.0)

	# Graveyard — multiple grave markers, west side
	for i in 8:
		var gx := -30.0 + (i % 4) * 2.0
		var gz := 30.0 + floorf(i / 4.0) * 2.5
		var rot := randf_range(-15.0, 15.0)
		_add_instance(root, P + "grave_marker.tscn", "Grave_%d" % i,
			Vector3(gx, 0, gz), rot)

	# Shrine / offering post near graveyard
	_add_instance(root, P + "shrine_post.tscn", "ShrinePost",
		Vector3(-28, 0, 28), 0.0)

	# Burnt / collapsed building on outskirts
	_add_instance(root, P + "burnt_building.tscn", "BurntBuilding",
		Vector3(-35, 0, 45), 30.0)

	# ─── FIELDS ───

	# Tended field NE
	_add_instance(root, P + "field_tended.tscn", "Field_Tended1",
		Vector3(12, 0, 48), 0.0)

	# Tended field E
	_add_instance(root, P + "field_tended.tscn", "Field_Tended2",
		Vector3(22, 0, 50), 10.0)

	# Overgrown / abandoned fields
	_add_instance(root, P + "field_overgrown.tscn", "Field_Abandoned1",
		Vector3(-12, 0, 52), 5.0)

	_add_instance(root, P + "field_overgrown.tscn", "Field_Abandoned2",
		Vector3(0, 0, 55), -5.0)

	_add_instance(root, P + "field_overgrown.tscn", "Field_Abandoned3",
		Vector3(32, 0, 52), 0.0)

	# ─── DOCK / SHORE AREA ───
	# (Dock and Boat already placed by user)

	# Fishing nets / rope coils near dock
	_add_instance(root, P + "rope_coil.tscn", "FishingNets1",
		Vector3(-80, -1.2, -18), 0.0)

	_add_instance(root, P + "rope_coil.tscn", "FishingNets2",
		Vector3(-84, -1.2, -15), 30.0)

	# Barrels near dock
	_add_instance(root, P + "barrel.tscn", "Barrel_Dock1",
		Vector3(-78, -1.2, -14), 0.0)

	_add_instance(root, P + "barrel.tscn", "Barrel_Dock2",
		Vector3(-79, -1.2, -13.5), 20.0)

	_add_instance(root, P + "crate.tscn", "Crate_Dock",
		Vector3(-81, -1.2, -13), 10.0)

	# ─── ENVIRONMENTAL PROPS ───

	# Cart abandoned mid-task near cottage 1
	_add_instance(root, P + "cart.tscn", "Cart_Abandoned",
		Vector3(-15, 0, 18), 65.0)

	# Plow abandoned in field
	_add_instance(root, P + "plow.tscn", "Plow_Abandoned",
		Vector3(-10, 0, 50), 30.0)

	# Barrels near longhouse
	_add_instance(root, P + "barrel.tscn", "Barrel_Longhouse1",
		Vector3(2, 0, 27), 0.0)

	_add_instance(root, P + "barrel.tscn", "Barrel_Longhouse2",
		Vector3(2.5, 0, 27.8), 15.0)

	# Crates near stabbur
	_add_instance(root, P + "crate.tscn", "Crate_Stabbur1",
		Vector3(6.5, 0, 24), 0.0)

	_add_instance(root, P + "crate.tscn", "Crate_Stabbur2",
		Vector3(7, 0, 24.5), 45.0)

	# Log near woodpile
	_add_instance(root, P + "log.tscn", "Log_Woodpile",
		Vector3(25, 0, 36.5), 5.0)

	# Hay bales near barn
	_add_instance(root, P + "hay_bale.tscn", "HayBale1",
		Vector3(24, 0, 18), 0.0)

	_add_instance(root, P + "hay_bale.tscn", "HayBale2",
		Vector3(25.5, 0, 17.5), 30.0)

	# Torch on longhouse entrance
	_add_instance(root, P + "torch.tscn", "Torch_Longhouse",
		Vector3(-1, 0, 26.5), 0.0)

	# ─── WOODEN FENCES / PATHS ───

	# Fence segments around animal pen
	_add_instance(root, P + "wooden_fence.tscn", "Fence_Pen1",
		Vector3(17, 0, 26), 0.0)

	_add_instance(root, P + "wooden_fence.tscn", "Fence_Pen2",
		Vector3(23, 0, 26), 0.0)

	# Path segments connecting buildings
	_add_instance(root, P + "path_segment.tscn", "Path_Main1",
		Vector3(-3, 0, 26), 0.0)

	_add_instance(root, P + "path_segment.tscn", "Path_Main2",
		Vector3(1, 0, 26), 0.0)

	_add_instance(root, P + "path_segment.tscn", "Path_Main3",
		Vector3(5, 0, 26), 0.0)

	_add_instance(root, P + "path_segment.tscn", "Path_ToWell",
		Vector3(-5, 0, 25.5), 20.0)

	_add_instance(root, P + "path_segment.tscn", "Path_ToCottage1",
		Vector3(-10, 0, 24), 30.0)

	_add_instance(root, P + "path_segment.tscn", "Path_ToBarn",
		Vector3(12, 0, 25), -15.0)

	# ─── NATURAL ───
	# Trees removed – will be placed via Proton Scatter.

	# Bushes
	_add_instance(root, P + "bush.tscn", "Bush1",
		Vector3(-20, 0, 48), 0.0)

	_add_instance(root, P + "bush.tscn", "Bush2",
		Vector3(35, 0, 40), 0.0)

	_add_instance(root, P + "bush.tscn", "Bush3",
		Vector3(-32, 0, 38), 0.0)

	# Rocks
	_add_instance(root, P + "rock_small.tscn", "Rock1",
		Vector3(-14, 0, 35), 30.0)

	_add_instance(root, P + "rock_large.tscn", "Rock2",
		Vector3(34, 0, 25), 15.0)

	_add_instance(root, P + "boulder.tscn", "Boulder1",
		Vector3(-36, 0, 35), 0.0)

	# ─── NPCs ───

	# 1. Storbonde — male YBot, near longhouse entrance, weight_shift gesture
	_add_villager(root, YBOT, "NPC_Storbonde",
		Vector3(-2, 0, 27), 180.0,
		"Idle", "npc_gestures.res", "weight_shift")

	# 2. Guard — male YBot, at longhouse entrance, dismissing gesture (wary)
	_add_villager(root, YBOT, "NPC_Guard",
		Vector3(-5, 0, 27.5), 160.0,
		"Guard", "npc_gestures.res", "dismissing_gesture")

	# 3. Farmer working field — male YBot, digging in tended field
	_add_villager(root, YBOT, "NPC_Farmer_Field",
		Vector3(13, 0, 48), 0.0,
		"Working", "npc_farming.res", "dig_and_plant_seeds")

	# 4. Farmer tending animals — male YBot, near animal pen, holding idle
	_add_villager(root, YBOT, "NPC_Farmer_Animals",
		Vector3(19, 0, 29), 90.0,
		"Working", "npc_farming.res", "holding_idle")

	# 5. Woman at well — female XBot, fearful/suspicious, look away gesture
	_add_villager(root, XBOT, "NPC_Woman_Well",
		Vector3(-6.5, 0, 23), 0.0,
		"Fearful", "npc_gestures.res", "look_away_gesture")

	# 6. Farmer pulling weeds — female XBot, in tended field 2, pull plant
	_add_villager(root, XBOT, "NPC_Farmer_Weeding",
		Vector3(23, 0, 50), 10.0,
		"Working", "npc_farming.res", "pull_plant")

	# 7. Sick NPC — male YBot, lying/kneeling outside abandoned cottage
	_add_villager(root, YBOT, "NPC_Sick",
		Vector3(-24, 0, 40), 0.0,
		"Sick", "npc_farming.res", "kneeling_idle")

	# 8. Child — female XBot (smaller scale), near longhouse, acknowledging gesture
	_add_villager(root, XBOT, "NPC_Child",
		Vector3(0, 0, 30), 200.0,
		"Child", "npc_gestures.res", "acknowledging", 0.65)

	# 9. Woman watering — female XBot, near field, watering animation
	_add_villager(root, XBOT, "NPC_Woman_Watering",
		Vector3(14, 0, 46), 180.0,
		"Working", "npc_farming.res", "watering")

	# ─── SAVE ───
	var scene := PackedScene.new()
	_set_all_owners(root, root)
	scene.pack(root)
	var err := ResourceSaver.save(scene, SCENE_PATH)
	if err != OK:
		printerr("FAIL: Could not save ", SCENE_PATH, " (code ", err, ")")
	else:
		print("SAVED: ", SCENE_PATH)

	root.free()
	print("\n=== Frafjord Settlement Built ===")
	quit()


# ═══ HELPERS ═══

func _add_instance(parent: Node, scene_path: String, node_name: String,
		pos: Vector3, y_rotation_deg: float) -> Node3D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("  SKIP (missing): ", scene_path)
		return null
	var inst := packed.instantiate() as Node3D
	inst.name = node_name
	inst.position = pos
	if y_rotation_deg != 0.0:
		inst.rotation_degrees.y = y_rotation_deg
	parent.add_child(inst)
	inst.owner = parent
	_set_all_owners(inst, parent)
	return inst


func _add_villager(parent: Node, skin_path: String, node_name: String,
		pos: Vector3, y_rotation_deg: float,
		role: String, activity_lib: String, activity_anim: String,
		char_scale: float = 1.0) -> void:
	var body := CharacterBody3D.new()
	body.name = node_name
	body.position = pos
	if y_rotation_deg != 0.0:
		body.rotation_degrees.y = y_rotation_deg

	# Attach villager script
	var script_res := load(VILLAGER_SCRIPT) as GDScript
	if script_res:
		body.set_script(script_res)
		body.set("role", role)
		body.set("activity_library", activity_lib)
		body.set("activity_animation", activity_anim)

	# Add to parent FIRST so ownership tree is valid
	parent.add_child(body)
	body.owner = parent

	# Add character skin
	var skin_packed := load(skin_path) as PackedScene
	if skin_packed:
		var skin := skin_packed.instantiate() as Node3D
		skin.transform = Transform3D(
			Basis(Vector3.UP, deg_to_rad(180.0)),
			Vector3.ZERO)
		if char_scale != 1.0:
			skin.scale = Vector3(char_scale, char_scale, char_scale)
		body.add_child(skin)
		skin.owner = parent
		_set_all_owners(skin, parent)

	# Add collision shape
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.86
	col.shape = shape
	col.position.y = 0.93
	body.add_child(col)
	col.owner = parent


func _set_all_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child.owner != owner:
			child.owner = owner
		_set_all_owners(child, owner)
