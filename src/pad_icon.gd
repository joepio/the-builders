class_name PadIcon
extends Control
## A drawn gamepad glyph: face buttons (A B X Y), bumpers (LB RB), triggers
## (LT RT) and sticks (LS RS, with -h / -v for the axis that matters).

const INK := Color("#2b2118")
const FACE := {"A": Color("#3fb950"), "B": Color("#e5534b"), "X": Color("#3b8fe0"), "Y": Color("#f0b62b")}
const SIZE := 28.0

var token := "A"
var _font: Font

static func make(p_token: String, font: Font) -> PadIcon:
	var icon := PadIcon.new()
	icon.token = p_token
	icon._font = font
	var w := SIZE
	if p_token in ["LB", "RB"]: w = SIZE * 1.5
	elif p_token.begins_with("LS") or p_token.begins_with("RS"): w = SIZE * 1.15
	icon.custom_minimum_size = Vector2(w, SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon

func _text(t: String, center: Vector2, fs: int, color := Color.WHITE) -> void:
	if _font == null: return
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, center + Vector2(-tw.x / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

func _rounded(r: Rect2, radius: float, fill: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.border_color = INK
	sb.set_border_width_all(2)
	draw_style_box(sb, r)

func _arrow(at: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([at + dir * 4.0, at - dir * 2.0 + side * 3.5, at - dir * 2.0 - side * 3.5]), INK)

func _draw() -> void:
	var c := size / 2.0
	if FACE.has(token):
		draw_circle(c, SIZE / 2.0 - 1.0, INK)
		draw_circle(c, SIZE / 2.0 - 3.0, FACE[token])
		_text(token, c, 17)
	elif token in ["LB", "RB"]:
		_rounded(Rect2(1, 5, size.x - 2, size.y - 10), 9, Color("#4a4d57"))
		_text(token, c, 14)
	elif token in ["LT", "RT"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#4a4d57")
		sb.corner_radius_top_left = 12
		sb.corner_radius_top_right = 12
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.border_color = INK
		sb.set_border_width_all(2)
		draw_style_box(sb, Rect2(3, 1, size.x - 6, size.y - 2))
		_text(token, c + Vector2(0, 1), 13)
	else:
		# Stick: grey well, dark cap with L or R, arrows for the axis.
		draw_circle(c, SIZE / 2.0 - 1.0, INK)
		draw_circle(c, SIZE / 2.0 - 3.0, Color("#d9d2c3"))
		draw_circle(c, SIZE / 2.0 - 8.0, Color("#4a4d57"))
		_text(token.substr(0, 1), c, 12)
		var r := SIZE / 2.0 - 5.5
		var horizontal := token.ends_with("-h") or not token.ends_with("-v")
		var vertical := token.ends_with("-v") or not token.ends_with("-h")
		if horizontal:
			_arrow(c + Vector2(r, 0), Vector2.RIGHT)
			_arrow(c - Vector2(r, 0), Vector2.LEFT)
		if vertical:
			_arrow(c + Vector2(0, r), Vector2.DOWN)
			_arrow(c - Vector2(0, r), Vector2.UP)
