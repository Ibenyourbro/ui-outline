@tool
extends EditorPlugin

# ================ Settings ================
enum LabelMode { ALL, LEAVES, SELECTED }

var _enabled: bool = true
var _show_labels: bool = true
var _labels_mode: LabelMode = LabelMode.SELECTED   # default to Selected
var _min_zoom_for_labels := 0.2   # 0 = always draw when Names is on

var _outline_color := Color(1, 0, 0, 0.9)                 # non-selected outline (red)
var _outline_color_selected := Color(0.1, 0.9, 1.0, 1.0)  # selected outline (cyan)
var _outline_width := 2.0
var _outline_width_selected := 3.0

var _label_text := Color(1, 1, 1, 1)
var _label_bg   := Color(0, 0, 0, 0.55)

# De-overlap for labels. Selected labels stay anchored and are drawn last.
var _avoid_overlap := true
var _max_label_offset_px := 160     # max nudge distance for labels

# ================ Toolbar ================
var _btn_outlines: Button
var _btn_names: Button
var _btn_mode: OptionButton

func _enter_tree() -> void:
	set_force_draw_over_forwarding_enabled()

	# Outlines toggle
	_btn_outlines = Button.new()
	_btn_outlines.text = "UI Outlines"
	_btn_outlines.toggle_mode = true
	_btn_outlines.button_pressed = true
	_btn_outlines.tooltip_text = "Toggle outlines for Control nodes in the 2D editor"
	_btn_outlines.toggled.connect(_on_toggle_outlines)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _btn_outlines)

	# Names toggle
	_btn_names = Button.new()
	_btn_names.text = "Names"
	_btn_names.toggle_mode = true
	_btn_names.button_pressed = true
	_btn_names.tooltip_text = "Toggle node-name labels"
	_btn_names.toggled.connect(_on_toggle_names)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _btn_names)

	# Label mode selector
	_btn_mode = OptionButton.new()
	_btn_mode.add_item("Labels: All",      LabelMode.ALL)
	_btn_mode.add_item("Labels: Leaves",   LabelMode.LEAVES)
	_btn_mode.add_item("Labels: Selected", LabelMode.SELECTED)
	_btn_mode.selected = int(_labels_mode)
	_btn_mode.item_selected.connect(func(i):
		_labels_mode = i
		_refresh_overlay()
	)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _btn_mode)

	# Refresh on selection/scene change
	var sel := get_editor_interface().get_selection()
	if sel:
		sel.selection_changed.connect(_on_selection_changed)
	scene_changed.connect(_on_scene_changed)

	update_overlays()

func _exit_tree() -> void:
	for c in [_btn_mode, _btn_names, _btn_outlines]:
		if is_instance_valid(c):
			remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, c)
			c.queue_free()
	update_overlays()

# =========== Toggle / refresh ===========
func _on_toggle_outlines(pressed: bool) -> void:
	_enabled = pressed
	_refresh_overlay()

func _on_toggle_names(pressed: bool) -> void:
	_show_labels = pressed
	_refresh_overlay()

func _on_selection_changed() -> void:
	_refresh_overlay()

func _on_scene_changed(_root: Node) -> void:
	_refresh_overlay()

func _refresh_overlay() -> void:
	update_overlays()
	var base := get_editor_interface().get_base_control()
	if base:
		base.queue_redraw()

# ================= Drawing =================
func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if !_enabled:
		return
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return

	var vp2d := get_editor_interface().get_editor_viewport_2d()
	if vp2d == null:
		return

	# Canvas (work area) -> editor screen pixels (pan+zoom aware)
	var canvas_to_screen: Transform2D = vp2d.get_final_transform()
	var zoom := canvas_to_screen.get_scale().x

	var selected_set := _selected_nodes_set()

	# Gather visible controls first so we can do two passes for z-ordering.
	var controls: Array = []
	_gather_controls(root, controls)

	var placed: Array = []

	# PASS 1: non-selected first (background)
	for c in controls:
		if not selected_set.has(c):
			_draw_one_control(c, overlay, canvas_to_screen, zoom, placed, selected_set)

	# PASS 2: selected last (on top)
	for c in controls:
		if selected_set.has(c):
			_draw_one_control(c, overlay, canvas_to_screen, zoom, placed, selected_set)

