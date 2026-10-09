extends Node3D
## The Builders: everyone shares one building site, seen from above. Walk to
## a machine, hop in with A, and get the job done together.

const PALETTE := ["#ff7547", "#4cb5f5", "#ffd23f", "#7bd389", "#c77dff", "#ff5d8f", "#3ddbd9", "#f2efe4"]
const NAMES := ["Digger Dee", "Big Bob", "Wendy", "Scoop", "Muddy", "Crane-o", "Tilly", "Bricks"]
const MAX_PLAYERS := 8
const SETTINGS := [
	{"key": "controls", "label": "Machine controls", "kind": "choice", "default": "tricky", "options": ["tricky", "easy"]},
]
const STARS := [480.0, 720.0]   ## Seconds for three and two stars.

var site: Site
var hud: Hud
var camera: Camera3D
var players: Array[Dictionary] = []
var managed := false
var session := ""
var running := false          ## Timer runs and the job counts.
var job_time := 0.0
var done_time := -1.0
var easy := false
var demo := false
var _shot_path := ""
var _shot_time := 1.5
var _stage := ""
var _pose := false
var _demo_t := 0.0
var _join_held := {}
var _cam_target := Vector3.ZERO
var _cam_tilt := 0.98
var _cam_dist := 56.0
var _cam_fov := 34.0

func _ready() -> void:
	GameNight.game_id = "the-builders"
	_parse_args()
	_build_environment()
	hud = Hud.new()
	add_child(hud)
	_new_site()
	managed = GameNight.launched_by_daemon
	GameNight.prepared.connect(_on_prepared)
	GameNight.started.connect(_on_started)
	GameNight.paused.connect(func(_s: String) -> void: _set_paused(true))
	GameNight.resumed.connect(func(_s: String) -> void: _set_paused(false))
	GameNight.disposed.connect(_on_disposed)
	GameNight.roster_changed.connect(_on_roster)
	GameNight.setting_changed.connect(_on_setting)
	GameNight.declare_settings(SETTINGS)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	if "--no-hud" in OS.get_cmdline_user_args(): hud.visible = false
	hud.show_join(not managed and not demo)
	if demo: _start_demo()
	if _pose: _pose_action.call_deferred()
	if not _shot_path.is_empty(): _take_shot()

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--demo": demo = true
		elif arg == "--easy": easy = true
		elif arg.begins_with("--shot="): _shot_path = arg.substr(7)
		elif arg.begins_with("--shot-time="): _shot_time = float(arg.substr(12))
		elif arg.begins_with("--stage="): _stage = arg.substr(8)
		elif arg == "--pose": _pose = true
		elif arg == "--pour-pose": _pour_pose.call_deferred()
		elif arg == "--foam-pose": _foam_pose.call_deferred()
		elif arg.begins_with("--cam="):
			var parts := arg.substr(6).split(",")
			_cam_target = Vector3(float(parts[0]), 0, float(parts[1]))
			if parts.size() > 2: _cam_dist = float(parts[2])
			if parts.size() > 3: _cam_tilt = float(parts[3])

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#5f9f43")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.86)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.86
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 95.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.45
	sun.shadow_blur = 0.6
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = _cam_fov
	add_child(camera)
	_place_camera()

func _place_camera() -> void:
	var dir := Vector3(0, sin(_cam_tilt), cos(_cam_tilt))
	camera.position = _cam_target + Vector3(0, 0, 1.5) + dir * _cam_dist
	camera.look_at(_cam_target + Vector3(0, 0, 1.5), Vector3.UP)

func _new_site() -> void:
	if site:
		for p in players:
			if p.machine: p.machine = null
		site.queue_free()
	site = Site.new()
	add_child(site)
	site.set_easy(easy)
	site.message.connect(func(t: String) -> void: hud.banner(t))
	site.job_done.connect(_on_job_done)
	if _stage != "": site.cheat(_stage)
	for p in players: _respawn_worker(p)
	job_time = 0.0
	done_time = -1.0
	hud.hide_done()
	hud.set_players(players)

# ── Players ──────────────────────────────────────────────────────────────────

func _add_player(p_name: String, controls: Controls, color: Color, id := "") -> Dictionary:
	var p := {"name": p_name, "controls": controls, "color": color, "id": id, "machine": null, "worker": null,
		"spawn": Site.SPAWN + Vector3((players.size() % 4) * 1.5, 0.1, (players.size() / 4) * 1.5)}
	players.append(p)
	_respawn_worker(p)
	hud.set_players(players)
	return p

