class_name Worker
extends CharacterBody3D
## A builder on foot. Walks around, climbs into machines, gets bonked by
## machines that drive too fast.

const SPEED := 6.0

var player: Dictionary = {}
var stunned := 0.0
var walked := 0.0   ## Metres on foot, for tests and stats.
var _body: Node3D
var _stars: Node3D
var _walk := 0.0
var _next_step := 0.7
var _name_tag: Label3D

func setup(p: Dictionary) -> void:
	player = p

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 2.6
	cs.shape = cap
	cs.position = Vector3(0, 1.3, 0)
	add_child(cs)
	_body = Node3D.new()
	_body.scale = Vector3.ONE * 1.8
	add_child(_body)
	var c: Color = player.get("color", Toy.ORANGE)
	for x in [-0.17, 0.17]:
		Toy.box(_body, Vector3(0.22, 0.5, 0.26), Vector3(x, 0.25, 0), Color("#3b4a6b"))
	Toy.box(_body, Vector3(0.7, 0.6, 0.45), Vector3(0, 0.78, 0), c)            # vest
	Toy.box(_body, Vector3(0.72, 0.08, 0.47), Vector3(0, 0.72, 0), Color("#e8f05a"))
	Toy.ball(_body, 0.3, Vector3(0, 1.3, 0), Color("#f2c49b"))                 # head
	Toy.ball(_body, 0.36, Vector3(0, 1.42, 0), Toy.YELLOW, 0.6)                 # hard hat
	Toy.box(_body, Vector3(0.5, 0.05, 0.25), Vector3(0, 1.36, -0.32), Toy.YELLOW)
	Toy.box(_body, Vector3(0.08, 0.08, 0.04), Vector3(-0.1, 1.32, -0.29), Toy.DARK)
	Toy.box(_body, Vector3(0.08, 0.08, 0.04), Vector3(0.1, 1.32, -0.29), Toy.DARK)
	_stars = Node3D.new()
	_stars.position = Vector3(0, 3.1, 0)
	_stars.visible = false
	add_child(_stars)
	for k in 3:
		Toy.ball(_stars, 0.1, Vector3(cos(k * TAU / 3) * 0.4, 0, sin(k * TAU / 3) * 0.4), Toy.glow(Toy.YELLOW, 2.0))
	_name_tag = Toy.label(self, str(player.get("name", "")), Vector3(0, 3.4, 0), c, 64)

func set_player_name(n: String) -> void:
	_name_tag.text = n

## Move from a pad dictionary. Screen-up on the stick is world -Z.
func walk(i: Dictionary, delta: float) -> void:
	var move := Vector3(float(i.lx), 0, float(i.ly))
	if move.length() > 1.0: move = move.normalized()
	if stunned > 0.0:
		stunned -= delta
		move = Vector3.ZERO
		_stars.visible = true
		_stars.rotation.y += delta * 6.0
		if stunned <= 0.0:
			_stars.visible = false
			_body.rotation = Vector3.ZERO
	var target := move * SPEED
	velocity.x = move_toward(velocity.x, target.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 40.0 * delta)
	if not is_on_floor(): velocity.y -= 22.0 * delta
	else: velocity.y = maxf(velocity.y, -0.5)
	var before := global_position
	move_and_slide()
	walked += Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if walked > _next_step and is_on_floor():
		# Boot prints, left and right, in the site's sand.
		_next_step = walked + 0.7
		var site: Node = get_parent()
		if site and site.get("ruts"):
			var side := 0.22 if int(walked / 0.7) % 2 == 0 else -0.22
			var v := Vector3(velocity.x, 0, velocity.z).normalized()
			site.ruts.dent(global_position + Vector3(-v.z, 0, v.x) * side, 0.32, 0.4)
	for k in get_slide_collision_count():
		var col := get_slide_collision(k)
		var other := col.get_collider()
		if other is RigidBody3D and not (other is Machine):
			other.apply_central_impulse(-col.get_normal() * 0.6)
	if move.length() > 0.1 and stunned <= 0.0:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-move.x, -move.z), clampf(14.0 * delta, 0, 1))
		_walk += delta * 12.0
		_body.position.y = absf(sin(_walk)) * 0.12
	else:
		_body.position.y = move_toward(_body.position.y, 0.0, delta)
	if global_position.y < -6.0 and player.has("spawn"):
		global_position = player.spawn
		velocity = Vector3.ZERO

func bonk(push: Vector3) -> void:
	if stunned > 0.0: return
	stunned = 1.6
	velocity = Vector3(push.x, 0, push.z).normalized() * 9.0 + Vector3.UP * 7.0
	_body.rotation.x = -1.2
