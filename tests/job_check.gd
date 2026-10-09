extends SceneTree
## Drives each machine with scripted sticks on a real site and checks that the
## job steps physically work: digging, spilling, forklifting, craning a module
## into its slot, bulldozing junk into the dump and tipping the truck.
##
##     godot --headless --path . --script tests/job_check.gd

var failures: Array[String] = []
var _site: Site

func _initialize() -> void:
	_run()

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: failures.append(what)

func _fresh() -> Site:
	if _site:
		root.remove_child(_site)
		_site.free()
	await physics_frame
	_site = Site.new()
	root.add_child(_site)
	await physics_frame
	return _site

func _machine(site: Site, type: Variant) -> Machine:
	for m in site.machines:
		if is_instance_of(m, type): return m
	return null

## Hold `input` on `m` for `seconds` of physics time.
func _hold(m: Machine, input: Dictionary, seconds: float) -> void:
	var c := Controls.new(Controls.Source.KEYS, 0)
	c.read()
	if m.driver.is_empty(): m.driver = {"name": "test", "color": Color.WHITE, "controls": c}
	else: m.driver.controls = c
	var first := true
	var steps := int(seconds * 120.0)
	for k in steps:
		var s := input.duplicate()
		if not first:
			for b in Controls.BUTTONS: if s.has(b): s[b] = s[b]
		c.scripted = s
		c.read()
		first = false
		await physics_frame
	c.scripted = {"lx": 0.0}
	c.read()

func _wait(seconds: float) -> void:
	for k in int(seconds * 120.0): await physics_frame

