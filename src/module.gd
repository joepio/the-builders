class_name Module
extends RigidBody3D
## A prefab house module (or the roof) on a pallet. Forklifts slide their
## forks between the runners; the crane hooks the ring on top. Dropped close
## enough to a free slot, it locks into the house.

const WALLS := [Color("#3fb8a6"), Color("#ff8d5c"), Color("#5f95f0"), Color("#f2b632"), Color("#a46be8"), Color("#62c255")]
const SIZE := Vector3(2.4, 2.1, 2.4)
const PALLET := 0.3

var kind := "module"          ## "module" or "roof"
var lift_offset := Vector3(0, PALLET + SIZE.y + 0.35, 0)
var placed := false
var color := Color.WHITE
var _pallet: Array[Node] = []
var _crane: Node = null

func setup(p_kind: String, index: int) -> void:
	kind = p_kind
	color = WALLS[index % WALLS.size()]

func _ready() -> void:
	add_to_group("liftable")
	add_to_group("module")
	mass = 4.0 if kind == "module" else 5.0
	can_sleep = true
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.9
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 1.0, 0)
	# Pallet runners
	for x in [-1.05, 0.0, 1.05]:
		if x == 0.0: continue
		_pallet.append(Toy.box(self, Vector3(0.3, PALLET, 2.4), Vector3(x, PALLET / 2.0, 0), Toy.WOOD))
		_pallet.append(Toy.shape(self, Vector3(0.3, PALLET, 2.4), Vector3(x, PALLET / 2.0, 0)))
	_pallet.append(Toy.box(self, Vector3(2.4, 0.06, 2.4), Vector3(0, PALLET - 0.03, 0), Toy.WOOD))
	if kind == "roof": _build_roof()
	else: _build_module()
	# Lifting ring on top.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.18
	tm.outer_radius = 0.3
	ring.mesh = tm
	ring.rotation = Vector3(PI / 2, 0, 0)
	ring.position = lift_offset - Vector3(0, 0.05, 0)
	ring.material_override = Toy.mat(Toy.ORANGE)
	add_child(ring)

func _build_module() -> void:
	var y0 := PALLET
	Toy.box(self, SIZE, Vector3(0, y0 + SIZE.y / 2.0, 0), color)
	Toy.box(self, Vector3(SIZE.x + 0.08, 0.14, SIZE.z + 0.08), Vector3(0, y0 + SIZE.y - 0.07, 0), Color.WHITE)
	Toy.box(self, Vector3(SIZE.x + 0.06, 0.1, SIZE.z + 0.06), Vector3(0, y0 + 0.05, 0), Color("#5d5550"))
	# Windows on every side, a door on one.
	for side in 4:
		var holder := Node3D.new()
		holder.rotation.y = side * PI / 2.0
		holder.position = Vector3(0, y0, 0)
		add_child(holder)
		var z := SIZE.z / 2.0 + 0.02
		if side == 0 and color.h > 0.4:
			Toy.box(holder, Vector3(0.7, 1.4, 0.06), Vector3(-0.5, 0.72, z), Color("#8a5a3a"))
			Toy.box(holder, Vector3(0.12, 0.12, 0.08), Vector3(-0.3, 0.75, z + 0.02), Toy.YELLOW)
			Toy.box(holder, Vector3(0.6, 0.6, 0.06), Vector3(0.55, 1.2, z), Color.WHITE)
			Toy.box(holder, Vector3(0.48, 0.48, 0.08), Vector3(0.55, 1.2, z), Toy.GLASS)
		else:
			Toy.box(holder, Vector3(1.4, 0.8, 0.06), Vector3(0, 1.15, z), Color.WHITE)
			Toy.box(holder, Vector3(1.26, 0.66, 0.08), Vector3(0, 1.15, z), Toy.GLASS)
			Toy.box(holder, Vector3(0.06, 0.66, 0.1), Vector3(0, 1.15, z), Color.WHITE)
			Toy.box(holder, Vector3(1.5, 0.08, 0.16), Vector3(0, 0.72, z + 0.04), Color.WHITE)
	Toy.shape(self, SIZE, Vector3(0, y0 + SIZE.y / 2.0, 0))

func _build_roof() -> void:
	var y0 := PALLET
	lift_offset = Vector3(0, y0 + 1.9, 0)
	var red := Color("#e0503a")
	Toy.box(self, Vector3(5.0, 0.2, 2.5), Vector3(0, y0 + 0.1, 0), Color("#f4ead8"))
	for s in [-1.0, 1.0]:
		Toy.box(self, Vector3(5.2, 0.18, 1.75), Vector3(0, y0 + 0.75, s * 0.62), red, Vector3(s * 0.78, 0, 0))
	Toy.box(self, Vector3(5.25, 0.16, 0.2), Vector3(0, y0 + 1.42, 0), Color("#b23a2b"))
	Toy.box(self, Vector3(0.45, 0.8, 0.45), Vector3(1.5, y0 + 1.4, 0.4), Color("#a65a44"))
	for s in [-1.0, 1.0]:
		var gable := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(2.4, 1.3, 0.1)
		gable.mesh = pm
		gable.position = Vector3(s * 2.45, y0 + 0.85, 0)
		gable.rotation.y = PI / 2
		gable.material_override = Toy.mat(Color("#f4ead8"))
		add_child(gable)
	Toy.shape(self, Vector3(5.0, 1.2, 2.4), Vector3(0, y0 + 0.6, 0))
	Toy.shape(self, Vector3(3.0, 0.6, 1.2), Vector3(0, y0 + 1.4, 0))

func on_hooked(crane: Node) -> void:
	_crane = crane

func on_released() -> void:
	_crane = null

func is_hooked() -> bool:
	return _crane != null and is_instance_valid(_crane)

## Lock into the house at `xf` (slot transform; origin = module floor).
func place(xf: Transform3D) -> void:
	placed = true
	remove_from_group("liftable")
	if is_hooked(): _crane.release()
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	for n in _pallet:
		if n is CollisionShape3D: n.disabled = true
		else: n.visible = false
	var target := xf.translated(Vector3(0, -PALLET, 0))
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_transform", target, 0.35)
	var pop := create_tween()
	for child in get_children():
		if child is MeshInstance3D:
			pop.parallel().tween_property(child, "scale", child.scale * 1.06, 0.12)
	pop.tween_interval(0.0)
	for child in get_children():
		if child is MeshInstance3D:
			pop.parallel().tween_property(child, "scale", child.scale, 0.2)
