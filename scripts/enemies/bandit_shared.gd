## Shared constants and helpers for bandit component scripts.
## Preload with:  const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")

const LIB_NAME := &"Searching"
const LIB_PATH := "res://assets/animations/animation_libraries/npc_searching.res"

const LEFT_ARM_BONES: Array[String] = [
	"shoulder.L", "upper_arm.L", "forearm.L", "hand.L",
	"thumb.01.L", "thumb.02.L", "thumb.03.L",
	"f_index.01.L", "f_index.02.L", "f_index.03.L",
	"f_middle.01.L", "f_middle.02.L", "f_middle.03.L",
	"f_ring.01.L", "f_ring.02.L", "f_ring.03.L",
	"f_pinky.01.L", "f_pinky.02.L", "f_pinky.03.L",
]
