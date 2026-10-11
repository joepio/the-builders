extends SceneTree
## Deterministic grading checks: preserve flat ground, conserve soil, avoid spikes.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("ok " if ok else "FAIL ") + message)
	if not ok: failures += 1

func volume(terrain: Terrain) -> float:
	var total := 0.0
	for height in terrain.h: total += height * Terrain.RES * Terrain.RES
	return total

func _run() -> void:
	var site := Site.new()
	root.add_child(site)
	site.process_mode = Node.PROCESS_MODE_DISABLED
	var dozer: Bulldozer
	for m in site.machines:
		if m is Bulldozer: dozer = m
	dozer.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 10))
	dozer.lift = Bulldozer.LIFT.x
	dozer._pose()
	var terrain := site.terrain
	var initial := terrain.h.duplicate()
	dozer.linear_velocity = Vector3(0, 0, -5)
	for frame in 240: dozer._scrape(1.0 / 120.0)
	check(terrain.h == initial, "Driving over flat ground neither digs trenches nor creates soil")
	var hill := Vector3(0, 0, 8.0)
	terrain.add(hill, 2.5, 1.5)
	var pile := terrain.h.duplicate()
	dozer.linear_velocity = Vector3.ZERO
	for frame in 240: dozer._scrape(1.0 / 120.0)
	check(terrain.h == pile, "An idling lowered blade does not reshape the terrain")
	dozer.linear_velocity = Vector3(0, 0, 5)
	for frame in 120: dozer._scrape(1.0 / 120.0)
	check(terrain.h == pile, "Reversing does not move soil into a forward spike")
	var before := volume(terrain)
	var peak := terrain.height_at(hill)
	dozer.linear_velocity = Vector3(0, 0, -5)
	for frame in 240: dozer._scrape(1.0 / 120.0)
	check(terrain.height_at(hill) < peak * 0.6, "Forward grading flattens the pile")
	check(absf(volume(terrain) - before) < 0.001, "Grading redistributes soil without creating or deleting it")
	var new_peak := 0.0
	for k in terrain.h.size():
		if pile[k] <= 0.001: new_peak = maxf(new_peak, terrain.h[k])
	check(new_peak <= 0.1201, "Spread soil stays below a 12 cm ridge (%.3f m)" % new_peak)
	# Enough loose dirt near the foundation must not undo excavation progress.
	terrain.flatten(site.pit_rect.grow(0.01), -Site.PIT_DEPTH)
	var pit_before := terrain.mean_depth(site.pit_rect)
	var edge := Vector3(site.pit_rect.end.x + 0.7, 0, site.pit_rect.get_center().y)
	terrain.add(edge, 1.5, 0.6, false)
	for frame in 120: site.plow(edge, Vector3.LEFT, 0.04)
	check(is_equal_approx(terrain.mean_depth(site.pit_rect), pit_before), "Spreading beside the pit preserves its dug depth")
	# Compare equal travel time split into different physics step lengths.
	terrain.h = pile.duplicate()
	for frame in 60: dozer._scrape(1.0 / 60.0)
	var coarse := terrain.height_at(hill)
	terrain.h = pile.duplicate()
	for frame in 120: dozer._scrape(1.0 / 120.0)
	check(absf(terrain.height_at(hill) - coarse) < 0.025, "Grading strength follows travel, not physics tick count")
	site.free()
	print("BUILDERS_GRADING_PASS" if failures == 0 else "BUILDERS_GRADING_FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
