class_name Hud
extends CanvasLayer
## Job card, timer, player strip, banners and the end-of-job card.

const INK := Color("#2b2118")
const PAPER := Color("#fff7e6")

var _font: Font
var _tasks: VBoxContainer
var _timer: Label
var _banner: Label
var _banner_time := 0.0
var _players: HFlowContainer
var _join: Label
var _pause: Control
var _done: Control
var _done_title: Label
var _done_text: Label
var _task_rows: Array = []

func _ready() -> void:
	layer = 5
	_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Job card
	var card := _panel(PAPER)
	card.position = Vector2(24, 22)
	root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var title := _label("JOB: A TINY HOUSE", 30, INK)
	v.add_child(title)
	_tasks = VBoxContainer.new()
	_tasks.add_theme_constant_override("separation", 2)
	v.add_child(_tasks)
	# Timer
	var tp := _panel(INK)
	tp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tp.position = Vector2(-190, 22)
	root.add_child(tp)
	_timer = _label("0:00", 44, Toy.YELLOW)
	_timer.custom_minimum_size = Vector2(130, 0)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tp.add_child(_timer)
	# Banner
	_banner = _label("", 54, Color.WHITE)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-600, 120)
	_banner.size = Vector2(1200, 80)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 16)
	_banner.add_theme_color_override("font_outline_color", INK)
	root.add_child(_banner)
	# Players
	_players = HFlowContainer.new()
	_players.anchor_top = 1.0
	_players.anchor_bottom = 1.0
	_players.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_players.offset_left = 24
	_players.offset_top = -24
	_players.offset_bottom = -24
	_players.add_theme_constant_override("h_separation", 12)
	_players.add_theme_constant_override("v_separation", 10)
	_players.anchor_right = 1.0
	_players.offset_right = -24
	root.add_child(_players)
	_join = _label("Press A / Space / Enter to join", 30, Color.WHITE)
	_join.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_join.position = Vector2(-400, -150)
	_join.size = Vector2(800, 40)
	_join.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join.add_theme_constant_override("outline_size", 12)
	_join.add_theme_color_override("font_outline_color", INK)
	root.add_child(_join)
	_pause = _overlay("PAUSED", "A: resume    Y: restart the job    Esc: quit")
	root.add_child(_pause)
	_done = _overlay("HOUSE BUILT!", "")
	root.add_child(_done)
	_done_title = _done.get_meta("title")
	_done_text = _done.get_meta("text")

func _panel(color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(14)
	sb.border_color = INK
	sb.set_border_width_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_offset = Vector2(4, 5)
	sb.shadow_size = 2
	p.add_theme_stylebox_override("panel", sb)
	return p

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font: l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _overlay(title: String, text: String) -> Control:
	var c := ColorRect.new()
	c.color = Color(0.1, 0.07, 0.04, 0.55)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	var box := _panel(PAPER)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-380, -150)
	box.custom_minimum_size = Vector2(760, 0)
	c.add_child(box)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(v)
	var t := _label(title, 84, Toy.ORANGE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", INK)
	v.add_child(t)
	var s := _label(text, 32, INK)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(s)
	c.set_meta("title", t)
	c.set_meta("text", s)
	return c

func set_tasks(tasks: Array) -> void:
	while _task_rows.size() < tasks.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tick := _label("", 26, INK)
		tick.custom_minimum_size = Vector2(28, 0)
		var name := _label("", 26, INK)
		name.custom_minimum_size = Vector2(290, 0)
		var value := _label("", 26, INK)
		row.add_child(tick)
		row.add_child(name)
		row.add_child(value)
		_tasks.add_child(row)
		_task_rows.append([tick, name, value])
	for k in tasks.size():
		var t: Dictionary = tasks[k]
		var row: Array = _task_rows[k]
		var done: bool = t.done
		row[0].text = "✔" if done else "○"
		row[0].add_theme_color_override("font_color", Color("#2f9e44") if done else INK)
		row[1].text = t.label
		row[1].add_theme_color_override("font_color", Color(INK, 0.45) if done else INK)
		if t.get("auto", false): row[2].text = "" if done else "auto"
		elif t.get("percent", false): row[2].text = "%d%%" % t.value
		else: row[2].text = "%d/%d" % [t.value, t.total]
		row[2].add_theme_color_override("font_color", Color(INK, 0.45) if done else Toy.ORANGE.darkened(0.2))

func set_time(seconds: float) -> void:
	_timer.text = "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func banner(text: String, hold := 2.5) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner_time = hold

func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		if _banner_time < 0.5: _banner.modulate.a = maxf(0.0, _banner_time / 0.5)

func set_players(players: Array) -> void:
	for c in _players.get_children(): c.queue_free()
	for p in players:
		var card := _panel(PAPER)
		card.size_flags_vertical = Control.SIZE_SHRINK_END
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		card.add_child(v)
		# The name carries the player's colour; the ink outline keeps light colours readable.
		var name_label := _label(str(p.name), 28, p.color)
		name_label.add_theme_constant_override("outline_size", 8)
		name_label.add_theme_color_override("font_outline_color", INK)
		v.add_child(name_label)
		var job := "on foot" if p.machine == null else str(p.machine.title)
		v.add_child(_label(job, 20, Color(INK, 0.6)))
		if p.machine != null and p.has("hint_until"):
			var rows := VBoxContainer.new()
			rows.add_theme_constant_override("separation", 3)
			v.add_child(rows)
			for row in p.machine.hint:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 4)
				for key in row[0]: line.add_child(PadIcon.make(key, _font))
				var text := _label(str(row[1]), 18, INK)
				text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				line.add_child(text)
				line.get_child(line.get_child_count() - 1).add_theme_constant_override("margin_left", 4)
				rows.add_child(line)
		_players.add_child(card)

func show_join(value: bool) -> void:
	_join.visible = value

func set_paused(value: bool) -> void:
	_pause.visible = value

func show_done(seconds: float, stars: int, managed: bool) -> void:
	_done.visible = true
	_done_title.text = "HOUSE BUILT!"
	var star_text := ""
	for k in 3: star_text += "★" if k < stars else "☆"
	_done_text.text = "%s\nTime: %d:%02d\n%s" % [star_text, int(seconds) / 60, int(seconds) % 60,
		"Next job coming up..." if managed else "Press A for a new job"]

func hide_done() -> void:
	_done.visible = false
