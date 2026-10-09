class_name Forklift
extends Machine
## Small, quick and twitchy: it steers with the REAR wheels, so the tail
## swings out. Slide the forks under a pallet, lift, and don't corner hard.

const SPEED := 6.5
const LIFT := Vector2(0.06, 3.4)

var carriage: Node3D
var lift := 0.08
var steer := 0.0
var _forks: AnimatableBody3D
var _rear_wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
## The pallet riding on the forks. Once lifted off the ground it locks on, so
## it doesn't slide off when the tail swings out; lowering it lets go.
var carrying: Module = null
var _carry := Transform3D.IDENTITY

func _build() -> void:
	title = "Forklift"
	mass = 9.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.45, 0.5)
	exit_offset = Vector3(1.8, 0, 0.4)
	Toy.box(self, Vector3(1.45, 0.75, 2.5), Vector3(0, 0.75, 0.15), Toy.ORANGE)
	Toy.box(self, Vector3(1.5, 0.9, 0.6), Vector3(0, 0.95, 1.2), Toy.DARK)   # counterweight
	Toy.stripes(self, Vector3(1.3, 0.16, 0.05), Vector3(0, 0.75, 1.52), 5)
	set_flag(Toy.box(self, Vector3(0.6, 0.5, 0.5), Vector3(0, 1.4, 0.45), Toy.DARK))  # seat back
	Toy.box(self, Vector3(0.7, 0.12, 0.6), Vector3(0, 1.15, 0.2), Toy.DARK)
	# Overhead guard
	for x in [-0.65, 0.65]:
		for z in [-0.6, 0.9]:
			Toy.box(self, Vector3(0.08, 1.7, 0.08), Vector3(x, 2.0, z), Toy.DARK)
	Toy.box(self, Vector3(1.45, 0.08, 1.6), Vector3(0, 2.85, 0.15), Toy.ORANGE)
	# Mast
	for x in [-0.55, 0.55]:
		Toy.box(self, Vector3(0.14, 3.8, 0.18), Vector3(x, 1.95, -1.25), Toy.STEEL)
	Toy.box(self, Vector3(1.24, 0.14, 0.18), Vector3(0, 3.8, -1.25), Toy.STEEL)
	for z in [-0.8, 0.9]:
		for x in [-0.78, 0.78]:
			var w := Toy.wheel(self, 0.42 if z < 0 else 0.32, 0.32, Vector3(x, 0.42 if z < 0 else 0.32, z))
			if z < 0: _front_wheels.append(w)
			else: _rear_wheels.append(w)
			marks.append([Vector3(x, 0, z), 0.32, false])
	carriage = Node3D.new()
	carriage.position = Vector3(0, lift, -1.4)
	add_child(carriage)
	Toy.box(carriage, Vector3(1.3, 1.0, 0.1), Vector3(0, 0.55, 0), Toy.DARK)
	for x in [-0.45, 0.45]:
		Toy.box(carriage, Vector3(0.18, 0.1, 1.7), Vector3(x, 0.0, -0.85), Toy.STEEL)
		Toy.box(carriage, Vector3(0.18, 0.6, 0.1), Vector3(x, 0.3, -0.03), Toy.STEEL)
	Toy.shape(self, Vector3(1.5, 1.3, 2.6), Vector3(0, 0.65, 0.15))
	Toy.shape(self, Vector3(1.4, 1.0, 1.4), Vector3(0, 2.3, 0.15))
	_forks = AnimatableBody3D.new()
	_forks.top_level = true
	_forks.sync_to_physics = true
	for x in [-0.45, 0.45]:
		Toy.shape(_forks, Vector3(0.2, 0.1, 1.7), Vector3(x, 0.0, -0.85))
	Toy.shape(_forks, Vector3(1.3, 1.0, 0.12), Vector3(0, 0.55, 0))
	_forks.physics_material_override = PhysicsMaterial.new()
	_forks.physics_material_override.friction = 1.0
	add_child(_forks)
	add_collision_exception_with(_forks)
	_forks.add_collision_exception_with(self)
	set_easy(false)
	_pose()

func set_easy(value: bool) -> void:
	easy = value
	var steer_text := "steer" if easy else "steer (rear wheels!)"
	hint = [[["LS-h"], steer_text], [["RT", "LT"], "drive / reverse"], [["RS-v"], "forks up / down"], [["Y"], "tap: hop out"]]

func control(i: Dictionary, delta: float) -> void:
	var throttle := float(i.rt) - float(i.lt)
	steer = lerpf(steer, float(i.lx), clampf(8.0 * delta, 0, 1))
	var fwd := -global_transform.basis.z
	var v := linear_velocity.dot(fwd)
	var yaw := -steer * v * 0.55
	var d := 0.85
	var side := (d * yaw) if not easy else (-d * yaw)
	drive(throttle * SPEED, yaw, delta, 7.0, 0.85, 10.0, side)
	lift = clampf(lift - float(i.ry) * 1.4 * delta, LIFT.x, LIFT.y)
	_pose()
	_hold_pallet()
	for w in _rear_wheels: w.rotation.y = -steer * 0.6 * (1.0 if not easy else 0.0)
	for w in _front_wheels: w.rotation.y = steer * 0.5 * (1.0 if easy else 0.0)

func _pose() -> void:
	carriage.position.y = lift
	if _forks and is_inside_tree():
		_forks.global_transform = carriage.global_transform

func _hold_pallet() -> void:
	if carrying:
		if not is_instance_valid(carrying) or carrying.placed or carrying.is_hooked() or lift < 0.22:
			_let_go()
			return
		carrying.global_transform = carriage.global_transform * _carry
		return
	if lift < 0.22: return
	# Fork tops are at carriage height 0.05; a pallet deck sits 0.24 up.
	for m in get_tree().get_nodes_in_group("liftable"):
		if not (m is Module) or m.placed or m.is_hooked() or m.forklift: continue
		var rel: Vector3 = carriage.global_transform.affine_inverse() * m.global_position
		if absf(rel.x) < 0.7 and rel.z > -1.8 and rel.z < 0.1 and rel.y > -0.45 and rel.y < 0.05:
			carrying = m
			m.forklift = self
			_carry = carriage.global_transform.affine_inverse() * m.global_transform
			m.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			m.freeze = true
			return

func _let_go() -> void:
	if is_instance_valid(carrying):
		carrying.forklift = null
		if not carrying.placed and not carrying.is_hooked():
			carrying.freeze = false
			carrying.linear_velocity = linear_velocity
	carrying = null

func tag_height() -> float:
	return 4.2
