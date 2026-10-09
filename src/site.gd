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
const PIT_DEPTH := 1.0
const DIG_PER_LOAD := 0.5        ## Metres of one cell removed by a full bucket.
const DUMP := Rect2(15.5, -11.5, 6.0, 5.0)
const CRANE_AT := Vector3(-13, 0, -10)
const PAD := Vector3(-8, 0, 6)
const YARD := Vector3(16, 0, 8)
const SPAWN := Vector3(-18, 0, 10)
const GATE := Vector2(5.0, 13.0)   ## x range of the gate in the bottom fence

var pit_rect := Rect2(HOUSE.x - 3, HOUSE.z - 3, 6, 6)
var cells: Array[Dictionary] = []
var slab: AnimatableBody3D
var poured := false
var pouring := false
var slots: Array[Dictionary] = []
var machines: Array[Machine] = []
var crane: Crane
var rubble_total := 0
var rubble_cleared := 0
var dirt_dumped := 0.0
var finished := false
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
	var holes := [pit_rect, DUMP]
	var grass := Decor.grass()
	var sand := Decor.sand()
	for r in cover(WORLD, [SITE]): _slab(self, r, 0.0, 3.0, grass, true)
	for r in cover(SITE, holes): _slab(self, r, 0.0, 3.0, sand, true)
	# Road outside the gate.
	Toy.box(self, Vector3(8, 0.04, 36), Vector3((GATE.x + GATE.y) / 2.0, 0.02, SITE.end.y + 18), Color("#5b5f66"))

func _build_pit() -> void:
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	var r := pit_rect
	Toy.box(self, Vector3(r.size.x, 0.4, r.size.y), Vector3(r.get_center().x, -PIT_DEPTH - 0.2, r.get_center().y), Toy.DIRT_DARK)
	Toy.shape(floor_body, Vector3(r.size.x, 0.4, r.size.y), Vector3(r.get_center().x, -PIT_DEPTH - 0.2, r.get_center().y))
	# Pit walls get a darker skin so the hole reads from above.
	for side in 4:
		var horizontal := side < 2
		var size := Vector3(r.size.x, PIT_DEPTH, 0.04) if horizontal else Vector3(0.04, PIT_DEPTH, r.size.y)
		var pos := Vector3(r.get_center().x, -PIT_DEPTH / 2.0, r.position.y + 0.02 if side == 0 else r.end.y - 0.02) if horizontal \
			else Vector3(r.position.x + 0.02 if side == 2 else r.end.x - 0.02, -PIT_DEPTH / 2.0, r.get_center().y)
		Toy.box(self, size, pos, Color("#8b5e36"))
	for ix in PIT_CELLS:
		for iz in PIT_CELLS:
			var c := {"x": r.position.x + CELL * (ix + 0.5), "z": r.position.y + CELL * (iz + 0.5), "depth": 0.0}
			var body := StaticBody3D.new()
			add_child(body)
			var shape := Toy.shape(body, Vector3(CELL, PIT_DEPTH, CELL), Vector3(c.x, -PIT_DEPTH / 2.0, c.z))
			var mesh := Toy.box(self, Vector3(CELL, PIT_DEPTH, CELL), Vector3(c.x, -PIT_DEPTH / 2.0, c.z), Toy.DIRT)
			var top := Toy.box(self, Vector3(CELL - 0.06, 0.04, CELL - 0.06), Vector3(c.x, 0.02, c.z), Color("#b98552"))
			c["shape"] = shape
			c["mesh"] = mesh
			c["top"] = top
			cells.append(c)
	# Pegs and string marking the future house.
	for corner in [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y)]:
		Toy.box(self, Vector3(0.12, 0.8, 0.12), Vector3(corner.x, 0.4, corner.y), Toy.WOOD)
	slab = AnimatableBody3D.new()
	slab.sync_to_physics = true
	add_child(slab)
	Toy.box(slab, Vector3(r.size.x, PIT_DEPTH, r.size.y), Vector3.ZERO, Toy.CONCRETE)
	slab.position = Vector3(r.get_center().x, -PIT_DEPTH * 1.5 - 0.05, r.get_center().y)
	slab.visible = false

func _set_cell(c: Dictionary) -> void:
	var h := PIT_DEPTH - float(c.depth)
	if h < 0.02:
		c.shape.disabled = true
		c.mesh.visible = false
		c.top.visible = false
		return
	c.shape.disabled = false
	c.mesh.visible = true
	c.top.visible = true
	(c.shape.shape as BoxShape3D).size = Vector3(CELL, h, CELL)
	c.shape.position = Vector3(c.x, -PIT_DEPTH + h / 2.0, c.z)
	c.mesh.scale = Vector3(1, h / PIT_DEPTH, 1)
	c.mesh.position = Vector3(c.x, -PIT_DEPTH + h / 2.0, c.z)
	c.top.position = Vector3(c.x, -PIT_DEPTH + h + 0.02, c.z)

func _cell_at(p: Vector3) -> Dictionary:
	if not pit_rect.has_point(Vector2(p.x, p.z)): return {}
	var ix := clampi(int((p.x - pit_rect.position.x) / CELL), 0, PIT_CELLS - 1)
	var iz := clampi(int((p.z - pit_rect.position.y) / CELL), 0, PIT_CELLS - 1)
	return cells[ix * PIT_CELLS + iz]