func _run() -> void:
	print("excavator")
	var site := await _fresh()
	var ex: Excavator = _machine(site, Excavator)
	ex.boom_angle = 0.0
	ex.arm_angle = -0.8
	ex.bucket_angle = -0.6
	await _hold(ex, {"rx": -1.0}, 1.0)
	_check(ex.carried > 0.4, "scooping fills the bucket (%.2f)" % ex.carried)
	_check(site.pit_progress() > 0.01, "the pit gets deeper (%.1f%%)" % (site.pit_progress() * 100))
	await _hold(ex, {"ry": -1.0}, 1.2)
	await _hold(ex, {"lx": 1.0}, 2.0)
	await _hold(ex, {"rx": 1.0}, 1.6)
	await _wait(1.5)
	_check(ex.carried < 0.05, "tipping the bucket empties it (%.2f left)" % ex.carried)
	_check(get_nodes_in_group("clump").size() >= 3, "dirt falls out as clumps (%d)" % get_nodes_in_group("clump").size())
	await _hold(ex, {"lt": 1.0, "rt": 1.0}, 1.0)
	_check(ex.global_position.z < 3.8, "both tracks drive forward (z %.1f)" % ex.global_position.z)

	print("forklift")
	site = await _fresh()
	var fl: Forklift = _machine(site, Forklift)
	var mod: Module = null
	for m in get_nodes_in_group("module"):
		if m.kind == "module": mod = m; break
	for m in get_nodes_in_group("module"):
		if m != mod: m.global_position += Vector3(-40, 0, 0)
	for m in site.machines:
		if m is Forklift and m != fl: m.global_position += Vector3(0, 0, -20)
	fl.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2), mod.global_position + Vector3(-4.4, 0.05, 0))
	fl.home = fl.global_transform
	await _wait(0.3)
	print("    mod ", mod.global_position, " fl ", fl.global_position)
	await _hold(fl, {"rt": 0.35}, 1.4)
	print("    mod ", mod.global_position, " fl ", fl.global_position)
	await _hold(fl, {"lt": 0.0}, 0.4)
	var y0 := mod.global_position.y
	await _hold(fl, {"ry": -1.0}, 0.9)
	_check(mod.global_position.y > y0 + 0.6, "forks lift the pallet (%.2f -> %.2f)" % [y0, mod.global_position.y])
	var gap := mod.global_position.distance_to(fl.global_position)
	await _hold(fl, {"lt": 0.4}, 1.5)
	var moved := mod.global_position.distance_to(fl.global_position)
	_check(absf(moved - gap) < 0.6 and mod.global_position.y > 0.4, "the pallet rides along in reverse (gap %.2f -> %.2f)" % [gap, moved])
	var heading := fl.global_rotation.y
	await _hold(fl, {"rt": 0.5, "lx": 1.0}, 1.0)
	_check(absf(angle_difference(heading, fl.global_rotation.y)) > 0.3, "rear-wheel steering turns the forklift")

	print("crane")
	site = await _fresh()
	site.cheat("poured")
	await _wait(2.0)
	_check(site.poured, "a pit full of concrete sets into the slab")
	var crane: Crane = site.crane
	var slot: Dictionary = site.slots[0]
	mod = null
	for m in get_nodes_in_group("module"):
		if m.kind == "module": mod = m; break
	var to: Vector3 = slot.pos - crane.global_position
	crane.slew.rotation.y = atan2(-to.x, -to.z) - crane.global_rotation.y
	crane.reach = Vector2(to.x, to.z).length()
	crane.rope_len = 6.0
	crane._pose()
	mod.global_transform = Transform3D(Basis.IDENTITY, crane.trolley.global_position - Vector3(0, 6.0 + mod.lift_offset.y, 0))
	mod.linear_velocity = Vector3.ZERO
	crane.attach(mod)
	_check(crane.carrying == mod, "the hook takes the module")
	await _hold(crane, {"lx": 0.0}, 1.5)
	_check(mod.global_position.y > 2.0, "the rope holds the load up (y %.1f)" % mod.global_position.y)
	await _hold(crane, {"ry": 1.0}, 3.0)
	await _hold(crane, {"lx": 0.0}, 2.0)
	_check(site.placed_count() == 0, "lowering it does not snap it in by itself")
	_check(site.bolt_problem(mod) == "", "a module lowered onto its ghost can be bolted (%s)" % site.bolt_problem(mod))
	var before := mod.global_position
	site.bolt(mod)
	await _wait(0.6)
	_check(site.placed_count() == 1, "bolting locks the module in (%d placed)" % site.placed_count())
	_check(crane.carrying == null, "bolting releases the hook")
	_check(Vector2(mod.global_position.x - before.x, mod.global_position.z - before.z).length() < 0.01, "bolting keeps it where it stood, no snapping")
	# A module dumped far off its ghost can't be bolted.
	var stray: Module = null
	for m in get_nodes_in_group("module"):
		if m.kind == "module" and not m.placed: stray = m; break
	stray.global_transform = Transform3D(Basis.IDENTITY, site.slots[1].pos + Vector3(0, 0.05, 1.6))
	await _wait(0.5)
	_check(site.bolt_problem(stray) != "", "too far off the ghost is refused (%s)" % site.bolt_problem(stray))
	stray.global_transform = Transform3D(Basis(Vector3.UP, 0.6), site.slots[3].pos + Vector3(0.1, 0.05, 0))
	await _wait(0.5)
	_check(site.bolt_problem(stray) == "Too crooked, turn it", "too twisted is refused (%s)" % site.bolt_problem(stray))
	stray.global_transform = Transform3D(Basis(Vector3.UP, 0.05), site.slots[3].pos + Vector3(0.3, 0.05, 0.1))
	await _wait(0.5)
	site.bolt(stray)
	_check(site.placed_count() == 2 and site.neatness() < 100, "a bit sloppy is fine but costs neatness (%d%%)" % site.neatness())
	# Swinging: slewing quickly makes the load trail behind.
	var mod2: Module = null
	for m in get_nodes_in_group("module"):
		if m.kind == "module" and not m.placed: mod2 = m; break
	crane.rope_len = 8.0
	mod2.global_transform = Transform3D(Basis.IDENTITY, crane.trolley.global_position - Vector3(0, 8.0 + mod2.lift_offset.y, 0))
	crane.attach(mod2)
	await _hold(crane, {"lx": 1.0}, 2.0)
	var under := crane.trolley.global_position - Vector3(0, crane.rope_len, 0)
	var lag := Vector2(mod2.global_position.x - under.x, mod2.global_position.z - under.z).length()
	_check(lag > 0.15, "the load swings behind when slewing (%.2f m)" % lag)

	print("bulldozer")
	site = await _fresh()
	var dz: Bulldozer = _machine(site, Bulldozer)
	var junk: RigidBody3D = get_nodes_in_group("rubble")[0]
	for r in get_nodes_in_group("rubble"):
		if r != junk: r.global_position += Vector3(0, 0, 18)
	junk.global_transform = Transform3D(Basis.IDENTITY, Vector3(12.5, 0.1, -9.0))
	dz.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(8.8, 0.05, -9.0))
	await _wait(0.3)
	await _hold(dz, {"lt": 1.0, "rt": 1.0}, 3.5)
	await _wait(1.5)
	print("    junk ", junk.global_position if is_instance_valid(junk) else "gone", " dozer ", dz.global_position)
	_check(site.rubble_cleared >= 1, "pushing junk into the dump clears it (%d)" % site.rubble_cleared)
	var yaw0 := dz.global_rotation.y
	dz.respawn()
	await _wait(0.5)
	yaw0 = dz.global_rotation.y
	await _hold(dz, {"lt": 1.0, "rb": true}, 1.0)
	_check(absf(angle_difference(yaw0, dz.global_rotation.y)) > 0.8, "opposite tracks spin on the spot")
	var edge0: float = (dz.blade.global_transform * Vector3(0, -0.75, -1.45)).y
	await _hold(dz, {"ry": -1.0}, 1.0)
	var edge1: float = (dz.blade.global_transform * Vector3(0, -0.75, -1.45)).y
	_check(edge1 - edge0 > 0.5, "right stick lifts the blade (%.2f m)" % (edge1 - edge0))

	print("dump truck")
	site = await _fresh()
	var tr: DumpTruck = _machine(site, DumpTruck)
	tr.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 8))
	await _wait(0.4)
	for k in 4:
		site.spawn_clump(tr.global_transform * Vector3(-0.5 + (k % 2), 2.4, 1.0 - (k / 2) * 1.0), 0.25, Vector3.ZERO)
	await _wait(1.0)
	var in_bed := 0
	for b in get_nodes_in_group("clump"):
		if b.global_position.y > 1.0: in_bed += 1
	_check(in_bed == 4, "clumps land in the bed (%d)" % in_bed)
	await _hold(tr, {"rt": 0.4}, 1.0)
	in_bed = 0
	for b in get_nodes_in_group("clump"):
		if b.global_position.y > 1.0: in_bed += 1
	_check(in_bed >= 3, "a gentle drive keeps the load (%d)" % in_bed)
	await _hold(tr, {"y": true}, 3.0)
	await _wait(1.0)
	in_bed = 0
	for b in get_nodes_in_group("clump"):
		if b.global_position.y > 1.0: in_bed += 1
	_check(in_bed == 0, "tipping the bed empties it (%d left)" % in_bed)

	print("concrete")
	site = await _fresh()
	site.cheat("dug")
	await _wait(0.2)
	var mixer: ConcreteTruck = _machine(site, ConcreteTruck)
	mixer.global_transform = Transform3D(Basis.IDENTITY, Vector3(4.0, 0.05, -3.0))
	await _wait(0.3)
	await _hold(mixer, {"y": true}, 0.1)
	_check(mixer.pumping, "Y starts the pump")
	var builder := Worker.new()
	builder.setup({"name": "Pourer", "color": Color.RED})
	site.add_child(builder)
	builder.global_position = Vector3(-1.5, 0.3, -3.0)
	builder._body.rotation.y = PI / 2
	await _wait(0.5)
	mixer.hose.grab(builder)
	_check(builder.holding == mixer.hose, "a builder can pick up the hose")
	for k in 360:
		mixer.hose.use(true, 1.0 / 120.0)
		await physics_frame
	_check(site.pour_progress() > 0.05, "the hose pours concrete into the pit (%.2f)" % site.pour_progress())
	builder.global_position = Vector3(9.0, 0.3, 6.0)
	for k in 120:
		mixer.hose.use(true, 1.0 / 120.0)
		await physics_frame
	_check(site.splats.size() > 0, "missing the pit splats concrete on the sand")
	var reach := Vector2(builder.global_position.x - mixer.hose.anchor().x, builder.global_position.z - mixer.hose.anchor().z).length()
	builder.global_position = Vector3(-14.0, 0.3, 8.0)
	await _wait(0.3)
	reach = Vector2(builder.global_position.x - mixer.hose.anchor().x, builder.global_position.z - mixer.hose.anchor().z).length()
	_check(reach < Hose.LENGTH + 0.5, "the hose holds a builder back (%.1f m)" % reach)
	mixer.set_pumping(false)
	mixer.hose.use(true, 0.5)
	_check(not mixer.hose.flowing, "nothing flows with the pump off")
	for c in site.cells: site.pour_at(Vector3(c.x, -0.5, c.z), 1.0)
	await _wait(2.0)
	_check(site.poured, "a full pit sets into the slab")

	print("foam")
	site = await _fresh()
	site.cheat("built")
	await _wait(1.0)
	var open := 0
	for sm in site.seams: if sm.open: open += 1
	_check(site.seams.size() == 9 and open == 9, "a stacked house has gaps to foam (%d/%d open)" % [open, site.seams.size()])
	_check(not site.finished, "the job isn't done with gaps left")
	var side: Dictionary = {}
	for sm in site.seams: if sm.kind == "side": side = sm; break
	var gun: FoamGun = site.tools[0]
	var foamer := Worker.new()
	foamer.setup({"name": "Foamer", "color": Color.BLUE})
	site.add_child(foamer)
	var outward := Vector3(side.spot.x - Site.HOUSE.x, 0, side.spot.z - Site.HOUSE.z).normalized()
	foamer.global_position = Vector3(side.spot.x, 0.1, side.spot.z) + outward * 2.4
	foamer._body.rotation.y = atan2(outward.x, outward.z)
	await _wait(0.3)
	gun.grab(foamer)
	await physics_frame
	for k in 600:
		foamer.global_position = Vector3(side.spot.x, foamer.global_position.y, side.spot.z) + outward * 2.4
		gun.use(true, 1.0 / 120.0)
		await physics_frame
		if site.seams_done() > 0: break
	_check(site.seams_done() == 1, "spraying PUR at a gap seals it (%d sealed)" % site.seams_done())
	_check(get_nodes_in_group("foam").size() > 5, "and leaves lots of foam (%d blobs)" % get_nodes_in_group("foam").size())
	for sm in site.seams: site.foam_seam(sm, 99.0)
	await _wait(0.2)
	_check(site.finished, "a stacked house with every gap sealed is done (neatness %d%%)" % site.neatness())

	print("players")
	if _site:
		root.remove_child(_site)
		_site.free()
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var c := Controls.new(Controls.Source.KEYS, 0)
	c.scripted = {"lx": 0.0}
	var p: Dictionary = main._add_player("Tester", c, Color.RED)
	var exm: Machine = _machine(main.site, Excavator)
	p.worker.global_position = exm.global_position + Vector3(2.5, 0.2, 0)
	await _wait(0.3)
	c.scripted = {"a": true}
	await physics_frame
	await physics_frame
	c.scripted = {"lx": 0.0}
	await physics_frame
	_check(p.machine == exm, "pressing A next to a machine climbs in")
	c.scripted = {"b": true}
	await physics_frame
	await physics_frame
	c.scripted = {"lx": 0.0}
	await physics_frame
	_check(p.machine == null and p.worker.visible, "B climbs back out")
	# Walk towards the camera: the fridge junk sits just to the right.
	c.scripted = {"ly": 1.0}
	var z0: float = p.worker.global_position.z
	await _wait(0.8)
	_check(p.worker.global_position.z > z0 + 2.0, "walking moves the builder")

	print("")
	if failures.is_empty(): print("ALL CHECKS PASSED")
	else: print("%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
