class_name Excavator
extends Machine
## Tracked digger with real two-stick arm controls (ISO pattern):
## left stick swings the house and moves the arm, right stick moves the boom
## and curls the bucket. Driving the tracks is on the triggers and bumpers.
## Dirt stays in the bucket while its mouth points up; tip it and it spills.

const SWING_SPEED := 1.1
const BOOM := Vector2(-0.45, 1.05)     ## min/max boom angle
const ARM := Vector2(-2.5, -0.35)
const BUCKET := Vector2(-2.6, 0.9)
const CAPACITY := 1.0
const CLUMPS_PER_LOAD := 4

var cab: Node3D
var boom: Node3D
var arm: Node3D
var bucket: Node3D
var tip: Node3D
var mouth: Node3D
var swing := 0.0
var boom_angle := 0.55
var arm_angle := -1.6
var bucket_angle := 0.3
var carried := 0.0
var _swing_vel := 0.0
var _bucket_body: AnimatableBody3D
var _load_mesh: MeshInstance3D
var _spill_timer := 0.0

func _build() -> void:
	title = "Excavator"
	mass = 20.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.4, 0)
	exit_offset = Vector3(2.4, 0, 1.0)
	for side in [-1.0, 1.0]:
		Toy.box(self, Vector3(0.7, 0.8, 3.6), Vector3(side * 1.05, 0.4, 0), Toy.DARK)
		for k in 6:
			Toy.cyl(self, 0.2, 0.74, Vector3(side * 1.05, 0.32, -1.4 + k * 0.56), Toy.STEEL, Vector3(0, 0, PI / 2), -1.0, 10)
	Toy.box(self, Vector3(1.4, 0.4, 2.4), Vector3(0, 0.75, 0), Toy.DARK)
	Toy.cyl(self, 0.8, 0.25, Vector3(0, 0.98, 0), Toy.STEEL)
	cab = Node3D.new()
	cab.position = Vector3(0, 1.1, 0)
	add_child(cab)
	Toy.box(cab, Vector3(2.3, 1.0, 2.6), Vector3(0, 0.5, 0.25), Toy.YELLOW)
	Toy.box(cab, Vector3(2.35, 0.8, 0.9), Vector3(0, 0.6, 1.4), Toy.DARK)   # counterweight
	Toy.stripes(cab, Vector3(2.0, 0.2, 0.05), Vector3(0, 0.75, 1.86), 6)
	Toy.box(cab, Vector3(1.0, 1.2, 1.2), Vector3(0.6, 1.6, -0.45), Toy.GLASS)
	Toy.box(cab, Vector3(1.1, 0.12, 1.3), Vector3(0.6, 2.25, -0.45), Toy.YELLOW)
	set_flag(Toy.box(cab, Vector3(0.9, 0.1, 1.1), Vector3(0.6, 2.33, -0.45), Toy.DARK))
	Toy.cyl(cab, 0.1, 0.8, Vector3(-0.7, 1.4, 0.8), Toy.DARK)
	boom = Node3D.new()
	boom.position = Vector3(-0.35, 1.1, -0.9)
	cab.add_child(boom)
	Toy.box(boom, Vector3(0.5, 0.6, 4.2), Vector3(0, 0, -2.0), Toy.YELLOW)
	Toy.cyl(boom, 0.13, 2.2, Vector3(0, -0.45, -1.4), Toy.STEEL, Vector3(PI / 2, 0, 0))
	arm = Node3D.new()
	arm.position = Vector3(0, 0, -4.1)
	boom.add_child(arm)
	Toy.box(arm, Vector3(0.42, 0.45, 3.1), Vector3(0, 0, -1.45), Toy.YELLOW)
	Toy.cyl(arm, 0.1, 1.8, Vector3(0, 0.36, -1.0), Toy.STEEL, Vector3(PI / 2, 0, 0))
	Toy.cyl(arm, 0.28, 0.6, Vector3.ZERO, Toy.DARK, Vector3(0, 0, PI / 2))
	bucket = Node3D.new()
	bucket.position = Vector3(0, 0, -3.0)
	arm.add_child(bucket)
	# The bucket is a cup that opens towards its local +Y.
	Toy.box(bucket, Vector3(1.2, 0.12, 1.0), Vector3(0, -0.85, -0.35), Toy.DARK)
	Toy.box(bucket, Vector3(1.2, 0.85, 0.12), Vector3(0, -0.45, 0.12), Toy.DARK)
	for side in [-1.0, 1.0]:
		Toy.box(bucket, Vector3(0.1, 0.9, 1.0), Vector3(side * 0.6, -0.45, -0.35), Toy.DARK)
	for k in 5:
		Toy.box(bucket, Vector3(0.12, 0.1, 0.3), Vector3(-0.48 + k * 0.24, -0.85, -0.95), Toy.STEEL)
	Toy.cyl(bucket, 0.18, 1.3, Vector3.ZERO, Toy.STEEL, Vector3(0, 0, PI / 2))
	_load_mesh = Toy.ball(bucket, 0.55, Vector3(0, -0.45, -0.35), Toy.DIRT, 0.7)
	_load_mesh.visible = false
	tip = Node3D.new()
	tip.position = Vector3(0, -0.85, -1.0)
	bucket.add_child(tip)
	mouth = Node3D.new()
	mouth.position = Vector3(0, 0.6, -0.35)
	bucket.add_child(mouth)
	# Body collision: tracks and house. The bucket gets its own moving body.
	Toy.shape(self, Vector3(2.8, 1.0, 3.6), Vector3(0, 0.5, 0))
	Toy.shape(self, Vector3(2.3, 1.2, 2.3), Vector3(0, 1.7, 0.4))
	_bucket_body = AnimatableBody3D.new()
	_bucket_body.top_level = true
	_bucket_body.sync_to_physics = true
	Toy.shape(_bucket_body, Vector3(1.2, 0.9, 1.1), Vector3(0, -0.45, -0.4))
	add_child(_bucket_body)
	add_collision_exception_with(_bucket_body)
	_bucket_body.add_collision_exception_with(self)
	hint = [[["LS-h"], "swing"], [["LS-v"], "arm in / out"], [["RS-v"], "boom up / down"], [["RS-h"], "curl / dump bucket"]] + TRACK_HINT + [[["B"], "hop out"]]
	_pose()

