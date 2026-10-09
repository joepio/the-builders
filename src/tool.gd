class_name Tool
extends Node3D
## Something a builder on foot can pick up with A, use with A or RT and put
## down with B: the concrete hose, the foam gun.

var title := "Tool"
var hint: Array = []
var holder: Worker = null

func _enter_tree() -> void:
	add_to_group("tool")

## Where a builder has to stand near to pick it up.
func grab_point() -> Vector3:
	return global_position

func can_grab() -> bool:
	return holder == null

func grab(w: Worker) -> void:
	holder = w
	w.holding = self

func drop() -> void:
	if holder: holder.holding = null
	holder = null

## Called every physics step while held. `active` is true while the trigger
## (or A) is down.
func use(_active: bool, _delta: float) -> void:
	pass
