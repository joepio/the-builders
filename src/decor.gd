class_name Decor
extends RefCounted
## The world around and on the site: textured sand and grass, tufts, trees,
## bushes, rocks, a street with houses, and builder's clutter. Mostly
## MultiMeshes so hundreds of plants stay cheap.

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_lambert;
uniform vec3 base : source_color;
uniform vec3 dark : source_color;
uniform vec3 light : source_color;
uniform vec3 side : source_color;
uniform float scale = 0.12;
uniform float speckle = 0.5;
uniform sampler2D ruts : filter_linear, repeat_disable;
uniform vec4 ruts_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float ruts_on = 0.0;
varying vec3 wpos;
varying vec3 wnormal;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 p = wpos.xz;
	float n = fbm(p * scale);
	vec3 c = mix(dark, base, smoothstep(0.36, 0.62, n));
	c = mix(c, dark * 0.9, smoothstep(0.62, 0.8, fbm(p * scale * 0.5 + 3.0)) * 0.5);
	c = mix(c, light, smoothstep(0.55, 0.85, fbm(p * scale * 2.3 + 7.0)) * 0.7);
	c *= 0.93 + 0.1 * noise(p * 3.1);
	// Soft round specks: small stones and darker grains.
	vec2 cell = floor(p * 4.0);
	vec2 local = fract(p * 4.0) - 0.5;
	float speck = step(0.86, hash(cell)) * (1.0 - smoothstep(0.12, 0.22, length(local)));
	c = mix(c, dark * 0.75, speck * speckle);
	// Tracks pressed into the ground: darker, damp grooves, lit on the far
	// wall from the sun and shaded on the near one.
	vec2 ruv = (p - ruts_rect.xy) / ruts_rect.zw;
	if (ruts_on > 0.5 && ruv.x > 0.0 && ruv.y > 0.0 && ruv.x < 1.0 && ruv.y < 1.0) {
		float r = texture(ruts, ruv).r;
		float rl = texture(ruts, ruv + vec2(-0.57, 0.82) * 0.09 / ruts_rect.zw).r;
		c = mix(c, dark * 0.82, r * 0.6);
		c *= clamp(1.0 + (rl - r) * 1.4, 0.6, 1.35);
	}
	if (wnormal.y < 0.5) c = side * (0.85 + 0.2 * noise(vec2(p.x + p.y, wpos.y) * 2.0));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""

static var _shader: Shader

static func ground_material(base: Color, dark: Color, light: Color, side: Color, scale := 0.12, speckle := 0.5) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("dark", dark)
	m.set_shader_parameter("light", light)
	m.set_shader_parameter("side", side)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("speckle", speckle)
	return m

static func sand() -> ShaderMaterial:
	return ground_material(Color("#dcae6e"), Color("#ad773e"), Color("#ecc995"), Color("#8b5e36"), 0.14, 0.55)

static func grass() -> ShaderMaterial:
	return ground_material(Color("#62a842"), Color("#3f8530"), Color("#8cc257"), Color("#6a4a2e"), 0.1, 0.35)

## A tuft of five blades with darker roots, as one small mesh.
static func tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := k * TAU / 6.0 + 0.4 * sin(k * 3.0)
		var lean := Vector3(cos(a), 0, sin(a)) * 0.22
		var side := Vector3(-sin(a), 0, cos(a)) * 0.07
		var h := 0.45 + 0.2 * fmod(k * 0.37, 1.0)
		st.set_color(Color("#3f7f2b"))
		st.set_normal(Vector3.UP)
		st.add_vertex(-side)
		st.add_vertex(side)
		st.set_color(Color("#9bd25e"))
		st.add_vertex(lean + Vector3(0, h, 0))
	return st.commit()

static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array, colors: Array, material: Material, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		if mm.use_colors: mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

static func _vertex_color_mat(rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Scatter tufts. `ok` filters positions (Vector2 xz -> bool).
static func tufts(parent: Node3D, rng: RandomNumberGenerator, area: Rect2, count: int, ok: Callable, size := 1.0) -> void:
	var xs: Array = []
	var tries := 0
	while xs.size() < count and tries < count * 6:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if not ok.call(p): continue
		var s := rng.randf_range(0.7, 1.5) * size
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(p.x, 0.0, p.y)))
	var m := _vertex_color_mat()
	_multimesh(parent, tuft_mesh(), xs, [], m, false)

