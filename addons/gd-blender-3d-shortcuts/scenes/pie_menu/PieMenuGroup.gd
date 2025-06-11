@tool
extends Control


signal item_focused(menu: PieMenu, index: int)
signal item_selected(menu: PieMenu, index: int)
signal item_cancelled(menu: PieMenu)


const PieMenuScn = preload("PieMenu.tscn")
const PieMenu := preload("PieMenu.gd")


var root: PieMenu
var page_index: Array[int] = [0]
var theme_source_node: Control = self: set = set_theme_source_node


func _ready() -> void:
	hide()


func _on_item_cancelled(pie_menu: PieMenu) -> void:
	back()
	item_cancelled.emit(pie_menu)


func _on_item_focused(index: int, pie_menu: PieMenu) -> void:
	var current_menu := get_current_menu()
	if current_menu == pie_menu:
		item_focused.emit(current_menu, index)


func _on_item_selected(index: int) -> void:
	var last_menu := get_current_menu()
	page_index.append(index)
	var current_menu := get_current_menu()
	if current_menu:
		current_menu.selected_index = -1
		if current_menu.pie_menus.size() > 0: # Has next page
			current_menu.popup(global_position)

		return

	# Final selection, revert page index
	if page_index.size() > 1:
		page_index.pop_back()

	last_menu = get_current_menu()
	page_index = [0]
	hide()
	item_selected.emit(last_menu, index)


func popup(pos: Vector2) -> void:
	global_position = pos
	var pie_menu := get_current_menu()
	pie_menu.popup(global_position)
	show()


func populate_menu(items: Array[Variant], pie_menu: PieMenu) -> PieMenu:
	add_child(pie_menu)
	if not root:
		root = pie_menu
		if root.item_focused.connect(_on_item_focused.bind(pie_menu)) != OK:
			push_error("Failed to connect to item_focused")

		if root.item_selected.connect(_on_item_selected) != OK:
			push_error("Failed to connect to item_selected")

		if root.item_cancelled.connect(_on_item_cancelled.bind(pie_menu)) != OK:
			push_error("Failed to connect to item_cancelled")

	pie_menu.items = items

	for i in items.size():
		var item: Variant = items[i]
		var is_array := typeof(item) == TYPE_ARRAY
		# var name = item if not is_array else item[0]
		var value: Variant = null if not is_array else item[1]
		if typeof(value) == TYPE_ARRAY:
			var new_pie_menu: PieMenu = PieMenuScn.instantiate()
			if new_pie_menu.item_focused.connect(_on_item_focused.bind(new_pie_menu)) != OK:
				push_error("Failed to connect to item_focused")

			if new_pie_menu.item_selected.connect(_on_item_selected) != OK:
				push_error("Failed to connect to item_selected")

			if new_pie_menu.item_cancelled.connect(_on_item_cancelled.bind(new_pie_menu)) != OK:
				push_error("Failed to connect to item_cancelled")

			var value_array: Array[Variant] = value
			@warning_ignore("return_value_discarded")
			populate_menu(value_array, new_pie_menu)
			pie_menu.pie_menus.append(new_pie_menu)
		else:
			pie_menu.pie_menus.append(null)

	return pie_menu


func clear_menu() -> void:
	if root:
		root.queue_free()


func back() -> void:
	var last_menu := get_current_menu()
	last_menu.hide()
	page_index.pop_back()
	if page_index.size() == 0:
		page_index = [0]
		hide()
		return

	var current_menu := get_current_menu()
	if current_menu:
		current_menu.popup(global_position)


func get_menu(indexes: Array[int] = [0]) -> PieMenu:
	var pie_menu := root
	for i in indexes.size():
		if i == 0:
			continue # root

		var page := indexes[i]
		pie_menu = pie_menu.pie_menus[page]

	return pie_menu


func get_current_menu() -> PieMenu:
	return get_menu(page_index)


func set_theme_source_node(v: Control) -> void:
	theme_source_node = v
	if not root:
		return

	for pie_menu in root.pie_menus:
		if pie_menu:
			pie_menu.theme_source_node = theme_source_node
