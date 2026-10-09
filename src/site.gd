class_name Site
extends Node3D
## The building site and the job running on it: clear the junk, dig the
## foundation pit, pour concrete, then forklift and crane the house modules
## into place. Builds the whole level out of primitives.

signal message(text: String)
signal job_done

const SITE := Rect2(-24, -15, 48, 30)
const WORLD := Rect2(-70, -50, 140, 100)
const HOUSE := Vector3(-3, 0, -3)
const PIT_CELLS := 3
const CELL := 2.0
const PIT_DEPTH := 0.8
const VOL_PER_LOAD := 1.2        ## Cubic metres of sand in a full bucket.
const DUMP := Rect2(15.0, -13.0, 7.0, 7.0)
const CRANE_AT := Vector3(-13, 0, -10)
const PAD := Vector3(-8, 0, 6)
const YARD := Vector3(16, 0, 8)
const SPAWN := Vector3(-18, 0, 10)
const GATE := Vector2(5.0, 13.0)   ## x range of the gate in the bottom fence
const BOLT_REACH := 1.0   ## How far off its ghost a module may be bolted (m).
const BOLT_TWIST := 0.35  ## And how twisted (rad, about 20 degrees).
const WET := Color("#565855")       ## Fresh concrete, dark and wet

var pit_rect := Rect2(HOUSE.x - 3, HOUSE.z - 3, 6, 6)
var cells: Array[Dictionary] = []
var slab: AnimatableBody3D
var poured := false
var pouring := false   ## Concrete is curing: the slab is about to set.
var splats: Array[Node3D] = []
var seams: Array[Dictionary] = []   ## Gaps between bolted parts that need PUR.
var tools: Array[Tool] = []
var slots: Array[Dictionary] = []
var machines: Array[Machine] = []
var ruts: Ruts
var terrain: Terrain
var _tufts: MultiMeshInstance3D
var _tuft_rest: Array = []    ## Each site tuft's transform on untouched ground.
var _tufts_seen := -1
var _cells_timer := 0.0
var crane: Crane
var rubble_total := 0
var rubble_cleared := 0
var dirt_dumped := 0.0
var finished := false
## Which job steps are open: junk and digging from the start, the pour once the
## pit is dug, stacking once the slab has set, PUR once the first gap appears.
var unlocked := [true, true, false, false, false]
const STEP_NAMES := ["Clear the junk", "Dig the foundation pit", "Pour the concrete", "Stack the house", "PUR every gap"]
const STEP_AFTER := ["", "", "once the pit is dug", "once the concrete has set", "once two parts touch"]
var easy := false
var _clump_mesh: SphereMesh
var _clump_shape: SphereShape3D
var _module_count := 0
var _rng := RandomNumberGenerator.new()
var _pending_deliveries := 0
var _delivery_timer := 0.0

func _ready() -> void:
	_rng.seed = 7
	_clump_mesh = SphereMesh.new()
	_clump_mesh.radius = 0.42
	_clump_mesh.height = 0.7
	_clump_mesh.radial_segments = 8
	_clump_mesh.rings = 4
	_clump_shape = SphereShape3D.new()
	_clump_shape.radius = 0.4
	_build_ground()
	_build_pit()
	_build_dump()
	_build_fence()
	_build_props()
	_spawn_tools()
	_build_slots()
	_spawn_modules()
	_spawn_rubble()
	_spawn_machines()

# ── Ground ───────────────────────────────────────────────────────────────────

## Cover `outer` with boxes, leaving `holes` open. Returns rectangles.
static func cover(outer: Rect2, holes: Array) -> Array[Rect2]:
	var xs := [outer.position.x, outer.end.x]
	for h in holes:
		xs.append(h.position.x)
		xs.append(h.end.x)
	xs.sort()
	var out: Array[Rect2] = []
	for k in xs.size() - 1:
		var x0: float = xs[k]
		var x1: float = xs[k + 1]
		if x1 - x0 < 0.001: continue
		var zs := [outer.position.y, outer.end.y]
		var blocked: Array = []
		for h in holes:
			if h.position.x <= x0 + 0.001 and h.end.x >= x1 - 0.001:
				blocked.append(h)
				zs.append(h.position.y)
				zs.append(h.end.y)
		zs.sort()
		for m in zs.size() - 1:
			var z0: float = zs[m]
			var z1: float = zs[m + 1]
			if z1 - z0 < 0.001: continue
			var mid := (z0 + z1) * 0.5
			var inside := false
			for h in blocked:
				if mid > h.position.y and mid < h.end.y: inside = true
			if not inside: out.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	return out

func _slab(parent: Node3D, r: Rect2, top: float, depth: float, color: Variant, collide: bool) -> void:
	var size := Vector3(r.size.x, depth, r.size.y)
	var pos := Vector3(r.get_center().x, top - depth / 2.0, r.get_center().y)
	Toy.box(parent, size, pos, color)
	if collide:
		var body := StaticBody3D.new()
		parent.add_child(body)
		Toy.shape(body, size, pos)

func _build_ground() -> void:
	var grass := Decor.grass()
	var sand := Decor.sand()
	for r in cover(WORLD, [SITE]): _slab(self, r, 0.0, 3.0, grass, true)
	ruts = Ruts.new()
	add_child(ruts)
	ruts.setup(SITE)
	ruts.apply(sand)
	# The whole site is diggable sand; bedrock underneath catches anything
	# that would slip through.
	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup(SITE, sand, [DUMP])
	var bedrock := StaticBody3D.new()
	add_child(bedrock)
	for r in cover(SITE, [DUMP]):
		Toy.shape(bedrock, Vector3(r.size.x, 1.0, r.size.y), Vector3(r.get_center().x, Terrain.LOWEST - 0.6, r.get_center().y))
	# Road outside the gate.
	Toy.box(self, Vector3(8, 0.04, 36), Vector3((GATE.x + GATE.y) / 2.0, 0.02, SITE.end.y + 18), Color("#5b5f66"))

