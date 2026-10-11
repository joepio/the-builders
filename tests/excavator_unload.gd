extends SceneTree
## Regression: raised/extended arms used to hit the bucket stop before spilling.
## Run: godot --headless --path . --script tests/excavator_unload.gd

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: failures.append(what)

func _hold(ex: Excavator, input: Dictionary, seconds: float) -> void:
	var state := ex._neutral.duplicate()
	state.merge(input, true)
	for k in int(seconds * 120.0):
		ex.control(state, 1.0 / 120.0)

func _clump_amount() -> float:
	var amount := 0.0
	for clump in get_nodes_in_group("clump"):
		amount += float(clump.get_meta("amount"))
	return amount

func _run() -> void:
	var site := Site.new()
	root.add_child(site)
	var ex: Excavator
	for machine in site.machines:
		if machine is Excavator:
			ex = machine
			break
	# Keep this regression deterministic: run the actual controls and spawning
	# above the ground, with no collisions or new digging during emptying.
	ex.freeze = true
	ex.set_physics_process(false)
	ex.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 15, 0))
	for pose in [Vector2(1.05, -0.35), Vector2(0.55, -1.6), Vector2(0.0, -0.8), Vector2(-0.45, -2.3)]:
		ex.boom_angle = pose.x
		ex.arm_angle = pose.y
		ex.bucket_angle = Excavator.BUCKET.y
		ex.carried = Excavator.CAPACITY
		var before := _clump_amount()
		_hold(ex, {"rx": 1.0}, 2.0)
		_check(ex.carried == 0.0, "dump stick empties at boom %.2f / arm %.2f" % [pose.x, pose.y])
		_check(is_equal_approx(_clump_amount() - before, Excavator.CAPACITY), "all sand becomes clumps")
		_check(is_equal_approx(ex.boom_angle, pose.x) and is_equal_approx(ex.arm_angle, pose.y), "dumping preserves independent boom and arm joints")

	ex.boom_angle = 0.55
	ex.arm_angle = -1.6
	ex.bucket_angle = 0.3
	ex.carried = 0.75
	_hold(ex, {}, 1.0)
	_check(is_equal_approx(ex.carried, 0.75), "the normal carrying pose retains its sand")
	_hold(ex, {"lx": 0.5, "ry": -0.5}, 0.4)
	_check(is_equal_approx(ex.carried, 0.75), "lifting and swinging a curled bucket retains its sand")

	# A tipped bucket must finish unloading after the player releases the stick,
	# including tiny partial scoops that were previously retained forever.
	for amount in [0.005, 0.01, 0.26, 1.0, 0.005]:
		ex.boom_angle = 1.05
		ex.arm_angle = -0.35
		ex.bucket_angle = Excavator.BUCKET.x
		ex.carried = amount
		var before := _clump_amount()
		_hold(ex, {}, 0.75)
		_check(ex.carried == 0.0 and not ex._load_mesh.visible, "neutral tipped bucket empties load %.3f completely" % amount)
		_check(is_equal_approx(_clump_amount() - before, amount), "partial load is conserved")

	print("EXCAVATOR UNLOAD CHECKS PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	root.remove_child(site)
	site.free()
	quit(0 if failures.is_empty() else 1)
