class_name Terrain
extends Node3D
## The building site's ground as a height grid of diggable sand. Buckets cut
## it, dirt piles onto it, blades push it around. Built from chunks so a dig
## only rebuilds the mesh and collision near it.

const RES := 0.5        ## Metres between grid points.
const CHUNK := 12       ## Quads per chunk side.
const LOWEST := -2.5    ## Bedrock: nothing digs deeper.
const HIGHEST := 2.5    ## Piles never grow taller than this.

var rect: Rect2
var nx := 0
var nz := 0
var h := PackedFloat32Array()
var locked := PackedByteArray()   ## 1 = this point can't change (edges, holes).
var _hole := PackedByteArray()    ## Per quad: 1 = no ground (the dump).
var _chunks: Array[Dictionary] = []
var _material: Material
var changed_since := 0            ## Bumped on every edit, for listeners.

func setup(area: Rect2, material: Material, holes: Array) -> void:
	rect = area
	_material = material
	nx = int(round(area.size.x / RES)) + 1
	nz = int(round(area.size.y / RES)) + 1
	h.resize(nx * nz)
	locked.resize(nx * nz)
	_hole.resize((nx - 1) * (nz - 1))
	for j in nz:
		for i in nx:
			var edge := i == 0 or j == 0 or i == nx - 1 or j == nz - 1
			locked[j * nx + i] = 1 if edge else 0
	for j in nz - 1:
		for i in nx - 1:
			var c := _point(i, j) + Vector2(RES, RES) * 0.5
			for r in holes:
				if r.has_point(c): _hole[j * (nx - 1) + i] = 1
	# Points on a hole's rim stay put, so the dump keeps its shape.
	for j in nz:
		for i in nx:
			for q in [[i - 1, j - 1], [i, j - 1], [i - 1, j], [i, j]]:
				if q[0] >= 0 and q[1] >= 0 and q[0] < nx - 1 and q[1] < nz - 1 and _hole[q[1] * (nx - 1) + q[0]] == 1:
					locked[j * nx + i] = 1
	for cz in range(0, nz - 1, CHUNK):
		for cx in range(0, nx - 1, CHUNK):
			var body := StaticBody3D.new()
			add_child(body)
			var shape := CollisionShape3D.new()
			shape.shape = ConcavePolygonShape3D.new()
			body.add_child(shape)
			var mi := MeshInstance3D.new()
			mi.material_override = material
			add_child(mi)
			var ch := {"x0": cx, "z0": cz, "x1": mini(cx + CHUNK, nx - 1), "z1": mini(cz + CHUNK, nz - 1), "mesh": mi, "shape": shape, "body": body, "dirty": true}
			_chunks.append(ch)
	_rebuild_dirty(1000)

func _point(i: int, j: int) -> Vector2:
	return rect.position + Vector2(i, j) * RES

func _index(p: Vector2) -> Vector2:
	return (p - rect.position) / RES

func contains(p: Vector3) -> bool:
	return rect.has_point(Vector2(p.x, p.z))

## Ground height under a point (bilinear).
func height_at(p: Vector3) -> float:
	var f := _index(Vector2(p.x, p.z))
	var i := clampi(int(floor(f.x)), 0, nx - 2)
	var j := clampi(int(floor(f.y)), 0, nz - 2)
	var u := clampf(f.x - i, 0.0, 1.0)
	var v := clampf(f.y - j, 0.0, 1.0)
	var a := lerpf(h[j * nx + i], h[j * nx + i + 1], u)
	var b := lerpf(h[(j + 1) * nx + i], h[(j + 1) * nx + i + 1], u)
	return lerpf(a, b, v)

func is_hole(p: Vector3) -> bool:
	var f := _index(Vector2(p.x, p.z))
	var i := int(floor(f.x))
	var j := int(floor(f.y))
	if i < 0 or j < 0 or i >= nx - 1 or j >= nz - 1: return false
	return _hole[j * (nx - 1) + i] == 1

## Cut away ground above `below_y` within `radius` of `center`, at most
## `max_volume` cubic metres. Returns how much came out.
func cut(center: Vector3, below_y: float, radius: float, max_volume: float, flat := false) -> float:
	var floor_y := maxf(below_y, LOWEST)
	var pts := _around(center, radius)
	if flat:
		for q in pts: q[1] = 1.0
	var want := 0.0
	for q in pts:
		var k: int = q[0]
		want += maxf(0.0, h[k] - floor_y) * q[1]
	if want <= 0.0001 or max_volume <= 0.0: return 0.0
	var take := minf(1.0, max_volume / (want * RES * RES))
	var got := 0.0
	for q in pts:
		var k: int = q[0]
		var wt: float = q[1]
		var d := maxf(0.0, h[k] - floor_y) * wt * take
		h[k] -= d
		got += d * RES * RES
	_touch(center, radius)
	return got

