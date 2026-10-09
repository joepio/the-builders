class_name Bulldozer
extends Machine
## Tank-steered pusher. Each stick drives one track, like the real thing:
## both forward to go straight, one forward to turn. Easy mode: one stick.

const SPEED := 5.0
const TURN := 1.5

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
	# Push arms and the big curved blade.
	for side in [-1.0, 1.0]:
		Toy.box(self, Vector3(0.2, 0.25, 1.4), Vector3(side * 1.2, 0.8, -1.3), Toy.YELLOW, Vector3(0.25, 0, 0))
	Toy.box(self, Vector3(3.2, 1.2, 0.22), Vector3(0, 0.75, -2.05), Toy.YELLOW, Vector3(-0.15, 0, 0))
	Toy.box(self, Vector3(3.2, 0.12, 0.3), Vector3(0, 0.2, -2.15), Toy.STEEL)
	Toy.stripes(self, Vector3(3.0, 0.22, 0.05), Vector3(0, 1.15, -2.2), 7)
	Toy.shape(self, Vector3(2.4, 1.6, 3.4), Vector3(0, 0.8, 0.2))
	Toy.shape(self, Vector3(1.3, 1.2, 1.2), Vector3(0, 2.2, 0.9))
	Toy.shape(self, Vector3(3.2, 1.1, 0.4), Vector3(0, 0.62, -2.05))
	hint = [[["LS-v"], "left track"], [["RS-v"], "right track"], [["B"], "hop out"]]

func set_easy(value: bool) -> void:
	easy = value
	hint = ([[["LS"], "drive and steer"], [["B"], "hop out"]] if easy else
		[[["LS-v"], "left track"], [["RS-v"], "right track"], [["B"], "hop out"]])

func control(i: Dictionary, delta: float) -> void:
	var l: float
	var r: float
	if easy:
		var fwd := -float(i.ly)
		var turn := float(i.lx)
		l = clampf(fwd + turn * 0.7, -1, 1)
		r = clampf(fwd - turn * 0.7, -1, 1)
	else:
		l = -float(i.ly)
		r = -float(i.ry)
	drive((l + r) * 0.5 * SPEED, (r - l) * TURN, delta, 5.0, 0.95, 5.0)
	_track_phase[0] += l * delta * 4.0
	_track_phase[1] += r * delta * 4.0
	for k in 2:
		_tracks[k].position.y = 0.45 + sin(_track_phase[k] * 6.0) * 0.015

func tag_height() -> float:
	return 4.0
