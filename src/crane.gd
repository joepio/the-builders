class_name Crane
extends Machine
## Tower crane. Slewing has momentum and the load hangs on a springy rope,
## so everything swings. A ground marker shows where the hook would land.

const HEIGHT := 13.0
const JIB := 18.5
const SLEW_MAX := 0.42
const ROPE_K := 900.0

var slew: Node3D
var trolley: Node3D
var hook: RigidBody3D
var rope: MeshInstance3D
var marker: MeshInstance3D
var reach := 9.0
var rope_len := 8.0
var slew_vel := 0.0
var carrying: RigidBody3D = null
var _carry_offset := Vector3.ZERO
var _hook_glow: MeshInstance3D
var _target: RigidBody3D = null

func _build() -> void:
	title = "Tower crane"
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	exit_offset = Vector3(2.0, 0, 2.0)
	Toy.box(self, Vector3(3.2, 0.6, 3.2), Vector3(0, 0.3, 0), Toy.CONCRETE)
	Toy.shape(self, Vector3(3.2, 0.6, 3.2), Vector3(0, 0.3, 0))
	Toy.shape(self, Vector3(1.4, HEIGHT, 1.4), Vector3(0, HEIGHT / 2.0, 0))
	# Lattice tower: four posts with cross bars.
	for x in [-0.6, 0.6]:
		for z in [-0.6, 0.6]:
			Toy.box(self, Vector3(0.14, HEIGHT, 0.14), Vector3(x, HEIGHT / 2.0, z), Toy.YELLOW)
	var k := 0.6
	while k < HEIGHT - 0.4:
		for face in 4:
			var holder := Node3D.new()
			holder.position = Vector3(0, k + 0.5, 0)
			holder.rotation.y = face * PI / 2.0
			add_child(holder)
			Toy.box(holder, Vector3(0.08, 1.5, 0.08), Vector3(0, 0, 0.6), Toy.YELLOW, Vector3(0, 0, 0.72))
			Toy.box(holder, Vector3(1.25, 0.08, 0.08), Vector3(0, -0.5, 0.6), Toy.YELLOW)
		k += 1.1
	slew = Node3D.new()
	slew.position = Vector3(0, HEIGHT, 0)
	add_child(slew)
	Toy.box(slew, Vector3(1.6, 0.5, 1.6), Vector3(0, 0.25, 0), Toy.DARK)
	# Jib (towards -Z) and counter-jib (+Z): open lattice so the site shows through.
	for x in [-0.38, 0.38]:
		Toy.box(slew, Vector3(0.1, 0.1, JIB + 0.5), Vector3(x, 0.55, -JIB / 2.0), Toy.YELLOW)
	Toy.box(slew, Vector3(0.1, 0.1, JIB + 0.5), Vector3(0, 1.25, -JIB / 2.0), Toy.YELLOW)
	var z := -0.8
	while z > -JIB:
		for x in [-0.19, 0.19]:
			Toy.box(slew, Vector3(0.06, 0.06, 1.15), Vector3(x, 0.9, z - 0.35), Toy.YELLOW, Vector3(0.6 if fmod(-z, 1.6) < 0.8 else -0.6, 0, 0))
		Toy.box(slew, Vector3(0.76, 0.06, 0.06), Vector3(0, 0.55, z), Toy.YELLOW)
		z -= 0.8
	Toy.box(slew, Vector3(0.8, 0.12, 6.5), Vector3(0, 0.6, 3.2), Toy.YELLOW)
	Toy.box(slew, Vector3(1.6, 1.4, 1.6), Vector3(0, 0.3, 5.6), Toy.CONCRETE)
	Toy.stripes(slew, Vector3(1.5, 0.3, 0.05), Vector3(0, 0.6, 6.42), 5)
	Toy.box(slew, Vector3(0.3, 3.2, 0.3), Vector3(0, 2.1, 0), Toy.YELLOW)   # apex
	for end in [-JIB * 0.6, 4.5]:
		var tie := sqrt(end * end + 9.0)
		Toy.box(slew, Vector3(0.05, 0.05, tie), Vector3(0, 2.2, end / 2.0), Toy.DARK, Vector3(atan2(3.0, absf(end)) * (1.0 if end < 0 else -1.0), 0, 0))
	# Operator cab, roof shows the driver.
	Toy.box(slew, Vector3(1.2, 1.3, 1.4), Vector3(1.1, -0.2, -0.6), Toy.GLASS)
	set_flag(Toy.box(slew, Vector3(1.3, 0.14, 1.5), Vector3(1.1, 0.5, -0.6), Toy.DARK))
	var sign_board := Toy.box(slew, Vector3(0.06, 1.2, 4.0), Vector3(0.45, 1.0, 2.2), Toy.ORANGE)
	sign_board.name = "Sign"
	trolley = Node3D.new()
	slew.add_child(trolley)
	Toy.box(trolley, Vector3(1.0, 0.35, 1.0), Vector3(0, 0.4, 0), Toy.DARK)
	Toy.cyl(trolley, 0.22, 0.9, Vector3(0, 0.15, 0), Toy.STEEL, Vector3(0, 0, PI / 2))
	hook = RigidBody3D.new()
	hook.top_level = true
	hook.mass = 0.8
	hook.linear_damp = 0.1
	hook.angular_damp = 2.0
	hook.can_sleep = false
	var hs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	hs.shape = sphere
	hook.add_child(hs)
	Toy.box(hook, Vector3(0.6, 0.4, 0.4), Vector3(0, 0.25, 0), Toy.ORANGE)
	_hook_glow = Toy.ball(hook, 0.3, Vector3(0, -0.15, 0), Toy.DARK)
	Toy.cyl(hook, 0.25, 0.1, Vector3(0, -0.45, 0), Toy.STEEL, Vector3(0, 0, PI / 2), -1.0, 12)
	add_child(hook)
	add_collision_exception_with(hook)
	rope = MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.05
	rm.bottom_radius = 0.05
	rm.height = 1.0
	rm.radial_segments = 6
	rope.mesh = rm
	rope.material_override = Toy.mat(Toy.DARK)
	rope.top_level = true
	add_child(rope)
	marker = MeshInstance3D.new()
	var mm := TorusMesh.new()
	mm.inner_radius = 0.75
	mm.outer_radius = 1.0
	mm.rings = 24
	mm.ring_segments = 6
	marker.mesh = mm
	marker.scale = Vector3(1, 0.15, 1)
	marker.material_override = Toy.glow(Color(1, 0.85, 0.2), 0.6)
	marker.top_level = true
	add_child(marker)
	hint = [[["LS-h"], "rotate"], [["LS-v"], "trolley in / out"], [["RS-v"], "hoist up / down"], [["A"], "hook on / let go"], [["LB", "RB"], "turn the load"], [["Y"], "tap: climb down"]]
	_pose()

