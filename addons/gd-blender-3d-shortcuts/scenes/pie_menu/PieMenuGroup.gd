@tool
extends Control # Control

signal item_focused(menu: PieMenu, index: int)
signal item_selected(menu: PieMenu, index: int)
signal item_cancelled(menu: PieMenu)

const PieMenu = preload("PieMenu.gd")
const PieMenuScene = preload("PieMenu.tscn")

var root: PieMenu
var page_index: Array[int] = [0]
var theme_source_node: Control = self:
	set = _set_theme_source_node


func _ready() -> void:
	hide()


func _on_item_cancelled(pie_menu: PieMenu) -> void:
	_back()
	item_cancelled.emit(pie_menu)


func _on_item_focused(index: int, pie_menu: PieMenu) -> void:
	var current_menu := _get_current_menu()
	if current_menu == pie_menu:
		item_focused.emit(current_menu, index)


func _on_item_selected(index: int) -> void:
	var last_menu := _get_current_menu()
	page_index.append(index)
	var current_menu := _get_current_menu()
	if is_instance_valid(current_menu):
		current_menu.selected_index = -1
		if current_menu.pie_menus.size() > 0: # Has next page
			current_menu.popup(global_position)

	else:
		# Final selection, revert page index
		if page_index.size() > 1:
			page_index.pop_back()

		last_menu = _get_current_menu()
		page_index = [0]
		hide()
		item_selected.emit(last_menu, index)


func _clear_menu() -> void:
	if is_instance_valid(root):
		root.queue_free()


func _back() -> void:
	var last_menu := _get_current_menu()
	last_menu.hide()
	page_index.pop_back()
	if page_index.size() == 0:
		page_index = [0]
		hide()
		return

	var current_menu := _get_current_menu()
	if is_instance_valid(current_menu):
		current_menu.popup(global_position)


func _get_menu(indexes: Array[int] = [0]) -> PieMenu:
	var pie_menu := root
	for index in indexes.size():
		if index == 0:
			continue # root

		var page := indexes[index]
		pie_menu = pie_menu.pie_menus[page]

	return pie_menu


func _get_current_menu() -> PieMenu:
	return _get_menu(page_index)


func _set_theme_source_node(mod_value: Control) -> void:
	theme_source_node = mod_value
	if not is_instance_valid(root):
		return

	for pie_menu in root.pie_menus:
		if is_instance_valid(pie_menu):
			pie_menu.theme_source_node = theme_source_node


func popup(pos: Vector2) -> void:
	global_position = pos
	var pie_menu := _get_current_menu()
	pie_menu.popup(global_position)
	show()


func populate_menu(items: Array[Variant], pie_menu: PieMenu) -> void:
	assert(is_instance_valid(pie_menu))
	add_child(pie_menu)
	if not is_instance_valid(root):
		root = pie_menu
		if not root.item_focused.is_connected(_on_item_focused):
			if root.item_focused.connect(_on_item_focused.bind(pie_menu)) != OK:
				push_error("[Blender 3D Shortcuts] Failed to connect to root.item_focused")

		if not root.item_selected.is_connected(_on_item_selected):
			if root.item_selected.connect(_on_item_selected) != OK:
				push_error("[Blender 3D Shortcuts] Failed to connect to root.item_selected")

		if not root.item_cancelled.is_connected(_on_item_cancelled):
			if root.item_cancelled.connect(_on_item_cancelled.bind(pie_menu)) != OK:
				push_error("[Blender 3D Shortcuts] Failed to connect to root.item_cancelled")

	pie_menu.items = items
	for index in items.size():
		var item: Variant = items[index]
		var is_array := typeof(item) == TYPE_ARRAY
		var value: Variant = null if not is_array else item[1]
		if typeof(value) == TYPE_ARRAY:
			var new_pie_menu := PieMenuScene.instantiate() as PieMenu
			assert(is_instance_valid(new_pie_menu))
			assert(not new_pie_menu.item_focused.is_connected(_on_item_focused))
			if new_pie_menu.item_focused.connect(_on_item_focused.bind(new_pie_menu)) != OK:
				push_error("[Blender 3D Shortcuts] Failed to connect to new_pie_menu.item_focused")

			assert(not new_pie_menu.item_selected.is_connected(_on_item_selected))
			if new_pie_menu.item_selected.connect(_on_item_selected) != OK:
				push_error("[Blender 3D Shortcuts] Failed to connect to new_pie_menu.item_selected")

			assert(not new_pie_menu.item_cancelled.is_connected(_on_item_cancelled))
			if new_pie_menu.item_cancelled.connect(_on_item_cancelled.bind(new_pie_menu)) != OK:
				push_error("[Blender 3D Shortcuts] Failed to connect to new_pie_menu.item_selected")

			var value_array: Array[Variant] = value
			populate_menu(value_array, new_pie_menu)
			pie_menu.pie_menus.append(new_pie_menu)
		else:
			pie_menu.pie_menus.append(null)