func _respawn_worker(p: Dictionary) -> void:
	if p.worker and is_instance_valid(p.worker): p.worker.queue_free()
	var w := Worker.new()
	w.setup(p)
	site.add_child(w)
	w.global_position = p.spawn
	p.worker = w
	p.machine = null

func _enter_machine(p: Dictionary) -> void:
	var w: Worker = p.worker
	var best: Machine = null
	var best_d := 4.2
	for m in site.machines:
		if not m.driver.is_empty(): continue
		var d := Vector2(m.global_position.x - w.global_position.x, m.global_position.z - w.global_position.z).length()
		if m is Crane: d -= 1.0
		elif m is DumpTruck or m is Excavator: d -= 0.6
		if d < best_d:
			best_d = d
			best = m
	if best == null: return
	p.machine = best
	best.enter(p)
	w.visible = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	w.get_child(0).disabled = true
	hud.set_players(players)

## Pick up the nearest free tool within reach. Returns true if it did.
func _grab_tool(p: Dictionary) -> bool:
	var w: Worker = p.worker
	var best: Tool = null
	var best_d := 2.2
	for t in get_tree().get_nodes_in_group("tool"):
		if not t.can_grab(): continue
		var g: Vector3 = t.grab_point()
		var d := Vector2(g.x - w.global_position.x, g.z - w.global_position.z).length()
		if d < best_d:
			best_d = d
			best = t
	if best == null: return false
	best.grab(w)
	hud.set_players(players)
	return true

## Bolt the nearest loose module in where it stands. Returns true if a
## module was in reach (bolted or not, the builder gets told why).
func _try_bolt(p: Dictionary) -> bool:
	var w: Worker = p.worker
	var best: Module = null
	var best_d := 2.7
	for m in get_tree().get_nodes_in_group("module"):
		if m.placed: continue
		var d := Vector2(m.global_position.x - w.global_position.x, m.global_position.z - w.global_position.z).length()
		if d >= best_d or not site.poured: continue
		# Only modules at the house count; the yard is forklift territory.
		var s: Dictionary = site.slot_for(m)
		if s.is_empty() or Vector2(m.global_position.x - s.pos.x, m.global_position.z - s.pos.z).length() > 3.0: continue
		if true:
			best_d = d
			best = m
	if best == null: return false
	var why: String = site.bolt(best)
	if why != "":
		hud.banner("%s: %s" % [p.name, why], 1.4)
	return true

func _leave_machine(p: Dictionary) -> void:
	var m: Machine = p.machine
	if m == null: return
	m.leave()
	p["show_controls"] = false
	var w: Worker = p.worker
	w.global_position = m.exit_point() + Vector3(0, 0.3, 0)
	w.global_position.y = maxf(w.global_position.y, 0.3)
	w.velocity = Vector3.ZERO
	w.visible = true
	w.process_mode = Node.PROCESS_MODE_INHERIT
	w.get_child(0).disabled = false
	p.machine = null
	hud.set_players(players)

const HOLD_FOR_CONTROLS := 0.3   ## Seconds Y must be held to show controls instead of a tap.

func _physics_process(delta: float) -> void:
	if demo: _demo_drive(delta)
	if not managed and not demo: _drop_in()
	for p in players:
		var i: Dictionary = p.controls.read()
		# Y does it all: a tap climbs in or out (or picks up and puts down a
		# tool), holding it shows the controls in the player's card.
		var y_time: float = p.get("y_time", 0.0)
		var y_tap := false
		if i.y: y_time += delta
		elif y_time > 0.0:
			y_tap = y_time < HOLD_FOR_CONTROLS
			y_time = 0.0
		p["y_time"] = y_time
		var show: bool = (p.machine != null or p.worker.holding != null) and (y_time >= HOLD_FOR_CONTROLS or _pose and (players.find(p) < 2 or p.machine is Bulldozer))
		if show != bool(p.get("show_controls", false)):
			p["show_controls"] = show
			hud.set_players(players)
		if p.machine:
			if y_tap: _leave_machine(p)
		else:
			var w: Worker = p.worker
			w.walk(i, delta)
			if w.holding:
				w.holding.use(bool(i.a) or float(i.rt) > 0.3, delta)
				if y_tap:
					w.holding.drop()
					hud.set_players(players)
			elif w.stunned <= 0.0:
				if y_tap and not _grab_tool(p): _enter_machine(p)
				elif i.a_pressed: _try_bolt(p)
		if i.start_pressed and not managed and not demo: _toggle_pause()
		if done_time >= 0.0 and not managed and i.a_pressed and job_time - done_time > 2.0: _new_site()
	if running and done_time < 0.0: job_time += delta
	elif done_time >= 0.0:
		job_time += delta
		if managed and job_time - done_time > 12.0:
			running = true
			_new_site()