## The excavator scoops at `p`. Returns how much load it got.
func dig_at(p: Vector3, amount: float) -> float:
	if poured or pouring: return 0.0
	var c := _cell_at(p)
	if c.is_empty(): return 0.0
	var top := -float(c.depth)
	if p.y > top + 0.3 or float(c.depth) >= PIT_DEPTH: return 0.0
	var take := minf(amount, (PIT_DEPTH - float(c.depth)) / DIG_PER_LOAD)
	c.depth = minf(PIT_DEPTH, float(c.depth) + take * DIG_PER_LOAD)
	_set_cell(c)
	return take

func pit_progress() -> float:
	var total := 0.0
	for c in cells: total += float(c.depth)
	return total / (PIT_DEPTH * cells.size())

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
	Decor.tufts(self, deco, SITE.grow(-0.6), 260, func(p: Vector2) -> bool:
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
		ghost.material_override = Toy.ghost(Color(0.4, 0.9, 1.0), 0.28)
		ghost.visible = false
		add_child(ghost)
		s["ghost"] = ghost

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
			s.ghost.material_override.albedo_color.a = 0.18 + 0.14 * sin(t * 4.0)
	if layer < 0 or layer > 2: return
	for m in get_tree().get_nodes_in_group("module"):
		if m.placed: continue
		for s in slots:
			if s.layer != layer or s.filled != null or s.kind != m.kind: continue
			var d: Vector3 = m.global_position - s.pos
			if Vector2(d.x, d.z).length() > 1.1: continue
			if d.y < -0.4 or d.y > 0.9: continue
			if m.linear_velocity.length() > 3.0: continue
			var yaw: float = m.global_rotation.y
			var step := PI / 2.0 if m.kind == "module" else PI
			var snapped := roundf(yaw / step) * step
			if m.kind == "roof" and absf(angle_difference(yaw, snapped)) > 0.6: continue
			if m.global_transform.basis.y.y < 0.85: continue
			s.filled = m
			m.place(Transform3D(Basis(Vector3.UP, snapped), s.pos))
			var left := slots.size() - placed_count()
			if left == 0:
				message.emit("HOUSE COMPLETE!")
				_finish()
			elif m.kind == "roof":
				pass
			else:
				message.emit("Module placed! %d to go" % left)
			break

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

func _spawn_machines() -> void:
	var defs := [
		[Excavator, Vector3(-3, 0, 4.5), 0.0],
		[DumpTruck, Vector3(5.5, 0, 1.0), 0.0],
		[Bulldozer, Vector3(-13, 0, 3.0), -PI / 2],
		[Forklift, Vector3(6.5, 0, 6.0), -PI / 2],
		[Forklift, Vector3(6.5, 0, 9.6), -PI / 2],
		[Crane, CRANE_AT, 0.0],
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
	return [
		{"label": "Clear the junk", "value": rubble_cleared, "total": rubble_total, "done": rubble_cleared >= rubble_total},
		{"label": "Dig the foundation pit", "value": int(round(pit_progress() * 100.0)), "total": 100, "done": poured or pouring, "percent": true},
		{"label": "Pour the concrete", "value": 1 if poured else 0, "total": 1, "done": poured, "auto": true},
		{"label": "Stack the house", "value": house, "total": slots.size(), "done": house >= slots.size()},
	]

func _physics_process(delta: float) -> void:
	var dump_rect := DUMP
	for b in get_tree().get_nodes_in_group("clump"):
		var p: Vector3 = b.global_position
		var xz := Vector2(p.x, p.z)
		if dump_rect.has_point(xz) and p.y < -1.0:
			dirt_dumped += float(b.get_meta("amount", 0.25))
			b.queue_free()
		elif pit_rect.has_point(xz) and p.y < -0.05 and not poured and not pouring:
			var c := _cell_at(p)
			if not c.is_empty() and p.y < -float(c.depth) + 0.6 and b.linear_velocity.length() < 1.5:
				c.depth = maxf(0.0, float(c.depth) - float(b.get_meta("amount", 0.25)) * DIG_PER_LOAD)
				_set_cell(c)
				b.queue_free()
		elif p.y < -8.0:
			b.queue_free()
	for b in get_tree().get_nodes_in_group("rubble"):
		var p: Vector3 = b.global_position
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
	if not poured and not pouring and pit_progress() >= 0.999:
		_pour()
	_check_slots()

func _pour() -> void:
	pouring = true
	message.emit("Pit dug! Pouring concrete...")
	for c in cells:
		c.shape.disabled = true
		c.mesh.visible = false
		c.top.visible = false
	slab.visible = true
	var r := pit_rect
	var tw := create_tween()
	tw.tween_property(slab, "position", Vector3(r.get_center().x, -PIT_DEPTH / 2.0, r.get_center().y), 3.0).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
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
	if stage in ["dug", "built", "half"]:
		for c in cells:
			c.depth = PIT_DEPTH
			_set_cell(c)
		for b in get_tree().get_nodes_in_group("rubble"):
			if stage != "dug" or randf() < 0.5:
				rubble_cleared += 1
				b.remove_from_group("rubble")
				b.queue_free()
	if stage in ["built", "half"]:
		poured = true
		for c in cells:
			c.shape.disabled = true
			c.mesh.visible = false
			c.top.visible = false
		slab.visible = true
		slab.position = Vector3(pit_rect.get_center().x, -PIT_DEPTH / 2.0, pit_rect.get_center().y)
		var mods := get_tree().get_nodes_in_group("module")
		var n := 4 if stage == "half" else slots.size()
		for k in n:
			var s: Dictionary = slots[k]
			for m in mods:
				if m.placed or m.kind != s.kind: continue
				s.filled = m
				m.global_position = s.pos
				m.place(Transform3D(Basis.IDENTITY, s.pos))
				break