func _build_pit() -> void:
	var r := pit_rect
	for ix in PIT_CELLS:
		for iz in PIT_CELLS:
			var c := {"x": r.position.x + CELL * (ix + 0.5), "z": r.position.y + CELL * (iz + 0.5), "depth": 0.0, "concrete": 0.0}
			c["rect"] = Rect2(c.x - CELL / 2.0, c.z - CELL / 2.0, CELL, CELL)
			var wet := Toy.box(self, Vector3(CELL, PIT_DEPTH, CELL), Vector3(c.x, -PIT_DEPTH / 2.0, c.z), Toy.mat(WET, 0.2))
			wet.visible = false
			c["wet"] = wet
			cells.append(c)
	# Pegs and string marking the future house.
	for corner in [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y)]:
		Toy.box(self, Vector3(0.12, 0.8, 0.12), Vector3(corner.x, 0.4, corner.y), Toy.WOOD)
	slab = AnimatableBody3D.new()
	slab.sync_to_physics = true
	add_child(slab)
	Toy.box(slab, Vector3(r.size.x, PIT_DEPTH, r.size.y), Vector3.ZERO, Toy.CONCRETE)
	Toy.shape(slab, Vector3(r.size.x, PIT_DEPTH, r.size.y), Vector3.ZERO)
	slab.position = Vector3(r.get_center().x, -PIT_DEPTH * 1.5 - 0.05, r.get_center().y)
	slab.visible = false

## Dig (or fill) a pit cell flat to its `depth`. For tests and the demo.
func _set_cell(c: Dictionary) -> void:
	terrain.flatten(c.rect.grow(0.01), -float(c.depth))

func _cell_at(p: Vector3) -> Dictionary:
	if not pit_rect.has_point(Vector2(p.x, p.z)): return {}
	var ix := clampi(int((p.x - pit_rect.position.x) / CELL), 0, PIT_CELLS - 1)
	var iz := clampi(int((p.z - pit_rect.position.y) / CELL), 0, PIT_CELLS - 1)
	return cells[ix * PIT_CELLS + iz]

## The excavator's bucket cuts at `p`: sand above the tip comes out, up
## to `amount` loads. Returns how much it got.
func dig_at(p: Vector3, amount: float) -> float:
	if not terrain.contains(p) or terrain.is_hole(p): return 0.0
	if (poured or pouring) and pit_rect.grow(0.3).has_point(Vector2(p.x, p.z)): return 0.0
	var c := _cell_at(p)
	if not c.is_empty() and float(c.concrete) > 0.0: return 0.0
	return terrain.cut(p, p.y - 0.2, 0.9, amount * VOL_PER_LOAD) / VOL_PER_LOAD

## A dozer blade edge at `p` scrapes sand above it and shoves it ahead
## along `ahead`, so a berm builds up in front of the blade.
func plow(p: Vector3, ahead: Vector3, max_volume: float) -> void:
	if not terrain.contains(p) or terrain.is_hole(p): return
	if (poured or pouring) and pit_rect.grow(0.3).has_point(Vector2(p.x, p.z)): return
	# The edge bites a little under itself, or the dozer would climb the
	# thin layer it leaves behind, a few centimetres at a time.
	var floor_y := p.y - 0.12
	if terrain.height_at(p) <= floor_y: return
	var got := terrain.cut(p, floor_y, 0.5, max_volume, true)
	# No slumping here: it would slide the berm back under the blade.
	if got > 0.0: terrain.add(p + ahead * 0.65, got, 0.6, false)

## Ground height under a point: the pit floor, dirt or concrete in the pit.
func ground_at(p: Vector3) -> float:
	if not terrain or not terrain.contains(p): return 0.0
	var c := _cell_at(p)
	if not c.is_empty():
		if poured: return 0.0
		if float(c.concrete) > 0.0: return maxf(terrain.height_at(p), -PIT_DEPTH + float(c.concrete) * PIT_DEPTH)
	return terrain.height_at(p)

## The hose pours `amount` (cells) at `p`. Returns false when it misses:
## outside the pit, or into a cell that isn't dug out yet or is already full.
func pour_at(p: Vector3, amount: float) -> bool:
	if poured or pouring or not unlocked[2]: return false
	var c := _cell_at(p)
	if c.is_empty() or float(c.depth) < PIT_DEPTH * 0.92: return false
	if float(c.concrete) >= 1.0:
		# Full: it slops over into the emptiest dug neighbour.
		var best: Dictionary = {}
		for o in cells:
			if absf(float(o.x) - float(c.x)) > CELL * 1.1 or absf(float(o.z) - float(c.z)) > CELL * 1.1: continue
			if float(o.depth) < PIT_DEPTH * 0.92 or float(o.concrete) >= 1.0: continue
			if best.is_empty() or float(o.concrete) < float(best.concrete): best = o
		if best.is_empty(): return false
		c = best
	c.concrete = minf(1.0, float(c.concrete) + amount)
	var h := maxf(0.02, float(c.concrete) * PIT_DEPTH)
	c.wet.visible = true
	c.wet.scale = Vector3(1, h / PIT_DEPTH, 1)
	c.wet.position = Vector3(c.x, -PIT_DEPTH + h / 2.0, c.z)
	return true

func pour_progress() -> float:
	var total := 0.0
	for c in cells: total += float(c.concrete)
	return total / cells.size()

## Concrete that missed the pit: a grey blob on the sand, for the shame.
func splat(p: Vector3) -> void:
	if splats.size() > 80: return
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = _rng.randf_range(0.25, 0.45)
	cm.bottom_radius = cm.top_radius + 0.08
	cm.height = 0.08
	cm.radial_segments = 10
	cm.rings = 1
	m.mesh = cm
	m.material_override = Toy.mat(WET, 0.35)
	add_child(m)
	m.global_position = Vector3(p.x + _rng.randf_range(-0.3, 0.3), ground_at(p) + 0.04, p.z + _rng.randf_range(-0.3, 0.3))
	splats.append(m)

func pit_progress() -> float:
	if poured: return 1.0
	var total := 0.0
	for c in cells: total += clampf(float(c.depth) / (PIT_DEPTH * 0.92), 0.0, 1.0)
	return total / cells.size()