func control(i: Dictionary, delta: float) -> void:
	var t := tracks(i)
	drive((t.x + t.y) * 0.5 * 3.5, (t.y - t.x) * 1.0, delta, 4.0, 0.95, 4.0)
	# Swing has momentum, so the arm overshoots a little: on purpose.
	_swing_vel = lerpf(_swing_vel, -float(i.lx) * SWING_SPEED, clampf(2.5 * delta, 0, 1))
	swing += _swing_vel * delta
	arm_angle = clampf(arm_angle + float(i.ly) * 1.2 * delta, ARM.x, ARM.y)
	boom_angle = clampf(boom_angle - float(i.ry) * 0.8 * delta, BOOM.x, BOOM.y)
	var curl := float(i.rx)
	bucket_angle = clampf(bucket_angle - curl * 2.0 * delta, BUCKET.x, BUCKET.y)
	_pose()
	_dig(curl, delta)

func _pose() -> void:
	cab.rotation.y = swing
	boom.rotation.x = boom_angle
	arm.rotation.x = arm_angle
	bucket.rotation.x = bucket_angle
	if _bucket_body and is_inside_tree():
		_bucket_body.global_transform = bucket.global_transform

## World direction the bucket opening faces.
func mouth_up() -> float:
	return (mouth.global_position - bucket.global_transform * Vector3(0, -0.45, -0.35)).normalized().y

func _dig(curl: float, delta: float) -> void:
	if site == null: return
	var t := tip.global_position
	# Scooping: tip in the dirt while curling the bucket in.
	if curl < -0.2 and carried < CAPACITY:
		var got: float = site.dig_at(t, minf(CAPACITY - carried, 0.9 * delta * -curl))
		carried += got
	# Spilling: an upside-down bucket empties itself in clumps.
	if carried > 0.01 and mouth_up() < -0.15:
		_spill_timer -= delta
		if _spill_timer <= 0.0:
			_spill_timer = 0.12
			var amount := minf(carried, CAPACITY / CLUMPS_PER_LOAD)
			carried -= amount
			site.spawn_clump(bucket.global_transform * Vector3(0, -0.2, -0.4), amount, linear_velocity)
	_load_mesh.visible = carried > 0.02
	if _load_mesh.visible:
		var s := 0.5 + carried * 0.6
		_load_mesh.scale = Vector3(s, s, s)

func tag_height() -> float:
	return 4.6

func set_easy(value: bool) -> void:
	easy = value
