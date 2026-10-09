class_name Machine
extends RigidBody3D
## Base for every drivable machine: a heavy toy on rigid-body physics with
## arcade drive helpers. Subclasses build their look in `_build()` and read
## the driver's pad in `control()`.

signal bonked(worker: Node)

const MAX_SPEED := 11.0   ## m/s across the ground
const MAX_RISE := 3.5     ## m/s upwards
const MAX_SPIN := 3.0     ## rad/s

var title := "Machine"
## Controls cheat sheet shown when someone climbs in: [[pad glyphs], action].
var hint: Array = []
var driver: Dictionary = {}       ## The player driving, or empty.
var home := Transform3D.IDENTITY  ## Where it respawns when it falls off the world.
var easy := false                 ## Friendlier controls (settings: controls = easy).
var site: Node = null
var exit_offset := Vector3(2.2, 0, 0)
## Ground contact points that leave marks in the sand: [local point, width, tread].
var marks: Array = []
var _flag: MeshInstance3D
var _name_tag: Label3D
var _neutral := {"lx": 0.0, "ly": 0.0, "rx": 0.0, "ry": 0.0, "lt": 0.0, "rt": 0.0,
	"a": false, "b": false, "x": false, "y": false, "lb": false, "rb": false, "start": false,
	"a_pressed": false, "b_pressed": false, "x_pressed": false, "y_pressed": false,
	"lb_pressed": false, "rb_pressed": false, "start_pressed": false}

func _ready() -> void:
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.05
	_build()
	_name_tag = Toy.label(self, "", Vector3(0, tag_height(), 0), Color.WHITE, 72)
	_name_tag.visible = false
	home = global_transform

## Override: build meshes and collision shapes.
func _build() -> void:
	pass

## Override: per-step control. `i` is a pad dictionary (see Controls).
func control(_i: Dictionary, _delta: float) -> void:
	pass

func tag_height() -> float:
	return 4.0

## A coloured panel (roof, seat) that shows who is driving.
func set_flag(mesh: MeshInstance3D) -> void:
	_flag = mesh

func enter(p: Dictionary) -> void:
	driver = p
	_name_tag.text = str(p.name)
	_name_tag.modulate = p.color
	_name_tag.visible = true
	if _flag: _flag.material_override = Toy.mat(p.color, 0.5)

func leave() -> void:
	driver = {}
	_name_tag.visible = false
	if _flag: _flag.material_override = Toy.mat(Toy.DARK, 0.6)

func exit_point() -> Vector3:
	return global_transform * exit_offset

func _physics_process(delta: float) -> void:
	var i: Dictionary = _neutral
	if not driver.is_empty() and driver.controls: i = driver.controls.state
	if i.is_empty(): i = _neutral
	control(i, delta)
	if global_position.y < -6.0: respawn()

## Moving parts (buckets, blades, forks) are kinematic and push with endless
## force, so a machine caught by one could be launched. Nothing on site
## legitimately goes this fast, so clamp it.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var v := state.linear_velocity
	var flat := Vector2(v.x, v.z)
	if flat.length() > MAX_SPEED or v.y > MAX_RISE:
		if flat.length() > MAX_SPEED: flat = flat.normalized() * MAX_SPEED
		state.linear_velocity = Vector3(flat.x, minf(v.y, MAX_RISE), flat.y)
	if state.angular_velocity.length() > MAX_SPIN:
		state.angular_velocity = state.angular_velocity.normalized() * MAX_SPIN

func respawn() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = home.translated(Vector3.UP * 0.5)
	reset_physics_interpolation()

## Arcade ground drive: chase a forward speed and a yaw rate, kill sideways
## slip. `grip` 0..1 lets a machine slide a bit.
func drive(target_speed: float, target_yaw: float, delta: float, accel := 6.0, grip := 0.9, turn_accel := 6.0, side_target := 0.0) -> void:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var v := linear_velocity
	var v_fwd := v.dot(fwd)
	var v_side := v.dot(right)
	# Ground friction is kept tiny on machines; this is the grip model.
	var dv := clampf(target_speed - v_fwd, -accel * delta, accel * delta)
	var impulse := fwd * dv * mass - right * (v_side - side_target) * grip * mass * 0.5
	apply_central_impulse(impulse)
	var av := angular_velocity
	av.y = lerpf(av.y, target_yaw, clampf(turn_accel * delta, 0.0, 1.0))
	angular_velocity = av

## Shared track controls for every tracked machine: each trigger drives its
## track forward, the bumper above it drives that track back.
const TRACK_HINT := [[["LT", "LB"], "left track"], [["RT", "RB"], "right track"]]

func tracks(i: Dictionary) -> Vector2:
	return Vector2(float(i.lt) - (1.0 if i.lb else 0.0), float(i.rt) - (1.0 if i.rb else 0.0))

func speed() -> float:
	return Vector3(linear_velocity.x, 0, linear_velocity.z).length()

func _on_body_entered(body: Node) -> void:
	if body is Worker and speed() > 2.2:
		body.bonk(linear_velocity)
		bonked.emit(body)