## How deep each pit cell is dug, from the terrain.
func _measure_cells() -> void:
	for c in cells: c.depth = terrain.mean_depth(c.rect)

func spawn_clump(at: Vector3, amount: float, inherit: Vector3) -> void:
	var b := RigidBody3D.new()
	b.mass = 0.5
	b.add_to_group("clump")
	b.set_meta("amount", amount)
	var cs := CollisionShape3D.new()
	cs.shape = _clump_shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _clump_mesh
	mi.material_override = Toy.mat(Toy.DIRT if _rng.randf() < 0.6 else Toy.DIRT_DARK)
	b.add_child(mi)
	b.physics_material_override = PhysicsMaterial.new()
	b.physics_material_override.friction = 1.0
	b.physics_material_override.rough = true
	b.angular_damp = 2.0
	add_child(b)
	b.global_position = at + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2))
	b.linear_velocity = inherit + Vector3(_rng.randf_range(-0.5, 0.5), -1.0, _rng.randf_range(-0.5, 0.5))

# ── Dump, fence and props ────────────────────────────────────────────────────

func _build_dump() -> void:
	var r := DUMP
	# Hazard border.
	for side in 4:
		var horizontal := side < 2
		var span := r.size.x + 1.0 if horizontal else r.size.y + 1.0
		var holder := Node3D.new()
		holder.position = Vector3(r.get_center().x, 0.03, r.position.y - 0.25 if side == 0 else r.end.y + 0.25) if horizontal \
			else Vector3(r.position.x - 0.25 if side == 2 else r.end.x + 0.25, 0.03, r.get_center().y)
		holder.rotation.y = 0.0 if horizontal else PI / 2
		add_child(holder)
		Toy.stripes(holder, Vector3(span, 0.04, 0.5), Vector3.ZERO, int(span))
	Toy.box(self, Vector3(r.size.x, 0.1, r.size.y), Vector3(r.get_center().x, -6.0, r.get_center().y), Color("#2a1d14"))
	# A real hole: walls and a floor deep enough that a machine can fall in.
	var hole := StaticBody3D.new()
	add_child(hole)
	Toy.shape(hole, Vector3(r.size.x + 2.0, 1.0, r.size.y + 2.0), Vector3(r.get_center().x, -6.5, r.get_center().y))
	for side in 4:
		var horizontal := side < 2
		var size := Vector3(r.size.x + 2.0, 6.5, 1.0) if horizontal else Vector3(1.0, 6.5, r.size.y + 2.0)
		var pos := Vector3(r.get_center().x, -3.25, r.position.y - 0.5 if side == 0 else r.end.y + 0.5) if horizontal \
			else Vector3(r.position.x - 0.5 if side == 2 else r.end.x + 0.5, -3.25, r.get_center().y)
		Toy.shape(hole, size, pos)
	for side in 4:
		var horizontal := side < 2
		var size := Vector3(r.size.x, 6.0, 0.05) if horizontal else Vector3(0.05, 6.0, r.size.y)
		var pos := Vector3(r.get_center().x, -3.0, r.position.y + 0.03 if side == 0 else r.end.y - 0.03) if horizontal \
			else Vector3(r.position.x + 0.03 if side == 2 else r.end.x - 0.03, -3.0, r.get_center().y)
		Toy.box(self, size, pos, Color("#3d2a1c"))
	var sign_post := Node3D.new()
	sign_post.position = Vector3(r.end.x + 1.4, 0, r.position.y - 0.6)
	add_child(sign_post)
	Toy.box(sign_post, Vector3(0.15, 2.0, 0.15), Vector3(0, 1.0, 0), Toy.DARK)
	Toy.box(sign_post, Vector3(2.4, 1.0, 0.12), Vector3(0, 2.2, 0), Toy.YELLOW)
	Toy.label(sign_post, "DUMP", Vector3(0, 3.6, 0), Toy.YELLOW, 90)

func _build_fence() -> void:
	var r := SITE
	var panels: Array = []
	var x := r.position.x
	while x < r.end.x - 0.1:
		panels.append([Vector3(x + 1.0, 0, r.position.y), 0.0])
		if x + 1.0 < GATE.x or x + 1.0 > GATE.y:
			panels.append([Vector3(x + 1.0, 0, r.end.y), 0.0])
		x += 2.0
	var z := r.position.y
	while z < r.end.y - 0.1:
		panels.append([Vector3(r.position.x, 0, z + 1.0), PI / 2])
		panels.append([Vector3(r.end.x, 0, z + 1.0), PI / 2])
		z += 2.0
	var body := StaticBody3D.new()
	add_child(body)
	var k := 0
	for p in panels:
		var holder := Node3D.new()
		holder.position = p[0]
		holder.rotation.y = p[1]
		add_child(holder)
		var col := Toy.ORANGE if k % 2 == 0 else Color("#f6f1e7")
		Toy.box(holder, Vector3(1.9, 1.0, 0.1), Vector3(0, 0.75, 0), col)
		Toy.box(holder, Vector3(1.9, 0.12, 0.14), Vector3(0, 1.3, 0), Color("#f6f1e7") if k % 2 == 0 else Toy.ORANGE)
		Toy.box(holder, Vector3(0.4, 0.2, 0.6), Vector3(-0.8, 0.1, 0), Toy.DARK)
		var cs := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = Vector3(2.0, 1.4, 0.3)
		cs.shape = s
		cs.transform = holder.transform.translated_local(Vector3(0, 0.7, 0))
		body.add_child(cs)
		k += 1
	# Gate posts with a sign.
	for gx in [GATE.x, GATE.y]:
		Toy.box(self, Vector3(0.3, 3.0, 0.3), Vector3(gx, 1.5, r.end.y), Toy.DARK)
	Toy.box(self, Vector3(GATE.y - GATE.x + 0.3, 0.8, 0.12), Vector3((GATE.x + GATE.y) / 2.0, 3.2, r.end.y), Toy.YELLOW)

