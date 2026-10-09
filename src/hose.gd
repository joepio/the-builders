class_name Hose
extends Tool
## The concrete truck's pump hose: a floppy rope of segments from the truck
## to a nozzle. A builder grabs the nozzle and walks it to the pit; it only
## reaches so far, and concrete only flows while the truck's pump runs.

const POINTS := 16
const LENGTH := 11.0
const FLOW := 0.32   ## Cells filled per second.

var truck: Node3D
var flowing := false
var _p: Array[Vector3] = []
var _old: Array[Vector3] = []
var _segs: Array[MeshInstance3D] = []
var _nozzle: Node3D
var _ring: MeshInstance3D
var _spray: CPUParticles3D
var _splat_timer := 0.0
var _stream: MeshInstance3D
var _land := Vector3.ZERO

func _ready() -> void:
	title = "Concrete hose"
	hint = [[["RT"], "pour (pump on)"], [["B"], "put down"]]
	top_level = true
	var tube := CylinderMesh.new()
	tube.top_radius = 0.14
	tube.bottom_radius = 0.14
	tube.height = 1.0
	tube.radial_segments = 8
	tube.rings = 1
	var m := Toy.mat(Color("#2b2d33"), 0.6)
	for k in POINTS - 1:
		var s := MeshInstance3D.new()
		s.mesh = tube
		s.material_override = m
		add_child(s)
		_segs.append(s)
	_nozzle = Node3D.new()
	add_child(_nozzle)
	Toy.cyl(_nozzle, 0.2, 0.9, Vector3(0, 0, -0.3), Toy.STEEL, Vector3(PI / 2, 0, 0))
	Toy.cyl(_nozzle, 0.24, 0.2, Vector3(0, 0, 0.1), Toy.ORANGE, Vector3(PI / 2, 0, 0))
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.7
	_ring.mesh = tm
	_ring.material_override = Toy.glow(Toy.ORANGE, 1.2)
	add_child(_ring)
	_spray = CPUParticles3D.new()
	_spray.emitting = false
	_spray.amount = 60
	_spray.lifetime = 0.7
	_spray.local_coords = false
	_spray.direction = Vector3(0, 0, -1)
	_spray.spread = 8.0
	_spray.initial_velocity_min = 3.0
	_spray.initial_velocity_max = 4.0
	_spray.gravity = Vector3(0, -14, 0)
	_spray.scale_amount_min = 0.7
	_spray.scale_amount_max = 1.2
	var blob := SphereMesh.new()
	blob.radius = 0.13
	blob.height = 0.22
	blob.radial_segments = 6
	blob.rings = 3
	blob.material = Toy.mat(Color("#8f918c"), 0.3)
	_spray.mesh = blob
	_spray.position = Vector3(0, 0, -0.75)
	_nozzle.add_child(_spray)
	# The pour itself: a thick grey stream from the nozzle to where it lands.
	_stream = MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.17
	sm.bottom_radius = 0.3
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 1
	_stream.mesh = sm
	_stream.material_override = Toy.mat(Site.WET, 0.25)
	_stream.visible = false
	add_child(_stream)
	var a := anchor()
	for k in POINTS:
		var q := a + Vector3(1.2, 0, 0).rotated(Vector3.UP, k * 0.5) * minf(k, 3.0) + Vector3(0, -a.y + 0.15, 0) * float(k > 0)
		_p.append(q)
		_old.append(q)

func anchor() -> Vector3:
	return truck.global_transform * Vector3(0, 1.0, 3.1) if truck else global_position

func grab_point() -> Vector3:
	return _p[POINTS - 1] if _p.size() == POINTS else global_position

func use(active: bool, delta: float) -> void:
	flowing = active and truck != null and bool(truck.get("pumping"))
	if not flowing: return
	# Concrete lands about where a blob from the nozzle hits the ground.
	var tip := _nozzle.global_transform * Vector3(0, 0, -0.75)
	var fwd := -_nozzle.global_transform.basis.z
	fwd.y = 0.0
	var land := tip + fwd.normalized() * 1.3
	var site: Node = truck.site
	if site: land.y = site.ground_at(land)
	_land = land
	if site == null: return
	if not site.pour_at(land, FLOW * delta):
		_splat_timer -= delta
		if _splat_timer <= 0.0:
			_splat_timer = 0.35
			site.splat(land)

func drop() -> void:
	super.drop()
	flowing = false

func _physics_process(delta: float) -> void:
	if _p.is_empty(): return
	var seg := LENGTH / float(POINTS - 1)
	# Verlet rope with the truck end pinned and, while held, the nozzle too.
	for k in range(1, POINTS):
		var v := (_p[k] - _old[k]) * 0.94
		_old[k] = _p[k]
		_p[k] += v + Vector3(0, -18.0, 0) * delta * delta
	_p[0] = anchor()
	if holder:
		var hand := holder.hand()
		var a := _p[0]
		var reach := Vector2(hand.x - a.x, hand.z - a.z)
		# The hose is only so long: it tugs the builder back.
		if reach.length() > LENGTH * 0.92:
			var back := reach.normalized() * (reach.length() - LENGTH * 0.92)
			holder.global_position -= Vector3(back.x, 0, back.y)
			hand = holder.hand()
		_p[POINTS - 1] = hand
	for it in 10:
		for k in POINTS - 1:
			var d := _p[k + 1] - _p[k]
			var l := d.length()
			if l < 0.0001: continue
			var corr := d * (1.0 - seg / l)
			var fix_a := k == 0
			var fix_b := k + 1 == POINTS - 1 and holder != null
			if fix_a and fix_b: continue
			elif fix_a: _p[k + 1] -= corr
			elif fix_b: _p[k] += corr
			else:
				_p[k] += corr * 0.5
				_p[k + 1] -= corr * 0.5
		for k in range(1, POINTS):
			var floor_y := 0.14
			if truck and truck.site: floor_y += truck.site.ground_at(_p[k])
			if _p[k].y < floor_y: _p[k].y = floor_y
	for k in POINTS - 1:
		var a := _p[k]
		var b := _p[k + 1]
		var d := b - a
		var l := maxf(d.length(), 0.001)
		var up := d / l
		var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
		var fwd := side.cross(up)
		_segs[k].global_transform = Transform3D(Basis(side, up * l, fwd), (a + b) * 0.5)
	var tip := _p[POINTS - 1]
	var dir := Vector3.FORWARD
	if holder: dir = holder.facing() + Vector3(0, -0.35, 0)
	else: dir = (tip - _p[POINTS - 2])
	if dir.length() < 0.01: dir = Vector3.FORWARD
	_nozzle.global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT), tip)
	_ring.visible = holder == null
	if _ring.visible:
		_ring.global_position = Vector3(tip.x, tip.y - 0.1, tip.z)
		_ring.scale = Vector3.ONE * (1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.006))
	_spray.emitting = flowing
	_stream.visible = flowing
	if flowing:
		var from := _nozzle.global_transform * Vector3(0, 0, -0.75)
		var d := _land - from
		var l := maxf(d.length(), 0.01)
		var up := -d / l
		var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
		_stream.global_transform = Transform3D(Basis(side, up * l, side.cross(up)), (from + _land) * 0.5)
