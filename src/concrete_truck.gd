class_name ConcreteTruck
extends Machine
## Mixer truck with a pump and a long hose. Drive it close to the pit, press
## Y to start the pump, then someone on foot grabs the hose and pours. The
## hose only reaches so far, so park well.

const SPEED := 7.0

var steer := 0.0
var pumping := false
var hose: Hose
var _drum: Node3D
var _lamp: MeshInstance3D
var _front_wheels: Array[Node3D] = []

func _build() -> void:
	title = "Concrete truck"
	mass = 16.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.6, 0)
	exit_offset = Vector3(2.0, 0, -1.6)
	Toy.box(self, Vector3(1.6, 0.4, 5.2), Vector3(0, 0.75, 0.3), Toy.DARK)
	Toy.box(self, Vector3(2.2, 1.4, 1.5), Vector3(0, 1.55, -1.75), Color("#e94f37"))
	Toy.box(self, Vector3(2.0, 0.7, 0.9), Vector3(0, 1.9, -1.55), Toy.GLASS)
	Toy.box(self, Vector3(2.25, 0.12, 1.55), Vector3(0, 2.3, -1.75), Color("#e94f37"))
	set_flag(Toy.box(self, Vector3(1.9, 0.1, 1.2), Vector3(0, 2.38, -1.75), Toy.DARK))
	Toy.box(self, Vector3(2.0, 0.3, 0.2), Vector3(0, 0.95, -2.55), Toy.STEEL)
	for z in [-1.7, 1.3, 2.3]:
		for x in [-1.0, 1.0]:
			var w := Toy.wheel(self, 0.5, 0.42, Vector3(x, 0.5, z))
			if z != 1.3: marks.append([Vector3(x, 0, z), 0.42, false])
			if z < 0: _front_wheels.append(w)
	# The drum: tilted, striped so you can see it turn.
	var cradle := Node3D.new()
	cradle.position = Vector3(0, 2.0, 1.0)
	cradle.rotation.x = -0.18
	add_child(cradle)
	_drum = Node3D.new()
	cradle.add_child(_drum)
	Toy.cyl(_drum, 1.05, 3.0, Vector3.ZERO, Color("#f4f1e6"), Vector3(PI / 2, 0, 0), 0.8, 20)
	Toy.cyl(_drum, 0.55, 0.7, Vector3(0, 0, 1.8), Color("#f4f1e6"), Vector3(PI / 2, 0, 0), 0.35, 14)
	for k in 4:
		var a := k * TAU / 4.0
		Toy.box(_drum, Vector3(0.18, 0.12, 3.0), Vector3(cos(a) * 1.0, sin(a) * 1.0, 0), Color("#e94f37"), Vector3(0, 0, a + 0.4))
	for x in [-0.7, 0.7]:
		Toy.box(self, Vector3(0.15, 1.2, 0.15), Vector3(x, 1.4, -0.4), Toy.STEEL)
		Toy.box(self, Vector3(0.15, 1.3, 0.15), Vector3(x, 1.2, 2.6), Toy.STEEL)
	# Pump box at the back, with a lamp that shows when it's running.
	Toy.box(self, Vector3(1.4, 0.7, 0.6), Vector3(0, 0.9, 3.05), Toy.STEEL)
	_lamp = Toy.ball(self, 0.16, Vector3(0.5, 1.35, 3.1), Toy.DARK)
	Toy.shape(self, Vector3(2.2, 1.2, 5.6), Vector3(0, 0.6, 0.3))
	Toy.shape(self, Vector3(2.2, 1.6, 1.5), Vector3(0, 1.6, -1.75))
	Toy.shape(self, Vector3(2.1, 2.0, 3.4), Vector3(0, 2.0, 1.0))
	hint = [[["LS-h"], "steer"], [["RT", "LT"], "drive / reverse"], [["Y"], "pump on / off"], [["B"], "hop out"]]

func _ready() -> void:
	super._ready()
	hose = Hose.new()
	hose.truck = self
	add_child(hose)

func control(i: Dictionary, delta: float) -> void:
	var throttle := float(i.rt) - float(i.lt)
	steer = lerpf(steer, float(i.lx), clampf(6.0 * delta, 0, 1))
	var fwd := -global_transform.basis.z
	var v := linear_velocity.dot(fwd)
	var yaw := -steer * v * 0.33
	drive(throttle * SPEED, yaw, delta, 4.5, 0.8, 8.0, -1.4 * yaw)
	if i.y_pressed: set_pumping(not pumping)
	_drum.rotation.z += delta * (4.0 if pumping else 1.2)
	for w in _front_wheels: w.rotation.y = -steer * 0.5

func set_pumping(on: bool) -> void:
	pumping = on
	_lamp.material_override = Toy.glow(Color("#7cff6b"), 2.0) if on else Toy.mat(Toy.DARK)

func tag_height() -> float:
	return 4.2