## Round trees (trunk + three canopy blobs), bushes and rocks outside the fence.
static func greenery(parent: Node3D, rng: RandomNumberGenerator, world: Rect2, keep_out: Array) -> void:
	var trunks: Array = []
	var blobs: Array = []
	var blob_colors: Array = []
	var bushes: Array = []
	var bush_colors: Array = []
	var rocks: Array = []
	var greens := [Color("#24622a"), Color("#2e7030"), Color("#3a7d34"), Color("#1f5a26"), Color("#468a39")]
	var placed: Array = []
	var tries := 0
	while trunks.size() < 170 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(world.position.x, world.end.x), rng.randf_range(world.position.y, world.end.y))
		var blocked := false
		for r in keep_out: if r.has_point(p): blocked = true
		for q in placed: if q.distance_to(p) < 3.2: blocked = true
		if blocked: continue
		placed.append(p)
		var s := rng.randf_range(0.9, 1.6)
		trunks.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(p.x, 1.0 * s, p.y)))
		var g: Color = greens[rng.randi() % greens.size()]
		for k in 3:
			var off := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(2.4, 3.4), rng.randf_range(-0.9, 0.9)) * s
			var bs := s * rng.randf_range(1.1, 1.6)
			blobs.append(Transform3D(Basis().scaled(Vector3(bs, bs * 0.9, bs)), Vector3(p.x, 0, p.y) + off))
			blob_colors.append(g.lightened(0.06) if k == 2 else g)
	for k in 140:
		var p := Vector2(rng.randf_range(world.position.x, world.end.x), rng.randf_range(world.position.y, world.end.y))
		var blocked := false
		for r in keep_out: if r.has_point(p): blocked = true
		if blocked: continue
		var s := rng.randf_range(0.6, 1.3)
		bushes.append(Transform3D(Basis().scaled(Vector3(s * 1.3, s * 0.8, s)), Vector3(p.x, 0.3 * s, p.y)))
		bush_colors.append((greens[rng.randi() % greens.size()] as Color).darkened(0.1))
	for k in 45:
		var p := Vector2(rng.randf_range(world.position.x, world.end.x), rng.randf_range(world.position.y, world.end.y))
		var blocked := false
		for r in keep_out: if r.has_point(p): blocked = true
		if blocked: continue
		var s := rng.randf_range(0.5, 1.6)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)).scaled(Vector3(s * 1.4, s * 0.8, s)), Vector3(p.x, 0.15 * s, p.y)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 2.0
	trunk.radial_segments = 7
	_multimesh(parent, trunk, trunks, [], Toy.mat(Color("#7a5236")))
	var blob := SphereMesh.new()
	blob.radius = 1.0
	blob.height = 2.0
	blob.radial_segments = 10
	blob.rings = 6
	# Instance colours don't reach meshes without a colour array in the
	# compatibility renderer, so each shade of green gets its own MultiMesh.
	_by_color(parent, blob, blobs, blob_colors)
	_by_color(parent, blob, bushes, bush_colors)
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.6
	rock.radial_segments = 6
	rock.rings = 3
	_multimesh(parent, rock, rocks, [], Toy.mat(Color("#9a9a94"), 0.95))

static func _by_color(parent: Node3D, mesh: Mesh, xforms: Array, colors: Array) -> void:
	var groups := {}
	for k in xforms.size():
		var key: String = (colors[k] as Color).to_html(false)
		if not groups.has(key): groups[key] = []
		groups[key].append(xforms[k])
	for key in groups: _multimesh(parent, mesh, groups[key], [], Toy.mat(Color(key), 0.9))

