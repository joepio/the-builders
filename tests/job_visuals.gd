extends SceneTree
## Validate that task identities survive unlocking/completion and match world targets.
const JobStyle = preload("res://src/job_style.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var site := Site.new()
	root.add_child(site)
	var hud := Hud.new()
	root.add_child(hud)
	hud.set_tasks(site.tasks())
	check(site._pit_job_marker.text == "2 DIG FOUNDATION\n↓", "New pit explicitly identifies the foundation area")
	check(site._pit_job_marker.modulate == site.tasks()[1].color, "Pit and digging row share a colour")
	for piece in get_nodes_in_group("rubble"):
		check(piece is RigidBody3D and not piece.freeze, "Marked junk remains movable")
		var label: Label3D = piece.get_node("JunkMark/TaskNumber")
		check(label.text == "1" and label.modulate == site.tasks()[0].color, "Junk has the same numbered colour as its job")
	var fixed := get_nodes_in_group("fixed_site_equipment")
	check(fixed.size() == 1 and not fixed[0].is_in_group("rubble"), "Fuel rack is scenery, excluded from junk progress")
	check(fixed[0].get_node_or_null("JunkMark") == null, "Fixed fuel rack has no junk interaction marker")
	site.rubble_cleared = site.rubble_total
	hud.set_tasks(site.tasks())
	check(hud._task_rows[0][0].text == "1" and hud._task_rows[0][1].text.begins_with("✔"), "Completed task retains its number and a completion symbol")
	check(hud._task_rows[2][5].visible and not hud._task_rows[3][5].visible, "Only the next locked task is shown")
	site.cheat("dug")
	site._update_job_markers()
	check(site._pit_job_marker.text.begins_with("3 POUR") and site._pit_job_marker.modulate == site.tasks()[2].color, "Dug pit changes to the concrete task identity")
	site.poured = true
	site._update_unlocks()
	site._update_job_markers()
	check(site._pit_job_marker.text.begins_with("4 STACK") and site._pit_job_marker.modulate == site.tasks()[3].color, "Cured slab changes to the stacking task identity")
	site.cheat("built")
	site._update_job_markers()
	check(site._pit_job_marker.text.begins_with("5 SEAL") and site._pit_job_marker.modulate == site.tasks()[4].color, "Finished structure points to the PUR task")
	for seam in site.seams:
		check(seam.marker.material_override.emission == site.tasks()[4].color, "Seam targets use the PUR task colour")
	site.finished = true
	site._update_job_markers()
	check(not site._pit_job_marker.visible, "Completed job hides its active location marker")
	print("BUILDERS_JOB_VISUALS_PASS" if failures == 0 else "BUILDERS_JOB_VISUALS_FAIL: %d" % failures)
	hud.free()
	site.free()
	quit(0 if failures == 0 else 1)