func _process(_delta: float) -> void:
	hud.set_tasks(site.tasks())
	hud.set_time(done_time if done_time >= 0.0 else job_time)

## Standalone drop-in: any pad or keyboard half pressing A joins.
func _drop_in() -> void:
	var sources := []
	for d in Input.get_connected_joypads(): sources.append([Controls.Source.PAD, d, Input.is_joy_button_pressed(d, JOY_BUTTON_A)])
	sources.append([Controls.Source.KEYS, 0, Input.is_physical_key_pressed(KEY_SPACE)])
	sources.append([Controls.Source.KEYS, 1, Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)])
	for s in sources:
		var key := "%d:%d" % [s[0], s[1]]
		var was: bool = _join_held.get(key, true)
		_join_held[key] = s[2]
		if not s[2] or was: continue
		var taken := false
		for p in players:
			if p.controls.source == s[0] and p.controls.id == s[1]: taken = true
		if taken or players.size() >= MAX_PLAYERS: continue
		var n := players.size()
		var c := Controls.new(s[0], s[1])
		c.read()
		_add_player("Builder %d" % (n + 1), c, Color(PALETTE[n % PALETTE.size()]))
		hud.banner("%s joined (%s)" % [players[-1].name, c.label()], 1.6)
		running = true

func _unhandled_input(event: InputEvent) -> void:
	if managed: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if get_tree().paused: get_tree().quit()
			else: _toggle_pause()
		elif get_tree().paused and event.keycode in [KEY_SPACE, KEY_ENTER]: _toggle_pause()
		elif get_tree().paused and event.keycode in [KEY_R, KEY_Y]:
			_toggle_pause()
			_new_site()
	elif event is InputEventJoypadButton and event.pressed and get_tree().paused:
		if event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_START: _toggle_pause()
		elif event.button_index == JOY_BUTTON_Y:
			_toggle_pause()
			_new_site()

func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)

func _set_paused(value: bool) -> void:
	get_tree().paused = value
	hud.set_paused(value and not managed)

func _on_job_done() -> void:
	done_time = job_time
	var stars := 1
	if done_time < STARS[0]: stars = 3
	elif done_time < STARS[1]: stars = 2
	hud.show_done(done_time, stars, managed)
	if managed and not session.is_empty(): GameNight.notify_finished(session)

# ── GameNight ────────────────────────────────────────────────────────────────

func _on_prepared(session_id: String, seats: Array, party_players: Array) -> void:
	session = session_id
	for p in players:
		if p.worker and is_instance_valid(p.worker): p.worker.queue_free()
	players.clear()
	var by_id := {}
	for pp in party_players: by_id[str(pp.get("id", ""))] = pp
	for seat in seats:
		var occupant: Dictionary = seat.get("occupant", {})
		if str(occupant.get("kind", "empty")) != "local": continue
		if players.size() >= MAX_PLAYERS: break
		var index := int(seat.get("index", players.size()))
		var profile: Dictionary = by_id.get(str(occupant.get("player_id", "")), {})
		_add_player(str(profile.get("name", "Builder %d" % (index + 1))), Controls.new(Controls.Source.SEAT, index),
			_profile_color(profile, players.size()), str(occupant.get("player_id", "")))
	_new_site()
	running = false
	GameNight._send({"type": "participation", "session": session_id, "instant_join": false})
	await get_tree().process_frame
	await get_tree().process_frame
	GameNight.notify_ready(session_id)

func _profile_color(profile: Dictionary, index: int) -> Color:
	var raw := str(profile.get("color", ""))
	if raw.begins_with("#") and Color.html_is_valid(raw): return Color(raw)
	return Color(PALETTE[index % PALETTE.size()])

func _on_started(session_id: String) -> void:
	if session_id != session: return
	_set_paused(false)
	running = true
	hud.banner("Let's build!", 2.0)