func _gather_controls(n: Node, out: Array) -> void:
	if n is Control:
		var c := n as Control
		if c.is_visible_in_tree() and c.size.x >= 1.0 and c.size.y >= 1.0:
			out.append(c)
	for child in n.get_children():
		_gather_controls(child, out)

func _draw_one_control(
		c: Control,
		overlay: Control,
		canvas_to_screen: Transform2D,
		zoom: float,
		placed: Array,
		selected_set: Dictionary
	) -> void:

	var to_screen: Transform2D = canvas_to_screen * c.get_global_transform_with_canvas()
	var is_sel := selected_set.has(c)

	# Outline (selected gets different color/width)
	var col := _outline_color_selected if is_sel else _outline_color
	var width := _outline_width_selected if is_sel else _outline_width
	overlay.draw_set_transform_matrix(to_screen)
	overlay.draw_rect(Rect2(Vector2.ZERO, c.size), col, false, width)
	overlay.draw_set_transform_matrix(Transform2D.IDENTITY)

	# Labels
	if _show_labels and zoom >= _min_zoom_for_labels and _should_label(c, selected_set):
		var font := overlay.get_theme_default_font()
		var fsize := overlay.get_theme_default_font_size()
		if font and fsize > 0:
			var anchor_tl: Vector2 = to_screen * Vector2.ZERO
			var pad := Vector2(4, 4)
			var text := c.name
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
			var raw_rect := Rect2(anchor_tl + pad, text_size + pad * 2)

			var final_rect := raw_rect
			# Selected labels keep priority: no de-overlap for them
			if _avoid_overlap and not is_sel:
				var bounds := Rect2(Vector2.ZERO, overlay.get_rect().size)
				var step := int(text_size.y + pad.y * 2 + 2)
				final_rect = _place_near_anchor(raw_rect, placed, bounds, step, _max_label_offset_px)

			overlay.draw_rect(final_rect, _label_bg, true)
			var ascent := font.get_ascent(fsize)
			var text_pos := final_rect.position + Vector2(pad.x, pad.y + ascent)
			overlay.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, _label_text)

# ======== Label policy / helpers =========
func _should_label(c: Control, selected_set: Dictionary) -> bool:
	match _labels_mode:
		LabelMode.ALL:
			return true
		LabelMode.LEAVES:
			return _is_leaf_control(c)
		LabelMode.SELECTED:
			return selected_set.has(c)
	return true

func _is_leaf_control(c: Control) -> bool:
	for ch in c.get_children():
		if ch is Control:
			return false
	return true

func _selected_nodes_set() -> Dictionary:
	var d: Dictionary = {}
	var sel := get_editor_interface().get_selection()
	if sel and sel.has_method("get_selected_nodes"):
		for n in sel.get_selected_nodes():
			d[n] = true
	return d

# Try to place rect near its anchor without overlapping others; stay within a max offset.
func _place_near_anchor(initial: Rect2, placed: Array, bounds: Rect2, step: int, max_offset: int) -> Rect2:
	var r := initial
	var attempts := 0
	while attempts < 300:
		var dx := abs(r.position.x - initial.position.x)
		var dy := abs(r.position.y - initial.position.y)
		if max(dx, dy) <= max_offset and bounds.encloses(r) and !_intersects_any(r, placed):
			placed.append(r)
			return r
		# move down; wrap right within the search window
		r.position.y += step
		if r.position.y - initial.position.y > max_offset:
			r.position.y = initial.position.y
			r.position.x += step
			if r.position.x - initial.position.x > max_offset:
				break
		attempts += 1
	placed.append(initial) # fallback: keep at anchor (may overlap)
	return initial

func _intersects_any(r: Rect2, arr: Array) -> bool:
	for p in arr:
		if r.intersects(p):
			return true
	return false

# ============== Editor plumbing ==============
func _handles(obj: Object) -> bool:
	return obj is Control

func _edit(_obj: Object) -> void:
	_refresh_overlay()
