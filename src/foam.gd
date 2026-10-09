class_name Foam
extends RefCounted
## PUR foam blobs: they puff up when sprayed and keep growing a little,
## so a keen builder leaves a house wrapped in yellow cauliflower.

const COLOR := Color("#f3df8a")
const MAX_BLOBS := 600

static var _mesh: SphereMesh
static var _mat: StandardMaterial3D

static func blob(parent: Node, at: Vector3, size: float) -> void:
	if parent.get_tree().get_node_count_in_group("foam") > MAX_BLOBS: return
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 0.5
		_mesh.height = 0.85
		_mesh.radial_segments = 8
		_mesh.rings = 4
		_mat = Toy.mat(COLOR, 0.95)
	var m := MeshInstance3D.new()
	m.mesh = _mesh
	m.material_override = _mat
	m.add_to_group("foam")
	parent.add_child(m)
	m.global_position = at + Vector3(randf_range(-0.12, 0.12), randf_range(-0.08, 0.08), randf_range(-0.12, 0.12))
	m.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	m.scale = Vector3.ONE * size * 0.3
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * size, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3.ONE * size * 1.35, 4.0).set_trans(Tween.TRANS_SINE)
