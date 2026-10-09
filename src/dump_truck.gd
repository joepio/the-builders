class_name DumpTruck
extends Machine
## Carries dirt from the digger to the dump. Hold Y (or RB) to tip the bed.
## Corner too hard with a full load and you'll leave a trail.

const SPEED := 8.0

var bed: Node3D
var tilt := 0.0
var steer := 0.0
var _bed_body: AnimatableBody3D
var _front_wheels: Array[Node3D] = []

func _build() -> void:
	title = "Dump truck"
	mass = 14.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.6, 0)
	exit_offset = Vector3(2.0, 0, -1.6)
	Toy.box(self, Vector3(1.6, 0.4, 4.8), Vector3(0, 0.75, 0.1), Toy.DARK)   # chassis
	Toy.box(self, Vector3(2.2, 1.4, 1.5), Vector3(0, 1.55, -1.75), Toy.ORANGE)  # cab
	Toy.box(self, Vector3(2.0, 0.7, 0.9), Vector3(0, 1.9, -1.55), Toy.GLASS)
	Toy.box(self, Vector3(2.25, 0.12, 1.55), Vector3(0, 2.3, -1.75), Toy.ORANGE)
	set_flag(Toy.box(self, Vector3(1.9, 0.1, 1.2), Vector3(0, 2.38, -1.75), Toy.DARK))
	Toy.box(self, Vector3(2.0, 0.3, 0.2), Vector3(0, 0.95, -2.55), Toy.STEEL)   # bumper
	for z in [-1.7, 0.9, 1.9]:
		for x in [-1.0, 1.0]:
			var w := Toy.wheel(self, 0.5, 0.42, Vector3(x, 0.5, z))
			if z < 0: _front_wheels.append(w)
	bed = Node3D.new()
	bed.position = Vector3(0, 1.0, 2.5)
	add_child(bed)
	Toy.box(bed, Vector3(2.3, 0.15, 3.4), Vector3(0, 0.08, -1.7), Toy.YELLOW)
	for x in [-1.1, 1.1]:
		Toy.box(bed, Vector3(0.12, 1.0, 3.4), Vector3(x, 0.55, -1.7), Toy.YELLOW)
	Toy.box(bed, Vector3(2.3, 1.3, 0.12), Vector3(0, 0.7, -3.4), Toy.YELLOW)
	Toy.box(bed, Vector3(2.3, 0.35, 0.12), Vector3(0, 0.25, 0.0), Toy.YELLOW)
	Toy.stripes(bed, Vector3(2.1, 0.2, 0.04), Vector3(0, 0.3, 0.07), 6)
	Toy.shape(self, Vector3(2.2, 1.2, 5.0), Vector3(0, 0.6, 0.1))
	Toy.shape(self, Vector3(2.2, 1.6, 1.5), Vector3(0, 1.6, -1.75))
	_bed_body = AnimatableBody3D.new()
	_bed_body.top_level = true
	_bed_body.sync_to_physics = true
	Toy.shape(_bed_body, Vector3(2.3, 0.2, 3.4), Vector3(0, 0.05, -1.7))
	for x in [-1.1, 1.1]:
		Toy.shape(_bed_body, Vector3(0.15, 1.1, 3.4), Vector3(x, 0.55, -1.7))
	Toy.shape(_bed_body, Vector3(2.3, 1.4, 0.15), Vector3(0, 0.7, -3.4))
	Toy.shape(_bed_body, Vector3(2.3, 0.4, 0.15), Vector3(0, 0.25, 0.0))
	_bed_body.physics_material_override = PhysicsMaterial.new()
	_bed_body.physics_material_override.friction = 0.35
	add_child(_bed_body)
	add_collision_exception_with(_bed_body)
	_bed_body.add_collision_exception_with(self)
	hint = "Left stick: steer\nRT / LT: drive / reverse\nY or RB: tip the bed\nB: hop out"
	_pose()

func control(i: Dictionary, delta: float) -> void:
	var throttle := float(i.rt) - float(i.lt)
	steer = lerpf(steer, float(i.lx), clampf(6.0 * delta, 0, 1))
	var fwd := -global_transform.basis.z
	var v := linear_velocity.dot(fwd)
	var yaw := -steer * v * 0.35
	drive(throttle * SPEED, yaw, delta, 5.0, 0.8, 8.0, -1.4 * yaw)
	var tipping: bool = i.y or i.rb
	tilt = move_toward(tilt, 1.15 if tipping else 0.0, (0.5 if tipping else 0.8) * delta)
	_pose()
	for w in _front_wheels: w.rotation.y = -steer * 0.5

func _pose() -> void:
	bed.rotation.x = tilt
	if _bed_body and is_inside_tree():
		_bed_body.global_transform = bed.global_transform

func tag_height() -> float:
	return 4.0

func set_easy(value: bool) -> void:
	easy = value