func _build_props() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	# Site hut (blue container) and a portable toilet.
	var hut := Vector3(-19.5, 0, 12.0)
	Toy.box(self, Vector3(6.0, 2.6, 2.6), hut + Vector3(0, 1.3, 0), Color("#3a7bd5"))
	Toy.box(self, Vector3(6.1, 0.14, 2.7), hut + Vector3(0, 2.65, 0), Color("#e9eef5"))
	for wx in [-1.8, 0.6, 2.0]:
		Toy.box(self, Vector3(0.9, 0.7, 0.06), hut + Vector3(wx, 1.6, -1.32), Toy.GLASS)
	Toy.box(self, Vector3(0.8, 1.8, 0.06), hut + Vector3(-0.7, 0.9, -1.32), Color("#e9eef5"))
	Toy.shape(body, Vector3(6.0, 2.6, 2.6), hut + Vector3(0, 1.3, 0))
	var loo := Vector3(-15.0, 0, 13.0)
	Toy.box(self, Vector3(1.3, 2.3, 1.3), loo + Vector3(0, 1.15, 0), Color("#3fb37f"))
	Toy.cyl(self, 0.75, 0.25, loo + Vector3(0, 2.4, 0), Color("#e9eef5"))
	Toy.shape(body, Vector3(1.3, 2.3, 1.3), loo + Vector3(0, 1.15, 0))
	# Pipes, crane pickup pad, material yard markings.
	for k in 3:
		Toy.cyl(self, 0.35, 5.0, Vector3(-20.5, 0.35 + k * 0.62 * (0.0 if k < 2 else 1.0), 2.0 + k * 0.72 - (0.36 if k == 2 else 0.0)), Color("#e05a3a"), Vector3(PI / 2, 0, 0))
	Toy.shape(body, Vector3(2.2, 1.3, 5.0), Vector3(-20.5, 0.65, 2.5))
	_marking(PAD, Vector2(5.5, 5.5), "CRANE PICKUP", Color("#ffd23f"))
	_marking(YARD, Vector2(10.5, 8.0), "DELIVERIES", Color("#f6f1e7"))
	# Cones
	for p in [Vector3(-7, 0, 1.5), Vector3(1.5, 0, 1.5), Vector3(-7.5, 0, -7.5), Vector3(13, 0, -5), Vector3(4, 0, 13), Vector3(14, 0, 13)]:
		Toy.cyl(self, 0.3, 0.8, p + Vector3(0, 0.4, 0), Toy.ORANGE, Vector3.ZERO, 0.05, 10)
		Toy.cyl(self, 0.21, 0.16, p + Vector3(0, 0.45, 0), Color.WHITE, Vector3.ZERO, 0.17, 10)
	Decor.site_props(self, body)
	# The world outside the fence.
	var keep_out: Array = Decor.street(self, SITE)
	keep_out.append(SITE.grow(1.5))
	keep_out.append(Rect2(GATE.x - 1, SITE.end.y, GATE.y - GATE.x + 2, 40))
	# Scenery gets its own dice so it never reshuffles the job layout.
	var deco := RandomNumberGenerator.new()
	deco.seed = 11
	Decor.greenery(self, deco, Rect2(-46, -32, 92, 58), keep_out)
	Decor.tufts(self, deco, Rect2(-46, -32, 92, 58), 2200, func(p: Vector2) -> bool:
		for r in keep_out: if r.has_point(p): return false
		return true, 2.0)
	# Sparse weeds inside the site, mostly along the fence and away from the work areas.
	var busy := [pit_rect.grow(1.5), DUMP.grow(1.0), Rect2(PAD.x - 3, PAD.z - 3, 6, 6), Rect2(YARD.x - 6, YARD.z - 5, 14, 10)]
	_tufts = Decor.tufts(self, deco, SITE.grow(-0.6), 260, func(p: Vector2) -> bool:
		for r in busy: if r.has_point(p): return false
		var edge := minf(minf(p.x - SITE.position.x, SITE.end.x - p.x), minf(p.y - SITE.position.y, SITE.end.y - p.y))
		return edge < 3.0 or deco.randf() < 0.18)

func _marking(center: Vector3, size: Vector2, text: String, color: Color) -> void:
	var t := 0.18
	for side in 4:
		var horizontal := side < 2
		var s := Vector3(size.x, 0.03, t) if horizontal else Vector3(t, 0.03, size.y)
		var p := center + (Vector3(0, 0.02, (-size.y if side == 0 else size.y) / 2.0) if horizontal else Vector3((-size.x if side == 2 else size.x) / 2.0, 0.02, 0))
		Toy.box(self, s, p, color)
	var l := Toy.label(self, text, center + Vector3(0, 0.05, size.y / 2.0 - 0.6), color, 70)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.rotation.x = -PI / 2
	l.no_depth_test = false

# ── House slots ──────────────────────────────────────────────────────────────

func _build_slots() -> void:
	var h := HOUSE
	var g := Module.SIZE.x / 2.0 + 0.02
	var floor_h := Module.SIZE.y
	for ox in [-g, g]:
		for oz in [-g, g]:
			slots.append({"pos": h + Vector3(ox, 0, oz), "kind": "module", "layer": 0})
	for ox in [-g, g]:
		slots.append({"pos": h + Vector3(ox, floor_h, -g), "kind": "module", "layer": 1})
	slots.append({"pos": h + Vector3(0, floor_h * 2.0, -g), "kind": "roof", "layer": 2})
	for s in slots:
		s["filled"] = null
		var ghost := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Module.SIZE if s.kind == "module" else Vector3(5.0, 1.4, 2.4)
		ghost.mesh = bm
		ghost.position = s.pos + Vector3(0, bm.size.y / 2.0, 0)
		ghost.material_override = Toy.ghost(Color(0.4, 0.9, 1.0), 0.12)
		ghost.visible = false
		add_child(ghost)
		var dots := MeshInstance3D.new()
		dots.mesh = _dashed_box(bm.size)
		dots.material_override = Toy.glow(Color(0.45, 0.95, 1.0), 1.2)
		ghost.add_child(dots)
		s["ghost"] = ghost
	_build_seams()