func _on_disposed(_session_id: String) -> void:
	var walks := []
	for p in players:
		if p.worker and is_instance_valid(p.worker): walks.append("%s walked %.1fm" % [p.name, p.worker.walked])
	print("The Builders: session disposed after %.0fs, %d/%d modules placed; %s" % [job_time, site.placed_count(), site.slots.size(), ", ".join(walks)])
	session = ""
	_set_paused(false)
	for p in players:
		if p.worker and is_instance_valid(p.worker): p.worker.queue_free()
	players.clear()
	running = false
	_new_site()

func _on_roster(_seats: Array, party_players: Array, _presence: Array) -> void:
	var by_id := {}
	for pp in party_players: by_id[str(pp.get("id", ""))] = pp
	for p in players:
		if p.id.is_empty() or not by_id.has(p.id): continue
		p.name = str(by_id[p.id].get("name", p.name))
		if p.worker: p.worker.set_player_name(p.name)
	hud.set_players(players)

func _on_setting(key: String, value: Variant) -> void:
	if key == "controls":
		easy = str(value) == "easy"
		site.set_easy(easy)

# ── Demo and screenshots ─────────────────────────────────────────────────────

func _start_demo() -> void:
	var picks := [Excavator, Crane, Forklift, Bulldozer, DumpTruck]
	for k in picks.size():
		var c := Controls.new(Controls.Source.KEYS, 0)
		c.scripted = {"lx": 0.0}
		var p := _add_player(NAMES[k], c, Color(PALETTE[k]))
		for m in site.machines:
			if is_instance_of(m, picks[k]) and m.driver.is_empty():
				p.worker.global_position = m.global_position + Vector3(1, 0, 0)
				_enter_machine(p)
				break
	for k in 2:
		var c := Controls.new(Controls.Source.KEYS, 0)
		c.scripted = {"lx": 0.0}
		var p := _add_player(NAMES[5 + k], c, Color(PALETTE[5 + k]))
		p.worker.global_position = Vector3(-6 + k * 9, 0.2, 2 + k * 3)
	running = true

## Scripted inputs so screenshots show machines mid-action.
func _demo_drive(delta: float) -> void:
	if _pose: return
	_demo_t += delta
	var t := _demo_t
	for p in players:
		var s: Dictionary = p.controls.scripted
		for k in s.keys(): s[k] = 0.0 if not (s[k] is bool) else false
		if p.machine is Excavator:
			s.ly = 0.6 if fmod(t, 6.0) < 2.0 else -0.4
			s.rx = -0.8 if fmod(t, 6.0) < 2.5 else 0.6
			s.lx = 0.5 if fmod(t, 6.0) > 3.0 else -0.2
		elif p.machine == null and p.worker.holding:
			s.rt = 1.0
		elif p.machine is Crane:
			s.lx = 0.35
			s.ry = -0.4 if t < 1.0 else 0.0
		elif p.machine is Forklift:
			s.rt = 0.5
			s.lx = 0.4 * sin(t)
			s.ry = -0.6
		elif p.machine is Bulldozer:
			s.lt = 0.8
			s.rt = 0.55
		elif p.machine is DumpTruck:
			s.rt = 0.4 if t < 2.0 else 0.0
			s.lx = 0.6
		else:
			s.lx = sin(t * 0.7 + p.spawn.x)
			s.ly = cos(t * 0.5 + p.spawn.z)

## Screenshot helper: freeze a busy moment mid-job.
## Screenshot helper: the pit dug, the mixer parked and a builder pouring.
func _pour_pose() -> void:
	await get_tree().physics_frame
	site.cheat("dug")
	var mixer: ConcreteTruck
	for m in site.machines: if m is ConcreteTruck: mixer = m
	mixer.global_transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(4.2, 0.02, -5.5))
	mixer.set_pumping(true)
	for k in site.cells.size():
		site.pour_at(Vector3(site.cells[k].x, -0.5, site.cells[k].z), [1.0, 0.7, 0.3, 1.0, 0.8, 0.2, 0.9, 0.5, 0.0][k])
	var p: Dictionary
	for q in players: if q.machine == null: p = q
	if p.is_empty(): return
	var w: Worker = p.worker
	mixer.hose.grab(w)
	hud.set_players(players)
	while is_instance_valid(w):
		w.global_position = Vector3(1.6, 0.0, -2.2)
		w._body.rotation.y = 1.15
		await get_tree().physics_frame

