class_name FoamGun
extends Tool
## A can of PUR foam on a gun. Hold RT to spray: the nearest open seam in
## front of you fills up, and foam goes everywhere, because that's how PUR
## works. With nothing to fill, it just makes a mess.

const RANGE := 2.2
const RATE := 0.7   ## Seam units per second.

var site: Node
var spraying := false
var _puff_timer := 0.0
var _rest := Transform3D.IDENTITY
var _spray: CPUParticles3D

func _ready() -> void:
	title = "PUR foam gun"
	hint = [[["RT"], "spray foam"], [["Y"], "tap: put down"]]
	top_level = true
	_rest = global_transform
	# Can, gun, nozzle.
	Toy.cyl(self, 0.16, 0.6, Vector3(0, 0.42, 0.05), Color("#f2c230"), Vector3.ZERO)
	Toy.cyl(self, 0.17, 0.08, Vector3(0, 0.74, 0.05), Toy.DARK)
	Toy.box(self, Vector3(0.12, 0.12, 0.5), Vector3(0, 0.8, -0.2), Color("#2a8ad6"))
	Toy.box(self, Vector3(0.1, 0.3, 0.12), Vector3(0, 0.62, 0.0), Color("#2a8ad6"))
	Toy.cyl(self, 0.03, 0.4, Vector3(0, 0.8, -0.6), Toy.DARK, Vector3(PI / 2, 0, 0))
	_spray = CPUParticles3D.new()
	_spray.emitting = false
	_spray.amount = 40
	_spray.lifetime = 0.45
	_spray.local_coords = false
	_spray.direction = Vector3(0, 0, -1)
	_spray.spread = 14.0
	_spray.initial_velocity_min = 3.5
	_spray.initial_velocity_max = 5.0
	_spray.gravity = Vector3(0, -6, 0)
	var blob := SphereMesh.new()
	blob.radius = 0.09
	blob.height = 0.16
	blob.radial_segments = 6
	blob.rings = 3
	blob.material = Toy.mat(Foam.COLOR, 0.9)
	_spray.mesh = blob
	_spray.position = Vector3(0, 0.8, -0.8)
	add_child(_spray)

func use(active: bool, delta: float) -> void:
	spraying = active
	if not active or site == null: return
	var from := global_transform * Vector3(0, 0.8, -0.8)
	var fwd := holder.facing()
	var seam: Dictionary = site.seam_ahead(from, fwd, RANGE)
	_puff_timer -= delta
	if not seam.is_empty():
		site.foam_seam(seam, RATE * delta)
		if _puff_timer <= 0.0:
			_puff_timer = 0.12
			Foam.blob(site, site.seam_spot(seam), 0.45 + randf() * 0.35)
	elif _puff_timer <= 0.0:
		_puff_timer = 0.2
		var land := from + fwd * 1.4
		land.y = site.ground_at(land) + 0.05
		Foam.blob(site, land, 0.35 + randf() * 0.25)

func drop() -> void:
	var w := holder
	super.drop()
	spraying = false
	if w:
		var at := w.global_position + w.facing() * 0.8
		global_transform = Transform3D(Basis(Vector3.UP, w._body.rotation.y), Vector3(at.x, 0.0, at.z))

func _physics_process(_delta: float) -> void:
	_spray.emitting = spraying
	if holder:
		var hand := holder.hand()
		global_transform = Transform3D(Basis(Vector3.UP, holder._body.rotation.y), hand - Vector3(0, 0.75, 0))