func ready_hook() -> void:
	hook.global_position = trolley.global_position - Vector3(0, rope_len, 0)

func exit_point() -> Vector3:
	return global_transform * exit_offset

func control(i: Dictionary, delta: float) -> void:
	var accel := 0.7 if not easy else 1.4
	slew_vel = move_toward(slew_vel, -float(i.lx) * SLEW_MAX, accel * delta)
	slew.rotation.y += slew_vel * delta
	reach = clampf(reach - float(i.ly) * 4.0 * delta, 3.0, JIB - 0.5)
	rope_len = clampf(rope_len + float(i.ry) * 3.5 * delta, 1.2, HEIGHT + 1.2)
	_pose()
	_find_target()
	if i.a_pressed:
		if carrying: release()
		elif _target: attach(_target)
	var body: RigidBody3D = carrying if carrying else hook
	var offset := _carry_offset if carrying else Vector3.ZERO
	_rope(body, offset)
	if carrying:
		hook.global_position = carrying.global_transform * _carry_offset
		# Bumpers turn the load on its hook.
		var turn := (1.0 if i.lb else 0.0) - (1.0 if i.rb else 0.0)
		if turn != 0.0:
			var av := carrying.angular_velocity
			av.y = move_toward(av.y, turn * 0.9, 3.0 * delta)
			carrying.angular_velocity = av
	if easy:
		body.linear_velocity.x *= 1.0 - 1.2 * delta
		body.linear_velocity.z *= 1.0 - 1.2 * delta

