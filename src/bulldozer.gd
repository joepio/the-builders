class_name Bulldozer
extends Machine
## Tank-steered pusher. Tracks drive like the excavator's: each trigger
## pushes one track forward, its bumper pulls it back. The right stick lifts
## and angles the blade. Easy mode: drive with one stick.

const SPEED := 5.0
const TURN := 1.5
const LIFT := Vector2(-0.04, 0.55)   ## Blade arm angle range (rad), down to up.
const ANGLE := 0.45                  ## Blade can angle this far left or right.

var lift := 0.0
var angle := 0.0
var blade: Node3D
var _blade_body: AnimatableBody3D
var _tracks: Array[Node3D] = []
var _track_phase := [0.0, 0.0]

func _build() -> void:
	title = "Bulldozer"
	mass = 22.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.5, 0)
	exit_offset = Vector3(2.2, 0, 0.6)
	for side in [-1.0, 1.0]:
		var t := Node3D.new()
		t.position = Vector3(side * 1.0, 0.45, 0.2)
		add_child(t)
		Toy.box(t, Vector3(0.62, 0.9, 3.3), Vector3.ZERO, Toy.DARK)
		for k in 5:
			Toy.cyl(t, 0.22, 0.66, Vector3(0, -0.1, -1.2 + k * 0.6), Toy.STEEL, Vector3(0, 0, PI / 2), -1.0, 10)
		_tracks.append(t)
	Toy.box(self, Vector3(1.5, 1.0, 2.8), Vector3(0, 1.2, 0.3), Toy.YELLOW)
	Toy.box(self, Vector3(1.3, 0.25, 2.6), Vector3(0, 1.82, 0.4), Toy.ORANGE)
	Toy.cyl(self, 0.12, 0.9, Vector3(-0.45, 2.3, -0.6), Toy.DARK)
	# Cab with a coloured roof that shows the driver.
	Toy.box(self, Vector3(1.3, 1.1, 1.2), Vector3(0, 2.4, 0.9), Toy.GLASS)
	Toy.box(self, Vector3(1.4, 0.12, 1.3), Vector3(0, 3.0, 0.9), Toy.YELLOW)
	set_flag(Toy.box(self, Vector3(1.2, 0.1, 1.1), Vector3(0, 3.08, 0.9), Toy.DARK))
	# Push arms and the big curved blade, hinged on the hull so it can lift.
	blade = Node3D.new()
	blade.position = Vector3(0, 0.95, -0.7)
	add_child(blade)
	for side in [-1.0, 1.0]:
		Toy.box(self, Vector3(0.24, 0.3, 0.3), Vector3(side * 1.2, 0.95, -0.7), Toy.DARK)
		Toy.box(blade, Vector3(0.2, 0.25, 1.3), Vector3(side * 1.2, -0.12, -0.65), Toy.YELLOW, Vector3(0.2, 0, 0))
	Toy.cyl(blade, 0.1, 1.1, Vector3(0, 0.25, -0.75), Toy.STEEL, Vector3(PI / 2 - 0.35, 0, 0))
	Toy.box(blade, Vector3(3.2, 1.2, 0.22), Vector3(0, -0.2, -1.35), Toy.YELLOW, Vector3(-0.15, 0, 0))
	Toy.box(blade, Vector3(3.2, 0.12, 0.3), Vector3(0, -0.75, -1.45), Toy.STEEL)
	Toy.stripes(blade, Vector3(3.0, 0.22, 0.05), Vector3(0, 0.2, -1.5), 7)
	Toy.shape(self, Vector3(2.4, 1.6, 3.4), Vector3(0, 0.8, 0.2))
	Toy.shape(self, Vector3(1.3, 1.2, 1.2), Vector3(0, 2.2, 0.9))
	_blade_body = AnimatableBody3D.new()
	_blade_body.top_level = true
	_blade_body.sync_to_physics = true
	Toy.shape(_blade_body, Vector3(3.2, 1.1, 0.4), Vector3(0, -0.33, -1.35))
	add_child(_blade_body)
	add_collision_exception_with(_blade_body)
	_blade_body.add_collision_exception_with(self)
	set_easy(false)
	for side in [-1.0, 1.0]:
		for z in [-1.3, 1.7]: marks.append([Vector3(side * 1.0, 0, z), 0.62, true])
	_pose()

func set_easy(value: bool) -> void:
	easy = value
	var blade_hint := [[["RS-v"], "blade up / down"], [["RS-h"], "angle blade"]]
	hint = ([[["LS"], "drive and steer"]] if easy else TRACK_HINT) + blade_hint + [[["Y"], "tap: hop out"]]

func control(i: Dictionary, delta: float) -> void:
	var l: float
	var r: float
	if easy:
		var fwd := -float(i.ly)
		var turn := float(i.lx)
		l = clampf(fwd + turn * 0.7, -1, 1)
		r = clampf(fwd - turn * 0.7, -1, 1)
	else:
		var t := tracks(i)
		l = t.x
		r = t.y
	drive((l + r) * 0.5 * SPEED, (r - l) * TURN, delta, 5.0, 0.95, 5.0)
	lift = clampf(lift - float(i.ry) * 0.9 * delta, LIFT.x, LIFT.y)
	angle = clampf(angle - float(i.rx) * 1.2 * delta, -ANGLE, ANGLE)
	_pose()
	_scrape(delta)
	_track_phase[0] += l * delta * 4.0
	_track_phase[1] += r * delta * 4.0
	for k in 2:
		_tracks[k].position.y = 0.45 + sin(_track_phase[k] * 6.0) * 0.015

## A lowered blade cuts the sand under its edge and pushes it ahead.
func _scrape(delta: float) -> void:
	if site == null: return
	var ahead := -blade.global_transform.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var push := clampf(speed() / SPEED, 0.15, 1.0)
	# Two rows: the edge, and just behind it so sand that slumps back under
	# the blade gets caught too instead of lifting the dozer.
	for z in [-1.45, -0.95]:
		for k in 7:
			var p := blade.global_transform * Vector3(-1.5 + k * 0.5, -0.81, z)
			site.plow(p, ahead, 0.4)

func _pose() -> void:
	blade.rotation = Vector3(lift, angle, 0)
	if _blade_body and is_inside_tree():
		_blade_body.global_transform = blade.global_transform

func tag_height() -> float:
	return 4.0