## Every place two parts of the house meet is a gap that needs foam: side
## by side on a floor, a floor on the one below, the roof on the top floor.
func _build_seams() -> void:
	var g := Module.SIZE.x / 2.0 + 0.02
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var a: Dictionary = slots[i]
			var b: Dictionary = slots[j]
			var d: Vector3 = b.pos - a.pos
			var flat := Vector2(d.x, d.z).length()
			var kind := ""
			if a.layer == b.layer and absf(flat - 2.0 * g) < 0.1: kind = "side"
			elif b.layer == a.layer + 1 and (flat < 0.1 or (b.kind == "roof" and absf(flat - g) < 0.1)): kind = "stack"
			if kind == "": continue
			var marker := MeshInstance3D.new()
			marker.material_override = Toy.glow(Color("#ff3b1f"), 0.5)
			marker.visible = false
			add_child(marker)
			seams.append({"a": a, "b": b, "kind": kind, "open": false, "done": false, "foam": 0.0, "need": 1.0, "marker": marker})

## Open seams once both their parts are bolted: how much foam a gap takes
## depends on how sloppily the two parts meet.
func _update_seams() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for sm in seams:
		if sm.done: continue
		if not sm.open:
			if sm.a.filled == null or sm.b.filled == null: continue
			if not (sm.a.filled.freeze and sm.b.filled.freeze): continue
			_open_seam(sm)
		sm.marker.material_override.emission_energy_multiplier = 0.5 + 0.4 * sin(t * 6.0)

func _open_seam(sm: Dictionary) -> void:
	sm.open = true
	var ma: Module = sm.a.filled
	var mb: Module = sm.b.filled
	var ca := ma.center()
	var cb := mb.center()
	var ideal: Vector3 = sm.b.pos - sm.a.pos
	var actual := cb - ca
	var err := Vector2(actual.x - ideal.x, actual.z - ideal.z).length()
	err += absf(angle_difference(ma.global_rotation.y, mb.global_rotation.y)) * 1.5
	sm.need = 1.0 + err * 6.0
	var box := BoxMesh.new()
	var lower_yaw := ma.global_rotation.y
	if sm.kind == "side":
		var along := Vector3(actual.x, 0, actual.z).normalized()
		box.size = Vector3(0.3 + err * 0.5, Module.SIZE.y + 0.4, Module.SIZE.z + 0.4)
		sm.marker.mesh = box
		sm.marker.global_transform = Transform3D(Basis(Vector3.UP, atan2(-along.z, along.x)), (ca + cb) * 0.5)
		sm["spot"] = (ca + cb) * 0.5
		sm["span"] = Vector3(-along.z, 0, along.x) * (Module.SIZE.z / 2.0 - 0.1)
	else:
		var top := ca + Vector3(0, Module.SIZE.y / 2.0, 0)
		var w := Module.SIZE.x + 0.1
		box.size = Vector3(w + 0.35, 0.28 + err * 0.4, w + 0.35)
		sm.marker.mesh = box
		sm.marker.global_transform = Transform3D(Basis(Vector3.UP, lower_yaw), top)
		sm["spot"] = top
		sm["span"] = Basis(Vector3.UP, lower_yaw) * Vector3(w / 2.0, 0, 0)
	sm.marker.visible = true

## Somewhere along a seam for a foam blob to land.
func seam_spot(sm: Dictionary) -> Vector3:
	var p: Vector3 = sm.spot + sm.span * randf_range(-1.0, 1.0)
	if sm.kind == "side": p.y += randf_range(-0.9, 0.9)
	else: p += Vector3(-sm.span.z, 0, sm.span.x) * (1.0 if randf() < 0.5 else -1.0)
	return p