func _pose() -> void:
	trolley.position = Vector3(0, 0.3, -reach)

func _rope(body: RigidBody3D, offset_local: Vector3) -> void:
	var anchor := trolley.global_position
	var p := body.global_transform * offset_local
	var d := p - anchor
	var dist := d.length()
	if dist > rope_len and dist > 0.01:
		var n := d / dist
		var r := p - body.global_position
		var v := body.linear_velocity + body.angular_velocity.cross(r)
		var vr := v.dot(n)
		var m := body.mass
		var force := -n * (ROPE_K * m * (dist - rope_len) + 2.0 * sqrt(ROPE_K) * m * maxf(vr, 0.0) * 0.8)
		body.apply_force(force, r)
	# Draw the rope.
	var mid := (anchor + p) * 0.5
	rope.global_position = mid
	var up := (anchor - p)
	var length := up.length()
	if length > 0.01:
		var basis := Basis()
		var y := up / length
		var x := y.cross(Vector3.FORWARD)
		if x.length() < 0.01: x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		basis = Basis(x, y, x.cross(y).normalized())
		rope.global_transform = Transform3D(basis.scaled(Vector3(1, length, 1)), mid)
	_update_marker(p, body)

func _update_marker(p: Vector3, body: RigidBody3D) -> void:
	var space := get_world_3d().direct_space_state
	var bottom := p
	if carrying: bottom = carrying.global_position + Vector3(0, -0.05, 0)
	var q := PhysicsRayQueryParameters3D.create(bottom, bottom + Vector3.DOWN * 40.0)
	q.exclude = [hook.get_rid(), body.get_rid()]
	var hit := space.intersect_ray(q)
	marker.visible = not hit.is_empty() and not driver.is_empty()
	if marker.visible:
		marker.global_position = hit.position + Vector3(0, 0.08, 0)

func _find_target() -> void:
	_target = null
	if carrying: return
	var best := 1.5
	for b in get_tree().get_nodes_in_group("liftable"):
		var lp: Vector3 = b.global_transform * b.lift_offset
		var dd := lp.distance_to(hook.global_position - Vector3(0, 0.45, 0))
		if dd < best:
			best = dd
			_target = b
	_hook_glow.material_override = Toy.glow(Color(0.3, 1, 0.4), 1.5) if _target else Toy.mat(Toy.DARK)

func attach(b: RigidBody3D) -> void:
	carrying = b
	_carry_offset = b.lift_offset
	b.angular_damp = 1.5
	b.linear_damp = 0.15
	hook.freeze = true
	hook.collision_layer = 0
	hook.collision_mask = 0
	# Keep the rope taut from where the load hangs now.
	rope_len = maxf(1.2, trolley.global_position.distance_to(b.global_transform * _carry_offset))
	if b.has_method("on_hooked"): b.on_hooked(self)

func release() -> void:
	if carrying == null: return
	var b := carrying
	carrying = null
	if is_instance_valid(b):
		b.angular_damp = 0.0
		b.linear_damp = 0.0
		if b.has_method("on_released"): b.on_released()
		hook.global_position = b.global_transform * _carry_offset + Vector3(0, 0.6, 0)
	hook.freeze = false
	hook.collision_layer = 1
	hook.collision_mask = 1
	hook.linear_velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if carrying and not is_instance_valid(carrying): release()
	super._physics_process(delta)

func tag_height() -> float:
	return HEIGHT + 3.0

func respawn() -> void:
	pass

func set_easy(value: bool) -> void:
	easy = value