## A street along the top edge with a pavement, and a few houses beside the site.
static func street(parent: Node3D, site: Rect2) -> Array:
	var z := site.position.y - 6.5
	Toy.box(parent, Vector3(140, 0.06, 6.0), Vector3(0, 0.03, z), Color("#5d6168"))
	Toy.box(parent, Vector3(140, 0.12, 1.8), Vector3(0, 0.06, z + 3.9), Color("#c9c6bd"))
	Toy.box(parent, Vector3(140, 0.12, 1.8), Vector3(0, 0.06, z - 3.9), Color("#c9c6bd"))
	for k in 18:
		Toy.box(parent, Vector3(2.6, 0.08, 0.22), Vector3(-66 + k * 8, 0.05, z), Color("#f2efe6"))
	var houses := [[Vector3(-33, 0, -3), Color("#e9d8b8"), 0.0], [Vector3(-33, 0, 7), Color("#c6dbe8"), 0.0],
		[Vector3(34, 0, -6), Color("#f0c9b0"), PI], [Vector3(34, 0, 5), Color("#d8e6c4"), PI]]
	var body := StaticBody3D.new()
	parent.add_child(body)
	for h in houses:
		var holder := Node3D.new()
		holder.position = h[0]
		holder.rotation.y = h[2]
		parent.add_child(holder)
		Toy.box(holder, Vector3(6.5, 3.6, 6.0), Vector3(0, 1.8, 0), h[1])
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(7.2, 2.4, 6.6)
		roof.mesh = pm
		roof.position = Vector3(0, 4.8, 0)
		roof.material_override = Toy.mat(Color("#b9533f"))
		holder.add_child(roof)
		for wz in [-1.5, 1.5]:
			Toy.box(holder, Vector3(0.08, 1.0, 1.1), Vector3(3.27, 2.0, wz), Toy.GLASS)
		Toy.box(holder, Vector3(0.08, 1.8, 0.9), Vector3(3.27, 0.9, 0), Color("#7a4e33"))
		Toy.box(holder, Vector3(0.6, 1.2, 0.6), Vector3(-1.6, 5.4, 1.2), Color("#9c5a45"))
		Toy.shape(body, Vector3(6.5, 3.6, 6.0), (h[0] as Vector3) + Vector3(0, 1.8, 0))
	var out: Array = [Rect2(-70, z - 5, 140, 10)]
	for h in houses: out.append(Rect2((h[0] as Vector3).x - 4.5, (h[0] as Vector3).z - 4.5, 9, 9))
	return out

## Builder's clutter inside the fence: dirt mounds, brick pallets, block stacks, a container.
static func site_props(parent: Node3D, body: StaticBody3D) -> void:
	for m in [[Vector3(-18.0, 0, -8.5), 2.8], [Vector3(-20.0, 0, -12.6), 1.8]]:
		var mound := Toy.cyl(parent, m[1], m[1] * 0.75, (m[0] as Vector3) + Vector3(0, m[1] * 0.375, 0), Toy.DIRT, Vector3.ZERO, m[1] * 0.25, 12)
		mound.material_override = ground_material(Color("#a8723f"), Color("#8a5a31"), Color("#c08a50"), Color("#8a5a31"), 0.6, 0.6)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = m[1] * 0.8
		cyl.height = m[1] * 0.6
		cs.shape = cyl
		cs.position = (m[0] as Vector3) + Vector3(0, m[1] * 0.3, 0)
		body.add_child(cs)
	# Pallets of bricks and stacks of blocks by the deliveries.
	for p in [Vector3(21.0, 0, -1.5), Vector3(21.0, 0, 1.4)]:
		Toy.box(parent, Vector3(1.6, 0.18, 1.6), p + Vector3(0, 0.09, 0), Toy.WOOD)
		for k in 3:
			Toy.box(parent, Vector3(1.4, 0.32, 1.4), p + Vector3(0, 0.34 + k * 0.34, 0), Color("#c4673f").darkened(0.06 * k))
		Toy.shape(body, Vector3(1.6, 1.2, 1.6), p + Vector3(0, 0.6, 0))
	for p in [Vector3(18.0, 0, -2.0)]:
		for k in 3:
			for j in 2:
				Toy.box(parent, Vector3(0.9, 0.45, 0.45), p + Vector3(0, 0.23 + k * 0.46, j * 0.47), Color("#b8b5ad"))
		Toy.shape(body, Vector3(0.9, 1.4, 0.95), p + Vector3(0, 0.7, 0.23))
	# A red site container along the left fence.
	var c := Vector3(-22.3, 0, -3.0)
	Toy.box(parent, Vector3(2.4, 2.5, 6.0), c + Vector3(0, 1.25, 0), Color("#c0392b"))
	for k in 9:
		Toy.box(parent, Vector3(2.44, 2.3, 0.08), c + Vector3(0, 1.25, -2.6 + k * 0.65), Color("#a83224"))
	Toy.shape(body, Vector3(2.4, 2.5, 6.0), c + Vector3(0, 1.25, 0))
	# Barrels and a wheelbarrow.
	for p in [Vector3(14.5, 0, -12.8), Vector3(15.4, 0, -13.1)]:
		Toy.cyl(parent, 0.42, 1.0, p + Vector3(0, 0.5, 0), Color("#2f7fb5"))
		Toy.shape(body, Vector3(0.84, 1.0, 0.84), p + Vector3(0, 0.5, 0))