## The open, unfoamed seam a gun at `from` pointing along `fwd` reaches.
func seam_ahead(from: Vector3, fwd: Vector3, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := reach
	for sm in seams:
		if not sm.open or sm.done: continue
		# Closest point on the seam's span, measured flat: a gun reaches up.
		var a: Vector3 = sm.spot - sm.span
		var b: Vector3 = sm.spot + sm.span
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(from.x - a.x, from.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := Vector2(a.x, a.z) + ab * t
		var to := q - Vector2(from.x, from.z)
		var d := to.length()
		if sm.kind == "stack": d = maxf(0.0, d - Module.SIZE.x / 2.0)
		if d > 0.3 and to.normalized().dot(Vector2(fwd.x, fwd.z)) < 0.2: continue
		if d < best_d:
			best_d = d
			best = sm
	return best

func foam_seam(sm: Dictionary, amount: float) -> void:
	if sm.done: return
	sm.foam = float(sm.foam) + amount
	if sm.foam >= sm.need:
		sm.done = true
		sm.marker.visible = false
		var left := 0
		for o in seams: if not o.done: left += 1
		message.emit("Sealed! %d gaps left" % left if left > 0 else "Every gap sealed!")

func seams_done() -> int:
	var n := 0
	for sm in seams: if sm.done: n += 1
	return n

## The ghost's dotted outline: every edge of a box as short dashes, one mesh.
func _dashed_box(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dash := BoxMesh.new()
	var h := size / 2.0
	for axis in 3:
		var len: float = size[axis]
		var count := maxi(2, int(len / 0.42))
		var step := len / count
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				var edge := Vector3.ZERO
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				edge[u] = a * h[u]
				edge[v] = b * h[v]
				for k in count:
					var c := edge
					c[axis] = -h[axis] + step * (k + 0.5)
					var sz := Vector3.ONE * 0.07
					sz[axis] = step * 0.55
					dash.size = sz
					st.append_from(dash, 0, Transform3D(Basis.IDENTITY, c))
	return st.commit()

func active_layer() -> int:
	if not poured: return -1
	for layer in 3:
		for s in slots:
			if s.layer == layer and s.filled == null: return layer
	return 3

func placed_count() -> int:
	var n := 0
	for s in slots: if s.filled != null: n += 1
	return n

func _check_slots() -> void:
	var layer := active_layer()
	var t := Time.get_ticks_msec() / 1000.0
	for s in slots:
		s.ghost.visible = s.layer == layer and s.filled == null
		if s.ghost.visible:
			s.ghost.material_override.albedo_color.a = 0.08 + 0.06 * sin(t * 4.0)
			s.ghost.get_child(0).material_override.emission_energy_multiplier = 1.0 + 0.6 * sin(t * 4.0)
	for m in get_tree().get_nodes_in_group("module"):
		if m.placed: continue
		m.show_bolt_tag(layer >= 0 and layer <= 2 and bolt_problem(m) == "")

## The free ghost of the active layer nearest to a module, or {}.
func slot_for(m: Module) -> Dictionary:
	var layer := active_layer()
	var best: Dictionary = {}
	var best_d := INF
	for s in slots:
		if s.layer != layer or s.filled != null or s.kind != m.kind: continue
		var d: Vector3 = m.global_position - s.pos
		var h := Vector2(d.x, d.z).length()
		if h < best_d:
			best_d = h
			best = s
	return best

## Why a module can't be bolted in yet, or "" when it can.
func bolt_problem(m: Module) -> String:
	if not poured: return "Pour the foundation first"
	var s := slot_for(m)
	if s.is_empty(): return "Not this one yet"
	var d: Vector3 = m.global_position - s.pos
	if Vector2(d.x, d.z).length() > BOLT_REACH: return "Get it onto the ghost"
	if d.y > 0.7: return "Lower it down first"
	if d.y < -0.5: return "It's sunk too low"
	if m.global_transform.basis.y.y < 0.92: return "It's tipped over"
	if _yaw_error(m) > BOLT_TWIST: return "Too crooked, turn it"
	if m.linear_velocity.length() > 1.2: return "Hold it still"
	return ""

func _yaw_error(m: Module) -> float:
	var step := PI / 2.0 if m.kind == "module" else PI
	var yaw: float = m.global_rotation.y
	return absf(angle_difference(yaw, roundf(yaw / step) * step))

## A builder bolts `m` in where it stands. Returns "" or what's wrong.
func bolt(m: Module) -> String:
	var why := bolt_problem(m)
	if why != "": return why
	var s := slot_for(m)
	var d: Vector3 = m.global_position - s.pos
	s.filled = m
	s["off"] = Vector2(d.x, d.z).length()
	s["twist"] = _yaw_error(m)
	m.bolt()
	var left := slots.size() - placed_count()
	if left == 0:
		message.emit("House stacked! Now PUR every gap")
	else:
		var verdict := "Perfect!" if s.off < 0.12 and s.twist < 0.04 else ("Bit wonky..." if s.off > 0.45 or s.twist > 0.15 else "Bolted!")
		message.emit("%s %d to go" % [verdict, left])
	return ""

## How straight the house is, 0..100: off-centre and twisted parts cost.
func neatness() -> int:
	var total := 0.0
	var n := 0
	for s in slots:
		if s.filled == null: continue
		total += clampf(1.0 - float(s.get("off", 0.0)) / BOLT_REACH * 0.6 - float(s.get("twist", 0.0)) / BOLT_TWIST * 0.4, 0.0, 1.0)
		n += 1
	return int(round(100.0 * total / maxf(n, 1)))

# ── Modules, rubble, machines ────────────────────────────────────────────────

func _spawn_modules() -> void:
	var spots := []
	for row in 2:
		for col in 3:
			spots.append(YARD + Vector3(-3.4 + col * 3.4, 0, -2.0 + row * 3.6))
	for k in 6:
		_spawn_module("module", spots[k], 0.0)
	_spawn_module("roof", YARD + Vector3(6.0, 0, 0.0), 0.0)

## Pallets face west, so forklifts drive in from the site side.
func _spawn_module(kind: String, at: Vector3, drop := 0.0) -> Module:
	var m := Module.new()
	m.setup(kind, _module_count)
	_module_count += 1
	add_child(m)
	m.global_transform = Transform3D(Basis(Vector3.UP, PI / 2), at + Vector3(0, 0.02 + drop, 0))
	return m

func _spawn_rubble() -> void:
	var pieces := [
		["slab", Vector3(-4.5, 0, -1.5)], ["slab", Vector3(-1.0, 0, -4.5)], ["tyre", Vector3(2.5, 0, -8.0)],
		["barrel", Vector3(6.0, 0, -2.0)], ["sofa", Vector3(-6.0, 0, -6.5)], ["slab", Vector3(8.0, 0, -9.0)],
		["tyre", Vector3(-9.0, 0, 0.5)], ["fridge", Vector3(1.5, 0, 4.0)],
	]
	rubble_total = pieces.size()
	for p in pieces:
		var b := RigidBody3D.new()
		b.add_to_group("rubble")
		b.physics_material_override = PhysicsMaterial.new()
		b.physics_material_override.friction = 0.7
		var kind: String = p[0]
		match kind:
			"slab":
				var s := Vector3(_rng.randf_range(1.4, 2.0), _rng.randf_range(0.5, 0.8), _rng.randf_range(1.2, 1.8))
				Toy.box(b, s, Vector3(0, s.y / 2.0, 0), Color("#8d887e"))
				Toy.box(b, Vector3(s.x * 0.6, 0.1, 0.1), Vector3(0.1, s.y + 0.05, 0.2), Color("#8a4b2b"), Vector3(0, 0.6, 0))
				Toy.shape(b, s, Vector3(0, s.y / 2.0, 0))
				b.mass = 2.5
			"tyre":
				var t := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.45
				tm.outer_radius = 0.95
				t.mesh = tm
				t.position.y = 0.25
				t.material_override = Toy.mat(Toy.DARK)
				b.add_child(t)
				Toy.shape(b, Vector3(1.9, 0.5, 1.9), Vector3(0, 0.25, 0))
				b.mass = 1.0
			"barrel":
				Toy.cyl(b, 0.45, 1.1, Vector3(0, 0.55, 0), Color("#3e7c6a"))
				Toy.cyl(b, 0.47, 0.08, Vector3(0, 0.75, 0), Color("#2e5a4d"))
				Toy.shape(b, Vector3(0.9, 1.1, 0.9), Vector3(0, 0.55, 0))
				b.mass = 1.2
			"sofa":
				var c := Color("#c0584b")
				Toy.box(b, Vector3(2.4, 0.5, 1.0), Vector3(0, 0.35, 0), c)
				Toy.box(b, Vector3(2.4, 0.7, 0.3), Vector3(0, 0.8, 0.4), c.darkened(0.15))
				for x in [-1.1, 1.1]: Toy.box(b, Vector3(0.25, 0.65, 1.0), Vector3(x, 0.55, 0), c.darkened(0.1))
				Toy.box(b, Vector3(0.5, 0.2, 0.4), Vector3(-0.4, 0.68, -0.1), Color("#f2d16b"), Vector3(0.2, 0.3, 0))
				Toy.shape(b, Vector3(2.4, 1.0, 1.0), Vector3(0, 0.5, 0.0))
				b.mass = 1.5
			"fridge":
				Toy.box(b, Vector3(0.9, 1.8, 0.8), Vector3(0, 0.9, 0), Color("#e8e4d8"))
				Toy.box(b, Vector3(0.06, 0.6, 0.06), Vector3(0.3, 1.2, -0.42), Toy.STEEL)
				Toy.shape(b, Vector3(0.9, 1.8, 0.8), Vector3(0, 0.9, 0))
				b.mass = 1.5
		add_child(b)
		b.global_position = p[1] + Vector3(0, 0.05, 0)
		b.rotation.y = _rng.randf_range(-PI, PI)
		if kind == "fridge":
			b.rotation.x = PI / 2   # lying on its back
			b.global_position.y = 0.45
		# A bobbing arrow so it's clear what counts as junk.
		var mark := Node3D.new()
		mark.top_level = true
		mark.name = "JunkMark"
		b.add_child(mark)
		Toy.cyl(mark, 0.24, 0.42, Vector3.ZERO, Toy.ORANGE, Vector3(PI, 0, 0), 0.0, 8)

## A crate by the builders' gate with two foam guns on it.
## Tufts stand on the ground: they sink and rise with it, and vanish where
## it's been dug up or buried.
func _settle_tufts() -> void:
	if _tufts == null or terrain.changed_since == _tufts_seen: return
	_tufts_seen = terrain.changed_since
	var mm := _tufts.multimesh
	if _tuft_rest.is_empty():
		for k in mm.instance_count: _tuft_rest.append(mm.get_instance_transform(k))
	for k in mm.instance_count:
		var xf: Transform3D = _tuft_rest[k]
		var y := terrain.height_at(xf.origin)
		if absf(y) > 0.12: xf = xf.scaled_local(Vector3.ZERO)
		mm.set_instance_transform(k, xf)

func _spawn_tools() -> void:
	var crate := Vector3(-15.5, 0, 7.0)
	Toy.box(self, Vector3(1.8, 0.5, 1.0), crate + Vector3(0, 0.25, 0), Color("#2a8ad6"))
	Toy.label(self, "PUR", crate + Vector3(0, 0.55, 0.55), Color.WHITE, 48).rotation.x = -PI / 2
	for k in 2:
		var gun := FoamGun.new()
		gun.site = self
		gun.position = crate + Vector3(-0.45 + k * 0.9, 0.5, 0)
		add_child(gun)
		tools.append(gun)

func _spawn_machines() -> void:
	var defs := [
		[Excavator, Vector3(-3, 0, 4.5), 0.0],
		[DumpTruck, Vector3(5.5, 0, 1.0), 0.0],
		[Bulldozer, Vector3(-13, 0, 3.0), -PI / 2],
		[Forklift, Vector3(6.5, 0, 6.0), -PI / 2],
		[Forklift, Vector3(6.5, 0, 9.6), -PI / 2],
		[Crane, CRANE_AT, 0.0],
		[ConcreteTruck, Vector3(12.0, 0, 0.5), 0.0],
	]
	for d in defs:
		var m: Machine = d[0].new()
		m.site = self
		m.position = d[1]
		m.rotation.y = d[2]
		add_child(m)
		m.home = m.global_transform
		machines.append(m)
		if m is Crane:
			crane = m
			var to := HOUSE - CRANE_AT
			m.slew.rotation.y = atan2(-to.x, -to.z)
			m.reach = Vector2(to.x, to.z).length()
			m._pose()
			m.ready_hook()

func set_easy(value: bool) -> void:
	easy = value
	for m in machines:
		if m.has_method("set_easy"): m.set_easy(value)

# ── Job loop ─────────────────────────────────────────────────────────────────

func tasks() -> Array:
	var house := placed_count()
	var list := [
		{"value": rubble_cleared, "total": rubble_total, "done": rubble_cleared >= rubble_total},
		{"value": int(round(pit_progress() * 100.0)), "total": 100, "done": pit_progress() >= 0.999 or poured, "percent": true},
		{"value": 100 if poured else int(floor(pour_progress() * 100.0)), "total": 100, "done": poured, "percent": true},
		{"value": house, "total": slots.size(), "done": house >= slots.size()},
		{"value": seams_done(), "total": seams.size(), "done": seams_done() >= seams.size()},
	]
	for k in list.size():
		list[k]["label"] = STEP_NAMES[k]
		list[k]["after"] = STEP_AFTER[k]
		list[k]["locked"] = not unlocked[k]
	return list

## Open the next steps as the earlier ones get done.
func _update_unlocks() -> void:
	var want := [true, true, unlocked[2] or pit_progress() >= 0.999 or poured, poured,
		seams.any(func(sm: Dictionary) -> bool: return sm.open)]
	for k in want.size():
		if want[k] and not unlocked[k]:
			unlocked[k] = true
			message.emit("New step: %s!" % STEP_NAMES[k])

func _physics_process(delta: float) -> void:
	for m in machines:
		for k in m.marks.size():
			var mk: Array = m.marks[k]
			var g: Vector3 = m.global_transform * mk[0]
			g.y -= ground_at(g)
			ruts.follow(m.get_instance_id() * 8 + k, g, mk[1], 0.85 if mk[2] else 0.7, mk[2])
	_cells_timer -= delta
	if _cells_timer <= 0.0:
		_cells_timer = 0.2
		_measure_cells()
		_settle_tufts()
	var dump_rect := DUMP
	for b in get_tree().get_nodes_in_group("clump"):
		var p: Vector3 = b.global_position
		var xz := Vector2(p.x, p.z)
		if dump_rect.has_point(xz) and p.y < -1.0:
			dirt_dumped += float(b.get_meta("amount", 0.25))
			b.queue_free()
		elif terrain.contains(p) and not terrain.is_hole(p):
			# A clump that comes to rest on the ground becomes ground again.
			var rest: float = b.get_meta("rest", 0.0)
			var on_ground := p.y - terrain.height_at(p) < 0.75
			rest = rest + delta if on_ground and b.linear_velocity.length() < 0.6 else 0.0
			b.set_meta("rest", rest)
			if rest > 0.5:
				var c := _cell_at(p)
				if c.is_empty() or (float(c.concrete) <= 0.0 and not poured and not pouring):
					terrain.add(Vector3(p.x, 0, p.z), float(b.get_meta("amount", 0.25)) * VOL_PER_LOAD, 0.9)
				b.queue_free()
		elif p.y < -8.0:
			b.queue_free()
	var bob := sin(Time.get_ticks_msec() * 0.003) * 0.06
	for b in get_tree().get_nodes_in_group("rubble"):
		var p: Vector3 = b.global_position
		var mark: Node3D = b.get_node_or_null("JunkMark")
		if mark: mark.global_position = p + Vector3(0, 2.0 + bob, 0)
		if dump_rect.has_point(Vector2(p.x, p.z)) and p.y < -1.0:
			rubble_cleared += 1
			b.remove_from_group("rubble")
			b.queue_free()
			message.emit("Junk dumped! %d left" % (rubble_total - rubble_cleared) if rubble_cleared < rubble_total else "Site cleared!")
			_check_done()
		elif p.y < -8.0:
			b.global_position = Vector3(0, 2, 10)
	for m in get_tree().get_nodes_in_group("module"):
		if m.placed: continue
		if m.global_position.y < -2.0:
			m.remove_from_group("module")
			m.remove_from_group("liftable")
			if m.is_hooked(): m._crane.release()
			m.queue_free()
			_pending_deliveries += 1
			_delivery_timer = 2.0
			message.emit("Oops! Ordering a new " + ("roof" if m.kind == "roof" else "module") + "...")
	if _pending_deliveries > 0:
		_delivery_timer -= delta
		if _delivery_timer <= 0.0:
			_pending_deliveries -= 1
			_delivery_timer = 1.0
			var need_roof := true
			for m in get_tree().get_nodes_in_group("module"):
				if m.kind == "roof": need_roof = false
			for s in slots:
				if s.kind == "roof" and s.filled != null: need_roof = false
			_spawn_module("roof" if need_roof else "module", YARD + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-2, 2)), 4.0)
			message.emit("Delivery!")
	if not poured and not pouring and pour_progress() >= 0.999:
		_pour()
	_check_slots()
	_update_seams()
	_update_unlocks()
	if not finished and placed_count() == slots.size() and seams_done() == seams.size():
		message.emit("HOUSE COMPLETE! Neatness %d%%" % neatness())
		_finish()

## All cells full: the wet concrete sets into the slab.
func _pour() -> void:
	pouring = true
	message.emit("Pit full! Concrete setting...")
	var r := pit_rect
	terrain.flatten(r.grow(0.2), -PIT_DEPTH)
	slab.position = Vector3(r.get_center().x, -PIT_DEPTH / 2.0 - 0.01, r.get_center().y)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func() -> void:
		slab.visible = true
		slab.position.y = -PIT_DEPTH / 2.0
		for c in cells: c.wet.visible = false
		pouring = false
		poured = true
		message.emit("Foundation ready! Crane the modules on")
		_check_done())

