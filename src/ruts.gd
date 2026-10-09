class_name Ruts
extends Node
## Tracks, tyre marks and footprints pressed into the sand. A small greyscale
## image over the site (how deep the sand is pressed, per pixel) that the
## ground shader reads to darken and shade the grooves.

const PX := 16.0  ## Pixels per metre.

var rect: Rect2
var image: Image
var texture: ImageTexture
var _last := {}   ## key -> [last ground point, distance travelled]
var _dirty := false

func setup(area: Rect2) -> void:
	rect = area
	image = Image.create(int(area.size.x * PX), int(area.size.y * PX), false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)

## Hook this up to a ground material made with Decor.ground_material().
func apply(m: ShaderMaterial) -> void:
	m.set_shader_parameter("ruts", texture)
	m.set_shader_parameter("ruts_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	m.set_shader_parameter("ruts_on", 1.0)
	m.set_shader_parameter("dig_tint", 1.0)

## Follow one contact point (a track end, a wheel) as it moves. `tread`
## gives the mark cross bars like a crawler track.
func follow(key: int, ground: Vector3, width: float, depth: float, tread := false) -> void:
	var p := Vector2(ground.x, ground.z)
	if absf(ground.y) > 0.35 or not rect.has_point(p):
		_last.erase(key)
		return
	if not _last.has(key):
		_last[key] = [p, 0.0]
		return
	var prev: Vector2 = _last[key][0]
	var along: float = _last[key][1]
	var d := prev.distance_to(p)
	if d < 0.12: return
	if d < 2.0: press(prev, p, width, depth, along if tread else -1.0)
	_last[key] = [p, along + d]

## Press a straight strip from a to b. `along` >= 0 adds tread bars.
func press(a: Vector2, b: Vector2, width: float, depth: float, along := -1.0) -> void:
	var seg := b - a
	var length := seg.length()
	if length < 0.001: return
	var dir := seg / length
	var half := width * 0.5
	var lo := (Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * half - rect.position) * PX
	var hi := (Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * half - rect.position) * PX
	var w := image.get_width()
	var h := image.get_height()
	for y in range(maxi(0, int(lo.y)), mini(h, int(hi.y) + 1)):
		for x in range(maxi(0, int(lo.x)), mini(w, int(hi.x) + 1)):
			var q := rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) / PX - a
			var t := q.dot(dir)
			if t < 0.0 or t >= length: continue
			var side := absf(q.x * dir.y - q.y * dir.x)
			if side > half: continue
			var v := depth * (1.0 - smoothstep(half * 0.55, half, side))
			if along >= 0.0:
				v *= 0.55 + 0.45 * float(fmod(along + t, 0.4) < 0.22)
			if v > image.get_pixel(x, y).r:
				image.set_pixel(x, y, Color(v, v, v))
	_dirty = true

## A single footprint-sized dent.
func dent(at: Vector3, size: float, depth: float) -> void:
	var p := Vector2(at.x, at.z)
	if not rect.has_point(p): return
	press(p - Vector2(0, size * 0.5), p + Vector2(0, size * 0.5), size * 0.7, depth)

func _process(_delta: float) -> void:
	if _dirty:
		texture.update(image)
		_dirty = false