## Screenshot helper: the house stacked, a few gaps already foamed (too
## generously) and a builder spraying the next one.
func _foam_pose() -> void:
	await get_tree().physics_frame
	site.cheat("built")
	for k in 30: await get_tree().physics_frame
	# The front gap stays open for the shot; the stacking gaps got foamed.
	var target: Dictionary = site.seams[0]
	for sm in site.seams:
		if sm.kind == "side" and sm.spot.z > target.spot.z: target = sm
	for sm in site.seams:
		if sm.kind != "stack": continue
		for n in 18: Foam.blob(site, site.seam_spot(sm), randf_range(0.4, 0.8))
		site.foam_seam(sm, 99.0)
	var p: Dictionary
	for q in players: if q.machine == null: p = q
	if p.is_empty(): return
	var w: Worker = p.worker
	site.tools[0].grab(w)
	hud.set_players(players)
	var out := Vector3(target.spot.x - Site.HOUSE.x, 0, target.spot.z - Site.HOUSE.z).normalized()
	while is_instance_valid(w):
		w.global_position = Vector3(target.spot.x, 0, target.spot.z) + out * 2.6
		w._body.rotation.y = atan2(out.x, out.z)
		await get_tree().physics_frame

func _pose_action() -> void:
	await get_tree().physics_frame
	var by_type := {}
	for m in site.machines:
		var key: String = m.title
		if not by_type.has(key): by_type[key] = m
	var mods: Array = []
	for m in get_tree().get_nodes_in_group("module"): if m.kind == "module": mods.append(m)
	# Half the pit dug, some dirt lying around.
	for k in site.cells.size():
		site.cells[k].depth = [0.9, 0.6, 0.2, 1.0, 0.7, 0.1, 0.5, 0.3, 0.0][k]
		site._set_cell(site.cells[k])
	# Forklift carrying a module towards the crane pad.
	var fl: Forklift = by_type["Forklift"]
	fl.global_transform = Transform3D(Basis(Vector3.UP, PI / 2 + 0.25), Vector3(1.5, 0.02, 7.5))
	fl.lift = 0.9
	fl._pose()
	mods[0].global_transform = Transform3D(fl.global_transform.basis, fl.global_transform * Vector3(0, 0.98, -2.2))
	# Crane swinging a module from the pad.
	var cr: Crane = site.crane
	var to := Site.PAD + Vector3(1.5, 0, -4.5) - cr.global_position
	cr.slew.rotation.y = atan2(-to.x, -to.z)
	cr.reach = Vector2(to.x, to.z).length()
	cr.rope_len = 7.0
	cr._pose()
	mods[1].global_transform = Transform3D(Basis(Vector3.UP, 0.4), cr.trolley.global_position - Vector3(0.6, 7.0 + mods[1].lift_offset.y, 0.3))
	cr.attach(mods[1])
	# Excavator swinging a full bucket over to the truck.
	var ex: Excavator = by_type["Excavator"]
	ex.swing = -1.1
	ex.boom_angle = 0.75
	ex.arm_angle = -1.3
	ex.bucket_angle = 0.5
	ex.carried = 1.0
	ex._pose()
	var tr: DumpTruck = by_type["Dump truck"]
	tr.global_transform = Transform3D(Basis(Vector3.UP, 0.15), Vector3(4.2, 0.02, 3.2))
	for k in 6:
		site.spawn_clump(tr.global_transform * Vector3(-0.5 + (k % 2), 1.6 + k * 0.3, 1.2 - (k / 2) * 0.9), 0.25, Vector3.ZERO)
	for p in [Vector3(1.2, 1, 0.5), Vector3(1.8, 1, -0.4), Vector3(-6.8, 1, -1.0)]:
		site.spawn_clump(p, 0.25, Vector3.ZERO)
	var dz: Bulldozer = by_type["Bulldozer"]
	dz.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2 + 0.3), Vector3(10.0, 0.02, -6.5))
	dz.lift = 0.3
	var junk: Array = get_tree().get_nodes_in_group("rubble")
	junk[2].global_position = Vector3(13.0, 0.2, -7.8)
	for p in players:
		if p.machine == null: p.worker.global_position = [Vector3(-8, 0.2, 2.5), Vector3(-3.5, 0.2, 9.5)][players.find(p) % 2]

func _take_shot() -> void:
	await get_tree().create_timer(_shot_time).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("Saved ", _shot_path)
	get_tree().quit()
