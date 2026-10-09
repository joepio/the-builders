class_name Toy
extends RefCounted
## Small helpers that build the chunky toy look out of primitive meshes.

const YELLOW := Color("#ffc21a")
const ORANGE := Color("#ff8a1f")
const DARK := Color("#2b2d33")
const STEEL := Color("#8e96a3")
const GLASS := Color("#9fd8ff")
const DIRT := Color("#9a6a3f")
const DIRT_DARK := Color("#6e4a2b")
const CONCRETE := Color("#c9c4b8")
const WOOD := Color("#c99556")

static var _materials := {}

static func mat(color: Color, rough: float = 0.75, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [color.to_html(), rough, metal]
	if _materials.has(key): return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_materials[key] = m
	return m

static func glow(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

static func ghost(color: Color, alpha: float = 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

static func box(parent: Node, size: Vector3, pos: Vector3, color: Variant, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = color if color is Material else mat(color)
	parent.add_child(mi)
	return mi

static func cyl(parent: Node, radius: float, height: float, pos: Vector3, color: Variant, rot := Vector3.ZERO, top := -1.0, sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0.0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = color if color is Material else mat(color)
	parent.add_child(mi)
	return mi

static func ball(parent: Node, radius: float, pos: Vector3, color: Variant, squash := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	mesh.radial_segments = 14
	mesh.rings = 7
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = color if color is Material else mat(color)
	parent.add_child(mi)
	return mi

## A wheel lying on its side along the local X axis.
static func wheel(parent: Node, radius: float, width: float, pos: Vector3) -> Node3D:
	var w := Node3D.new()
	w.position = pos
	parent.add_child(w)
	cyl(w, radius, width, Vector3.ZERO, DARK, Vector3(0, 0, PI / 2), -1.0, 14)
	cyl(w, radius * 0.5, width + 0.04, Vector3.ZERO, STEEL, Vector3(0, 0, PI / 2), -1.0, 10)
	return w

static func shape(body: CollisionObject3D, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	body.add_child(cs)
	return cs

static func label(parent: Node, text: String, pos: Vector3, color := Color.WHITE, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.01
	l.font_size = size
	l.outline_size = 18
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.08, 0.06)
	l.render_priority = 10
	l.outline_render_priority = 9
	var font := load("res://assets/fonts/LilitaOne-Regular.ttf")
	if font: l.font = font
	parent.add_child(l)
	return l

## Black/yellow hazard stripes painted onto a box.
static func stripes(parent: Node, size: Vector3, pos: Vector3, count: int = 6) -> void:
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	box(holder, size, Vector3.ZERO, YELLOW)
	var w := size.x / float(count * 2)
	for i in count:
		box(holder, Vector3(w, size.y + 0.01, size.z + 0.01), Vector3(-size.x / 2.0 + w * (i * 2 + 1.5), 0, 0), DARK, Vector3(0, 0, 0))
