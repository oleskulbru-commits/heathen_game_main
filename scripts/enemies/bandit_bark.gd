extends Node
## Voiced-reaction (bark) system for bandits.
## Attach as a child of the bandit CharacterBody3D alongside BanditPerception.
##
## Populate the export arrays with AudioStream assets in the Inspector.
## Barks respect a per-bandit cooldown so lines don't stack.

@export var bark_curious: Array[AudioStream] = []   ## "What was that?" etc.
@export var bark_alert: Array[AudioStream] = []     ## "Someone's there!" etc.
@export var bark_combat: Array[AudioStream] = []    ## "Get them!" etc.
@export var bark_lost: Array[AudioStream] = []      ## "They got away…" etc.

@export var cooldown: float = 3.5          ## min seconds between any two barks
@export var max_audible_distance: float = 30.0
@export var unit_size: float = 8.0

var _audio: AudioStreamPlayer3D
var _cooldown_timer: float = 0.0


func _ready() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.max_distance = max_audible_distance
	_audio.unit_size = unit_size
	_audio.bus = &"SFX"
	add_child(_audio)

	var perception := get_parent().get_node_or_null("BanditPerception")
	if not perception:
		push_warning("[BanditBark] No BanditPerception on %s" % get_parent().name)
		return
	perception.alert_level_changed.connect(_on_alert_level_changed)
	perception.player_lost_in_darkness.connect(_on_player_lost)


func _physics_process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _on_alert_level_changed(level: int) -> void:
	match level:
		1: _bark(bark_curious)
		2: _bark(bark_alert)
		3: _bark(bark_combat)


func _on_player_lost(_pos: Vector3) -> void:
	_bark(bark_lost)


func _bark(pool: Array[AudioStream]) -> void:
	if pool.is_empty() or _cooldown_timer > 0.0:
		return
	_audio.stream = pool.pick_random()
	_audio.play()
	_cooldown_timer = cooldown
