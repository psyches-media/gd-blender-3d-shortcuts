@tool
extends Control


signal item_selected(index: int)
signal item_focused(index: int)
signal item_cancelled()


const PieMenu := preload("PieMenu.gd") # SELF


const BUTTON_MARGIN := 6


@export var items: Array[Variant] = []: set = _set_items
@export var selected_index := -1: set = _set_selected_index
@export var radius := 100.0: set = _set_radius


var buttons: Array[Button] = []
var pie_menus: Array[PieMenu] = []
var theme_source_node: Control = self: set = _set_theme_source_node


var _focused_index := -1
var _grow_with_max_button_width := false


func _ready() -> void:
	_set_items(items)
	_set_selected_index(selected_index)
	_set_radius(radius)
	hide()
	if visibility_changed.connect(_on_visiblity_changed) != OK:
		push_error("Failed to connect to visibility_changed")


func _input(event: InputEvent) -> void:
	if not visible:
		return

	var input_event_key := event as InputEventKey
	if input_event_key != null:
		if input_event_key.pressed:
			match input_event_key.keycode:
				KEY_ESCAPE:
					_cancel()

	if event is InputEventMouseMotion:
		_focus_item()
		get_viewport().set_input_as_handled()

	var input_event_mouse_button := event as InputEventMouseButton
	if input_event_mouse_button != null:
		if input_event_mouse_button.pressed:
			match input_event_mouse_button.button_index:
				MOUSE_BUTTON_LEFT:
					_select_item(_focused_index)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_RIGHT:
					_cancel()
					get_viewport().set_input_as_handled()


func _on_visiblity_changed() -> void:
	if not visible:
		if selected_index != _focused_index: # Cancellation
			_focused_index = selected_index


func _cancel() -> void:
	hide()
	get_viewport().set_input_as_handled()
	item_cancelled.emit()


func _select_item(index: int) -> void:
	_set_button_style(selected_index, "normal", "normal")
	selected_index = index
	_focused_index = selected_index
	hide()
	item_selected.emit(selected_index)


func _focus_item() -> void:
	queue_redraw()
	var pos := get_global_mouse_position()
	var count := maxi(buttons.size(), 1)
	var angle_offset := 2 * PI / count
	var angle := pos.angle_to_point(global_position) + PI / 2 # -90 deg initial offset
	if angle < 0:
		angle += 2 * PI

	var index: float = angle / angle_offset
	var decimal := index - floorf(index)
	index = floor(index)
	if decimal >= 0.5:
		index += 1

	if index > buttons.size() - 1:
		index = 0

	_set_button_style(_focused_index, "normal", "normal")
	_focused_index = int(index)
	_set_button_style(_focused_index, "normal", "hover")
	_set_button_style(selected_index, "normal", "focus")
	item_focused.emit(_focused_index)


func popup(pos: Vector2) -> void:
	global_position = pos
	show()


func _populate_menu() -> void:
	_clear_menu()
	buttons = []
	for i in items.size():
		var item: Variant = items[i]
		var is_array := typeof(item) == TYPE_ARRAY
		var option_text: String = item if not is_array else item[0]
		var option_value:Variant = null if not is_array else item[1]
		var button := Button.new()
		button.grow_horizontal = Control.GROW_DIRECTION_BOTH
		button.text = option_text
		if option_value != null:
			button.set_meta("value", option_value)

		buttons.append(button)
		_set_button_style(i, "hover", "hover")
		_set_button_style(i, "pressed", "pressed")
		_set_button_style(i, "focus", "focus")
		_set_button_style(i, "disabled", "disabled")
		_set_button_style(i, "normal", "normal")
		add_child(button)

	_align()

	_set_button_style(selected_index, "normal", "focus")


func _align() -> void:
	var final_radius := radius
	if _grow_with_max_button_width:
		var max_button_width := 0.0
		for button in buttons:
			max_button_width = max(max_button_width, button.size.x)

		final_radius = maxf(radius, max_button_width)

	var count := maxi(buttons.size(), 1)
	var angle_offset := 2 * PI / count
	var angle := PI / 2 # 90 deg initial offset
	for button in buttons:
		button.position = Vector2(final_radius, 0.0).rotated(angle) - (button.size / 2.0)
		angle += angle_offset

func _clear_menu() -> void:
	for button in buttons:
		button.queue_free()


func _set_button_style(index: int, target_style: String, source_style: String) -> void:
	if index < 0 or index > buttons.size() - 1:
		return

	buttons[index].set(
		"theme_override_styles/%s" % target_style,
		get_theme_stylebox(source_style, "Button")
	)


func _set_items(v: Array[Variant]) -> void:
	items = v
	if is_inside_tree():
		_populate_menu()


func _set_selected_index(v: int) -> void:
	_set_button_style(selected_index, "normal", "normal")
	selected_index = v
	_set_button_style(selected_index, "normal", "focus")


func _set_radius(v: float) -> void:
	radius = v
	_align()


func _set_theme_source_node(v: Control) -> void:
	theme_source_node = v
	for pie_menu in pie_menus:
		if is_instance_valid(pie_menu):
			pie_menu.theme_source_node = theme_source_node