func _check_done() -> void:
	pass

func _finish() -> void:
	if finished: return
	finished = true
	job_done.emit()

## Demo/screenshot helper: jump the job forward.
func cheat(stage: String) -> void:
	if stage in ["dug", "poured", "built", "half"]:
		unlocked[2] = true
		for c in cells:
			c.depth = PIT_DEPTH
			_set_cell(c)
		_measure_cells()
		for c in cells:
			if stage == "poured": pour_at(Vector3(c.x, -0.5, c.z), 1.0)
		for b in get_tree().get_nodes_in_group("rubble"):
			if stage not in ["dug", "poured"] or randf() < 0.5:
				rubble_cleared += 1
				b.remove_from_group("rubble")
				b.queue_free()
	if stage in ["built", "half"]:
		unlocked[3] = true
		unlocked[4] = true
		poured = true
		terrain.flatten(pit_rect.grow(0.2), -PIT_DEPTH)
		for c in cells: c.depth = PIT_DEPTH
		slab.visible = true
		slab.position = Vector3(pit_rect.get_center().x, -PIT_DEPTH / 2.0, pit_rect.get_center().y)
		var mods := get_tree().get_nodes_in_group("module")
		var n := 4 if stage == "half" else slots.size()
		for k in n:
			var s: Dictionary = slots[k]
			for m in mods:
				if m.placed or m.kind != s.kind: continue
				# A little wonky, like a real crew would leave it.
				s.filled = m
				s["off"] = _rng.randf_range(0.0, 0.2)
				s["twist"] = _rng.randf_range(0.0, 0.06)
				var a := _rng.randf() * TAU
				m.global_transform = Transform3D(Basis(Vector3.UP, s.twist * (1 if k % 2 else -1)), s.pos + Vector3(cos(a), 0, sin(a)) * s.off + Vector3(0, 0.02 * k, 0))
				m.bolt()
				break