## Pile `volume` cubic metres of dirt in a soft mound around `center`.
func add(center: Vector3, volume: float, radius: float, slump := true) -> void:
	var pts := _around(center, radius)
	var total := 0.0
	for q in pts: total += q[1]
	if total <= 0.0: return
	var dh := volume / (total * RES * RES)
	for q in pts:
		var k: int = q[0]
		h[k] = minf(HIGHEST, h[k] + dh * q[1])
	if slump: _relax(center, radius + RES * 2.0)
	_touch(center, radius + RES * 2.0)

## Set everything inside `r` to height `y` (the foundation, the cheat).
func flatten(r: Rect2, y: float) -> void:
	for j in nz:
		for i in nx:
			if locked[j * nx + i] == 1: continue
			if r.has_point(_point(i, j)): h[j * nx + i] = y
	_touch(Vector3(r.get_center().x, 0, r.get_center().y), maxf(r.size.x, r.size.y))

## Mean depth below zero over a rectangle (how dug out it is).
func mean_depth(r: Rect2) -> float:
	var total := 0.0
	var n := 0
	for j in nz:
		for i in nx:
			var p := _point(i, j)
			if p.x > r.position.x + 0.01 and p.y > r.position.y + 0.01 and p.x < r.end.x - 0.01 and p.y < r.end.y - 0.01:
				total += -h[j * nx + i]
				n += 1
	return total / maxf(n, 1)

## Unlocked grid points within `radius`: [index, weight 0..1].
func _around(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var f := _index(Vector2(center.x, center.z))
	var r := radius / RES
	for j in range(maxi(0, int(f.y - r) - 1), mini(nz, int(f.y + r) + 2)):
		for i in range(maxi(0, int(f.x - r) - 1), mini(nx, int(f.x + r) + 2)):
			if locked[j * nx + i] == 1: continue
			var d := Vector2(i - f.x, j - f.y).length() / r
			if d >= 1.0: continue
			out.append([j * nx + i, 1.0 - d * d])
	return out

## Sand doesn't stand in cliffs: let steep steps slump a little.
func _relax(center: Vector3, radius: float) -> void:
	var f := _index(Vector2(center.x, center.z))
	var r := int(radius / RES) + 1
	var max_step := RES * 0.9
	for it in 2:
		for j in range(maxi(1, int(f.y) - r), mini(nz - 1, int(f.y) + r + 1)):
			for i in range(maxi(1, int(f.x) - r), mini(nx - 1, int(f.x) + r + 1)):
				var k := j * nx + i
				if locked[k] == 1: continue
				for o in [k + 1, k - 1, k + nx, k - nx]:
					if locked[o] == 1: continue
					var step := h[k] - h[o]
					if step > max_step:
						var move := (step - max_step) * 0.5
						h[k] -= move
						h[o] += move

func _touch(center: Vector3, radius: float) -> void:
	changed_since += 1
	var f := _index(Vector2(center.x, center.z))
	var r := radius / RES + 1.0
	for ch in _chunks:
		if f.x + r >= ch.x0 and f.x - r <= ch.x1 and f.y + r >= ch.z0 and f.y - r <= ch.z1:
			ch.dirty = true

func _process(_delta: float) -> void:
	_rebuild_dirty(8)

func _rebuild_dirty(limit: int) -> void:
	var n := 0
	for ch in _chunks:
		if not ch.dirty: continue
		_build_chunk(ch)
		n += 1
		if n >= limit: return

func _vertex(i: int, j: int) -> Vector3:
	var p := _point(i, j)
	return Vector3(p.x, h[j * nx + i], p.y)

func _normal(i: int, j: int) -> Vector3:
	var l := h[j * nx + maxi(i - 1, 0)]
	var r := h[j * nx + mini(i + 1, nx - 1)]
	var d := h[maxi(j - 1, 0) * nx + i]
	var u := h[mini(j + 1, nz - 1) * nx + i]
	return Vector3(l - r, 2.0 * RES, d - u).normalized()

func _build_chunk(ch: Dictionary) -> void:
	ch.dirty = false
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var faces := PackedVector3Array()
	var idx := PackedInt32Array()
	var w: int = ch.x1 - ch.x0 + 1
	for j in range(ch.z0, ch.z1 + 1):
		for i in range(ch.x0, ch.x1 + 1):
			verts.append(_vertex(i, j))
			normals.append(_normal(i, j))
	for j in range(ch.z0, ch.z1):
		for i in range(ch.x0, ch.x1):
			if _hole[j * (nx - 1) + i] == 1: continue
			var a: int = (j - ch.z0) * w + (i - ch.x0)
			var b := a + 1
			var c := a + w
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
			faces.append_array([verts[a], verts[b], verts[c], verts[b], verts[d], verts[c]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not idx.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ch.mesh.mesh = mesh
	(ch.shape.shape as ConcavePolygonShape3D).set_faces(faces)
