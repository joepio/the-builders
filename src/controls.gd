class_name Controls
extends RefCounted
## One player's controller: a GameNight seat, a local pad or a keyboard half.
## `read()` returns the same gamepad-shaped dictionary for all three, plus
## press edges for the face buttons.

enum Source { SEAT, PAD, KEYS }

const DEADZONE := 0.18
## Keyboard players get a pad-like layout: WASD is the left stick, IJKL the
## right stick (or arrows + numpad for the second player).
const KEYSETS := [
	{"lx-": KEY_A, "lx+": KEY_D, "ly-": KEY_W, "ly+": KEY_S, "rx-": KEY_J, "rx+": KEY_L, "ry-": KEY_I, "ry+": KEY_K,
		"lt": KEY_Q, "rt": KEY_E, "a": KEY_SPACE, "b": KEY_SHIFT, "x": KEY_F, "y": KEY_R, "lb": KEY_Z, "rb": KEY_X, "start": KEY_TAB},
	{"lx-": KEY_LEFT, "lx+": KEY_RIGHT, "ly-": KEY_UP, "ly+": KEY_DOWN, "rx-": KEY_KP_4, "rx+": KEY_KP_6, "ry-": KEY_KP_8, "ry+": KEY_KP_5,
		"lt": KEY_KP_7, "rt": KEY_KP_9, "a": KEY_ENTER, "b": KEY_KP_0, "x": KEY_KP_1, "y": KEY_KP_2, "lb": KEY_KP_3, "rb": KEY_KP_PERIOD, "start": KEY_BACKSPACE},
]
const BUTTONS := ["a", "b", "x", "y", "lb", "rb", "start"]

var source := Source.KEYS
var id := 0
## Set by tests and the demo: when not empty, read() returns this instead.
var scripted := {}
var _held := {}
var state := {}

func _init(p_source: Source, p_id: int) -> void:
	source = p_source
	id = p_id

static func _dz(v: float) -> float:
	if absf(v) < DEADZONE: return 0.0
	return signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)

func _raw() -> Dictionary:
	if not scripted.is_empty():
		var s := scripted.duplicate()
		for k in ["lx", "ly", "rx", "ry", "lt", "rt"]: if not s.has(k): s[k] = 0.0
		for k in BUTTONS: if not s.has(k): s[k] = false
		return s
	match source:
		Source.SEAT:
			# Looked up at runtime so headless test scripts compile without autoloads.
			var gn: Node = Engine.get_main_loop().root.get_node_or_null("GameNight")
			if gn == null: return {}
			var f: Dictionary = gn.frame_for_seat(id)
			var lx: float = gn.axis(f, 0)
			var ly: float = gn.axis(f, 1)
			if gn.button(f, 14): lx = -1.0
			if gn.button(f, 15): lx = 1.0
			if gn.button(f, 12): ly = -1.0
			if gn.button(f, 13): ly = 1.0
			return {"lx": lx, "ly": ly, "rx": gn.axis(f, 2), "ry": gn.axis(f, 3),
				"lt": maxf(0.0, gn.axis(f, 4)), "rt": maxf(0.0, gn.axis(f, 5)),
				"a": gn.button(f, 0), "b": gn.button(f, 1), "x": gn.button(f, 2), "y": gn.button(f, 3),
				"lb": gn.button(f, 4), "rb": gn.button(f, 5), "start": gn.button(f, 7)}
		Source.PAD:
			var lx := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
			var ly := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT): lx = -1.0
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT): lx = 1.0
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP): ly = -1.0
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN): ly = 1.0
			return {"lx": lx, "ly": ly, "rx": Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), "ry": Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y),
				"lt": Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT), "rt": Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT),
				"a": Input.is_joy_button_pressed(id, JOY_BUTTON_A), "b": Input.is_joy_button_pressed(id, JOY_BUTTON_B),
				"x": Input.is_joy_button_pressed(id, JOY_BUTTON_X), "y": Input.is_joy_button_pressed(id, JOY_BUTTON_Y),
				"lb": Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER), "rb": Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER),
				"start": Input.is_joy_button_pressed(id, JOY_BUTTON_START)}
		_:
			var k: Dictionary = KEYSETS[id]
			var r := {}
			for axis in ["lx", "ly", "rx", "ry"]:
				r[axis] = float(Input.is_physical_key_pressed(k[axis + "+"])) - float(Input.is_physical_key_pressed(k[axis + "-"]))
			r["lt"] = float(Input.is_physical_key_pressed(k.lt))
			r["rt"] = float(Input.is_physical_key_pressed(k.rt))
			for b in BUTTONS: r[b] = Input.is_physical_key_pressed(k[b])
			if id == 1: r["a"] = r["a"] or Input.is_physical_key_pressed(KEY_KP_ENTER)
			return r

## Call once per physics step. Adds `<button>_pressed` edges.
func read() -> Dictionary:
	var r := _raw()
	if r.is_empty(): r = {"lx": 0.0, "ly": 0.0, "rx": 0.0, "ry": 0.0, "lt": 0.0, "rt": 0.0, "a": false, "b": false, "x": false, "y": false, "lb": false, "rb": false, "start": false}
	for axis in ["lx", "ly", "rx", "ry"]: r[axis] = _dz(float(r[axis]))
	for t in ["lt", "rt"]: r[t] = clampf(float(r[t]), 0.0, 1.0) if float(r[t]) > 0.08 else 0.0
	for b in BUTTONS:
		var was: bool = _held.get(b, true)
		r[b + "_pressed"] = bool(r[b]) and not was
		_held[b] = bool(r[b])
	state = r
	return r

func label() -> String:
	match source:
		Source.PAD: return "Pad %d" % (id + 1)
		Source.KEYS: return "WASD keys" if id == 0 else "Arrow keys"
	return "Seat %d" % (id + 1)
