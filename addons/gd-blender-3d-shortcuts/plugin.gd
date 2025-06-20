@tool
extends EditorPlugin


enum Session {
	TRANSLATE,
	ROTATE,
	SCALE,
	NONE
}


const Utils := preload("Utils.gd")
const PieMenuScn := preload("scenes/pie_menu/PieMenu.tscn")
const PieMenu := preload("scenes/pie_menu/PieMenu.gd")
const PieMenuGroupScn := preload("scenes/pie_menu/PieMenuGroup.tscn")
const PieMenuGroup := preload("scenes/pie_menu/PieMenuGroup.gd")


const DEFAULT_LINE_COLOR = Color.WHITE


# Array[T] where T = [String, int|T]
const DEBUG_DRAW_OPTIONS: Array[Array] = [
	[
		"Normal",
		0
	],
	[
		"Unshaded",
		1
	],
	[
		"Lighting",
		2
	],
	[
		"Overdraw",
		3
	],
	[
		"Wireframe",
		4
	],
	[
		"Advance",
		[
			[
				"Shadows",
				[
					[
						"Shadow Atlas",
						9
					],
					[
						"Directional Shadow Atlas",
						10
					],
					[
						"Directional Shadow Splits",
						14
					]
				]
			],
			[
				"Lights",
				[
					[
						"Omni Lights Cluster",
						20
					],
					[
						"Spot Lights Cluster",
						21
					]
				]
			],
			[
				"VoxelGI",
				[
					[
						"VoxelGI Albedo",
						6
					],
					[
						"VoxelGI Lighting",
						7
					],
					[
						"VoxelGI Emission",
						8
					]
				]
			],
			[
				"SDFGI",
				[
					[
						"SDFGI",
						16
					],
					[
						"SDFGI Probes",
						17
					],
					[
						"GI Buffer",
						18
					]
				]
			],
			[
				"Environment",
				[
					[
						"SSAO",
						12
					],
					[
						"SSIL",
						13
					]
				]
			],
			[
				"Decals",
				[
					[
						"Decal Atlas",
						15
					],
					[
						"Decal Cluster",
						22
					]
				]
			],
			[
				"Others",
				[
					[
						"Normal Buffer",
						5
					],
					[
						"Scene Luminance",
						11
					],
					[
						"Disable LOD",
						19
					],
					[
						"Cluster Reflection Probes",
						23
					],
					[
						"Occluders",
						24
					],
					[
						"Motion Vectors",
						25
					]
				]
			],
		]
	],
]


var translate_snap_line_edit: LineEdit
var rotate_snap_line_edit: LineEdit
var scale_snap_line_edit: LineEdit
var local_space_button: Button
var snap_button: Button
var overlay_control: Control
var spatial_editor_viewports: Array[Control]
var debug_draw_pie_menu: PieMenuGroup
var overlay_control_canvas_layer := CanvasLayer.new()

var overlay_label := Label.new()
var axis_mesh_inst: MeshInstance3D
var axis_im := ImmediateMesh.new()
var axis_im_material := StandardMaterial3D.new()

var current_session := Session.NONE
var pivot_point := Vector3.ZERO
var constraint_axis := Vector3.ONE
var translate_snap := 1.0
var rotate_snap := deg_to_rad(15.0)
var scale_snap := 0.1
var is_snapping := false
var is_global := true
var axis_length := 1000.0
var precision_mode := false
var precision_factor := 0.1

var _is_editing := false
var _camera: Camera3D
var _editing_transform := Transform3D.IDENTITY
var _applying_transform := Transform3D.IDENTITY
var _last_world_pos := Vector3.ZERO
var _init_angle := NAN
var _last_angle := 0.0
var _last_center_offset := 0.0
var _cummulative_center_offset := 0.0
var _max_x := 0.0
var _min_x := 0.0
var _cache_global_transforms: Array[Transform3D] = []
var _cache_transforms: Array[Transform3D] = [] # Nodes' local transform relative to pivot_point
var _input_string := ""
var _is_global_on_session := false
var _is_warping_mouse := false
var _is_pressing_right_mouse_button := false


func _init() -> void:
	axis_im_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	axis_im_material.vertex_color_use_as_albedo = true
	axis_im_material.no_depth_test = true

	overlay_label.set("custom_colors/font_color_shadow", Color.BLACK)


func _ready() -> void:
	var spatial_editor := Utils.get_spatial_editor(EditorInterface.get_base_control())
	var snap_dialog := Utils.get_snap_dialog(spatial_editor)
	var snap_dialog_line_edits := Utils.get_snap_dialog_line_edits(snap_dialog)
	translate_snap_line_edit = snap_dialog_line_edits[0]
	rotate_snap_line_edit = snap_dialog_line_edits[1]
	scale_snap_line_edit = snap_dialog_line_edits[2]
	if translate_snap_line_edit.text_changed.connect(
		_on_snap_value_changed.bind(Session.TRANSLATE)
	) != OK:
		push_error("Failed to connect to text_changed signal")

	if rotate_snap_line_edit.text_changed.connect(_on_snap_value_changed.bind(Session.ROTATE)) != OK:
		push_error("Failed to connect to text_changed signal")

	if scale_snap_line_edit.text_changed.connect(_on_snap_value_changed.bind(Session.SCALE)) != OK:
		push_error("Failed to connect to text_changed signal")

	local_space_button = Utils.get_spatial_editor_local_space_button(spatial_editor)
	if local_space_button.toggled.connect(_on_local_space_button_toggled) != OK:
		push_error("Failed to connect to toggled signal")

	snap_button = Utils.get_spatial_editor_snap_button(spatial_editor)
	if snap_button.toggled.connect(_on_snap_button_toggled) != OK:
		push_error("Failed to connect to toggled signal")

	debug_draw_pie_menu = PieMenuGroupScn.instantiate()
	@warning_ignore("return_value_discarded")
	debug_draw_pie_menu.populate_menu(DEBUG_DRAW_OPTIONS, PieMenuScn.instantiate() as PieMenu)
	debug_draw_pie_menu.theme_source_node = spatial_editor
	if debug_draw_pie_menu.item_focused.connect(_on_PieMenu_item_focused) != OK:
		push_error("Failed to connect to item_focused signal")

	if debug_draw_pie_menu.item_selected.connect(_on_PieMenu_item_selected) != OK:
		push_error("Failed to connect to item_selected signal")

	var spatial_editor_viewport_container := (
		Utils.get_spatial_editor_viewport_container(spatial_editor)
	)
	if is_instance_valid(spatial_editor_viewport_container):
		spatial_editor_viewports = Utils.get_spatial_editor_viewports(spatial_editor_viewport_container)

	sync_settings()


func _input(event: InputEvent) -> void:
	var input_event_key := event as InputEventKey
	if input_event_key != null:
		# Check meta modifier to avoid conflict with Mac command
		if input_event_key.pressed and not input_event_key.echo and not input_event_key.meta_pressed:
			match input_event_key.keycode:
				KEY_Z:
					var focus := find_focused_control(get_tree().root)
					if focus != null:
						var focus_parent_control := focus.get_parent_control()
						if focus_parent_control != null:
							if focus_parent_control.get_class() == "Node3DEditorViewport":
								if debug_draw_pie_menu.visible:
									debug_draw_pie_menu.hide()
									get_viewport().set_input_as_handled()
								else:
									if (
										not (
											input_event_key.ctrl_pressed
											or input_event_key.alt_pressed
											or input_event_key.shift_pressed
										)
										and current_session == Session.NONE
									):
										@warning_ignore("return_value_discarded")
										show_debug_draw_pie_menu()
										get_viewport().set_input_as_handled()

			# Hacky way to intercept default shortcut behavior when in session
			if current_session != Session.NONE:
				var event_text := input_event_key.as_text()
				if event_text.begins_with("Kp"):
					@warning_ignore("return_value_discarded")
					_append_input_string(event_text.replace("Kp ", ""))
					get_viewport().set_input_as_handled()

				match input_event_key.keycode:
					KEY_Y:
						if input_event_key.shift_pressed:
							toggle_constraint_axis(Vector3.RIGHT + Vector3.BACK)
						else:
							toggle_constraint_axis(Vector3.UP)

						get_viewport().set_input_as_handled()

	var input_event_mouse_motion := event as InputEventMouseMotion
	if input_event_mouse_motion != null:
		if current_session != Session.NONE and overlay_control:
			# Infinite mouse movement
			var rect := overlay_control.get_rect()
			var local_mouse_pos := overlay_control.get_local_mouse_position()
			if not rect.has_point(local_mouse_pos):
				var warp_pos:Variant = Utils.infinite_rect(
					rect,
					local_mouse_pos,
					-input_event_mouse_motion.velocity.normalized() * rect.size.length()
				)
				if warp_pos != null:
					var wrap_pos_vector: Vector2 = warp_pos
					Input.warp_mouse(overlay_control.global_position + wrap_pos_vector)
					_is_warping_mouse = true


func _on_snap_value_changed(text: String, session: Session) -> void:
	match session:
		Session.TRANSLATE:
			translate_snap = text.to_float()
		Session.ROTATE:
			rotate_snap = deg_to_rad(text.to_float())
		Session.SCALE:
			scale_snap = text.to_float() / 100.0


func _on_PieMenu_item_focused(menu: PieMenu, index: int) -> void:
	var value: Variant = menu.buttons[index].get_meta("value", 0)
	if typeof(value) != TYPE_ARRAY:
		var debug_draw: Viewport.DebugDraw = value
		_switch_display_mode(debug_draw)


func _on_PieMenu_item_selected(menu: PieMenu, index: int) -> void:
	var value: Variant = menu.buttons[index].get_meta("value", 0)
	if typeof(value) != TYPE_ARRAY:
		var debug_draw: Viewport.DebugDraw = value
		_switch_display_mode(debug_draw)


func show_debug_draw_pie_menu() -> bool:
	var spatial_editor_viewport := Utils.get_focused_spatial_editor_viewport(spatial_editor_viewports)
	overlay_control = (
		Utils.get_spatial_editor_viewport_control(spatial_editor_viewport)
			if spatial_editor_viewport
			else null
	)
	if not overlay_control:
		return false

	if overlay_control_canvas_layer.get_parent() != overlay_control:
		overlay_control.add_child(overlay_control_canvas_layer)

	if debug_draw_pie_menu.get_parent() != overlay_control_canvas_layer:
		overlay_control_canvas_layer.add_child(debug_draw_pie_menu)
		var viewport := Utils.get_spatial_editor_viewport_viewport(spatial_editor_viewport)
		assert(viewport != null)

	debug_draw_pie_menu.popup(overlay_control.get_global_mouse_position())
	return true


func _on_local_space_button_toggled(pressed: bool) -> void:
	is_global = not pressed


func _on_snap_button_toggled(pressed: bool) -> void:
	is_snapping = pressed


func _handles(object: Object) -> bool:
	if object is Node3D:
		_is_editing = EditorInterface.get_selection().get_selected_nodes().size()
		return _is_editing

	# Explicitly handle MultiNodeEdit, otherwise, it will active when selected Resource
	if object.get_class() == "MultiNodeEdit":
		_is_editing = EditorInterface.get_selection().get_transformable_selected_nodes().size() > 0
		return _is_editing

	return false


func _edit(_object: Object) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root != null:
		# Let editor free axis_mesh_inst as the scene closed,
		# then create new instance whenever needed
		if not is_instance_valid(axis_mesh_inst):
			axis_mesh_inst = MeshInstance3D.new()
			axis_mesh_inst.mesh = axis_im
			axis_mesh_inst.material_override = axis_im_material

		if axis_mesh_inst.get_parent() == null:
			scene_root.get_parent().add_child(axis_mesh_inst)
		else:
			if axis_mesh_inst.get_parent() != scene_root:
				axis_mesh_inst.get_parent().remove_child(axis_mesh_inst)
				scene_root.get_parent().add_child(axis_mesh_inst)


func find_focused_control(node: Node) -> Control:
	assert(is_instance_valid(node))
	var control := node as Control
	if is_instance_valid(control) and control.has_focus():
		return control

	for child in node.get_children():
		var result := find_focused_control(child)
		if is_instance_valid(result):
			return result

	return null


func _forward_3d_gui_input_no_session(camera: Camera3D, event: InputEvent) -> int:
	var forward := false
	# solve conflict with free look
	var input_event_mouse_button := event as InputEventMouseButton
	if input_event_mouse_button is InputEventMouseButton:
		if input_event_mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_is_pressing_right_mouse_button = input_event_mouse_button.is_pressed()

	if _is_editing:
		var input_event_key := event as InputEventKey
		if input_event_key != null:
			# Check meta modifier to avoid conflict with Mac command
			if input_event_key.pressed and not input_event_key.meta_pressed:
				match input_event_key.keycode:
					KEY_G:
						start_session(Session.TRANSLATE, camera, input_event_key)
						forward = true
					KEY_R:
						start_session(Session.ROTATE, camera, input_event_key)
						forward = true
					KEY_S:
						if not input_event_key.ctrl_pressed:
							# solve conflict with free look
							if not _is_pressing_right_mouse_button:
								start_session(Session.SCALE, camera, input_event_key)
								forward = true
					KEY_H:
						commit_hide_nodes()
					KEY_X:
						if input_event_key.shift_pressed:
							delete_selected_nodes()
						else:
							confirm_delete_selected_nodes()

	return forward


func _forward_3d_gui_input_session(camera: Camera3D, event: InputEvent) -> int:
	var forward := false
	var input_event_key := event as InputEventKey
	if input_event_key != null:
		# Not sure why event.pressed always return false for numpad keys
		match input_event_key.keycode:
			KEY_KP_SUBTRACT:
				_toggle_input_string_sign()
				return true

			KEY_KP_ENTER:
				commit_session()
				end_session()
				return true

		if input_event_key.keycode == KEY_SHIFT:
			precision_mode = input_event_key.pressed
			forward = true

		# Check meta modifier to avoid conflict with Mac command
		if input_event_key.pressed and not input_event_key.meta_pressed:
			var event_text := input_event_key.as_text()
			if _append_input_string(event_text):
				return true

			var return_true := false
			match input_event_key.keycode:
				KEY_G:
					if current_session != Session.TRANSLATE:
						revert()
						clear_session()
						start_session(Session.TRANSLATE, camera, input_event_key)
						return_true = true

				KEY_R:
					if current_session != Session.ROTATE:
						revert()
						clear_session()
						start_session(Session.ROTATE, camera, input_event_key)
						return_true = true

				KEY_S:
					if not input_event_key.ctrl_pressed:
						if current_session != Session.SCALE:
							revert()
							clear_session()
							start_session(Session.SCALE, camera, input_event_key)
							return_true = true

				KEY_X:
					if input_event_key.shift_pressed:
						toggle_constraint_axis(Vector3.UP + Vector3.BACK)
					else:
						toggle_constraint_axis(Vector3.RIGHT)

					return_true = true

				KEY_Y:
					if input_event_key.shift_pressed:
						toggle_constraint_axis(Vector3.RIGHT + Vector3.BACK)
					else:
						toggle_constraint_axis(Vector3.UP)

					return_true = true

				KEY_Z:
					if input_event_key.shift_pressed:
						toggle_constraint_axis(Vector3.RIGHT + Vector3.UP)
					else:
						toggle_constraint_axis(Vector3.BACK)

					return_true = true

				KEY_MINUS:
					_toggle_input_string_sign()
					return_true = true

				KEY_BACKSPACE:
					_trim_input_string()
					return_true = true

				KEY_ENTER:
					commit_session()
					end_session()
					return_true = true

				KEY_ESCAPE:
					revert()
					end_session()
					return_true = true

			if return_true:
				return true

	var input_event_mouse_button := event as InputEventMouseButton
	if input_event_mouse_button != null:
		if input_event_mouse_button.pressed:
			if input_event_mouse_button.button_index == 2:
				revert()
				end_session()
				return true

			commit_session()
			end_session()
			forward = true

	var input_event_mouse_motion := event as InputEventMouseMotion
	if input_event_mouse_motion != null:
		match current_session:
			Session.TRANSLATE, Session.ROTATE, Session.SCALE:
				mouse_transform(input_event_mouse_motion)
				@warning_ignore("return_value_discarded")
				update_overlays()
				forward = true

	return forward


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if current_session == Session.NONE:
		return _forward_3d_gui_input_no_session(camera, event)

	return _forward_3d_gui_input_session(camera, event)


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if current_session == Session.NONE:
		if overlay_label.get_parent() != null:
			overlay_label.get_parent().remove_child(overlay_label)

		return

	var editor_settings := EditorInterface.get_editor_settings()
	var line_color := DEFAULT_LINE_COLOR
	if editor_settings.has_setting("editors/3d/selection_box_color"):
		line_color = editor_settings.get_setting("editors/3d/selection_box_color")

	var snapped_text := "snapped" if is_snapping else ""
	var global_or_local := "global" if is_global else "local"
	var along_axis := ""
	if not constraint_axis.is_equal_approx(Vector3.ONE):
		if constraint_axis.x > 0:
			along_axis = "X"

		if constraint_axis.y > 0:
			along_axis += ", Y" if along_axis.length() else "Y"

		if constraint_axis.z > 0:
			along_axis += ", Z" if along_axis.length() else "Z"

	if along_axis.length():
		along_axis = "along " + along_axis

	if overlay_label.get_parent() == null:
		overlay_control.add_child(overlay_label)
		overlay_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		overlay_label.position += Vector2(8, -8)

	match current_session:
		Session.TRANSLATE:
			var translation := _applying_transform.origin
			overlay_label.text = (
				"Translate (%.3f, %.3f, %.3f) %s %s %s" % [
					translation.x,
					translation.y,
					translation.z,
					global_or_local,
					along_axis, snapped_text
				]
			)
		Session.ROTATE:
			var rotation := _applying_transform.basis.get_euler()
			overlay_label.text = (
				"Rotate (%.3f, %.3f, %.3f) %s %s %s" % [
					rad_to_deg(rotation.x),
					rad_to_deg(rotation.y),
					rad_to_deg(rotation.z),
					global_or_local,
					along_axis,
					snapped_text
				]
			)
		Session.SCALE:
			var scale := _applying_transform.basis.get_scale()
			overlay_label.text = (
				"Scale (%.3f, %.3f, %.3f) %s %s %s" % [
					scale.x,
					scale.y,
					scale.z,
					global_or_local,
					along_axis,
					snapped_text
				]
			)

	if not _input_string.is_empty():
		overlay_label.text += "(%s)" % _input_string

	var is_pivot_point_behind_camera := _camera.is_position_behind(pivot_point)
	var screen_origin := overlay.size / 2.0
	if not is_pivot_point_behind_camera:
		screen_origin = _camera.unproject_position(pivot_point)

	Utils.draw_dashed_line(
		overlay,
		screen_origin,
		overlay.get_local_mouse_position(),
		line_color,
		1,
		5,
		true,
		true
	)


func text_transform(text: String) -> void:
	var input_value := text.to_float()
	match current_session:
		Session.TRANSLATE:
			_applying_transform.origin = constraint_axis * input_value
		Session.ROTATE:
			_applying_transform.basis = (
				Basis.IDENTITY.rotated(
					(-_camera.global_transform.basis.z * constraint_axis).normalized(),
					deg_to_rad(input_value)
				)
			)
		Session.SCALE:
			if constraint_axis.x:
				_applying_transform.basis.x = Vector3.RIGHT * input_value

			if constraint_axis.y:
				_applying_transform.basis.y = Vector3.UP * input_value

			if constraint_axis.z:
				_applying_transform.basis.z = Vector3.BACK * input_value

	var nodes := EditorInterface.get_selection().get_transformable_selected_nodes()
	var t := _applying_transform
	if (
		is_global
		or (constraint_axis.is_equal_approx(Vector3.ONE) and current_session == Session.TRANSLATE)
	):
		t.origin += pivot_point
		Utils.apply_global_transform(nodes, t, _cache_transforms)
	else:
		Utils.apply_transform(nodes, t, _cache_global_transforms)


func mouse_transform(event: InputEventMouseMotion) -> void:
	var nodes := EditorInterface.get_selection().get_transformable_selected_nodes()
	var is_single_node := nodes.size() == 1
	var node1 := nodes[0] as Node3D
	assert(is_instance_valid(node1))
	var is_pivot_point_behind_camera := _camera.is_position_behind(pivot_point)
	var screen_origin: Vector2
	if is_nan(_init_angle):
		screen_origin = _camera.unproject_position(pivot_point)
		_init_angle = event.position.angle_to_point(screen_origin)

	# Translation offset
	var plane_transform := _camera.global_transform
	plane_transform.origin = pivot_point
	plane_transform.basis = plane_transform.basis.rotated(
		plane_transform.basis * Vector3.LEFT, deg_to_rad(90)
	)
	if is_pivot_point_behind_camera:
		plane_transform.origin = (
			_camera.global_transform.origin - _camera.global_transform.basis.z * 10.0
		)

	var plane := Utils.transform_to_plane(plane_transform)
	var axis_count := _get_constraint_axis_count()
	if axis_count == 2:
		var normal := (Vector3.ONE - constraint_axis).normalized()
		if is_single_node and not is_global:
			normal = node1.global_transform.basis * normal

		var plane_dist := normal * plane_transform.origin
		plane = Plane(normal, plane_dist.x + plane_dist.y + plane_dist.z)

	var world_pos := Utils.project_on_plane(_camera, event.position, plane)
	if not is_global and is_single_node and axis_count < 3:
		var normalized_node1_basis := node1.global_transform.basis.scaled(
			Vector3.ONE / node1.global_transform.basis.get_scale()
		)
		world_pos = world_pos * normalized_node1_basis

	if is_equal_approx(_last_world_pos.length(), 0):
		_last_world_pos = world_pos

	var offset := world_pos - _last_world_pos
	offset *= constraint_axis
	offset = offset.snapped(Vector3.ONE * 0.001)
	if _is_warping_mouse:
		offset = Vector3.ZERO

	# Rotation offset
	screen_origin = _camera.unproject_position(pivot_point)
	if is_pivot_point_behind_camera:
		screen_origin = overlay_control.size / 2.0

	var angle: float = event.position.angle_to_point(screen_origin) - _init_angle
	var angle_offset := angle - _last_angle
	angle_offset = snapped(angle_offset, 0.001)
	# Scale offset
	if is_zero_approx(_max_x):
		_max_x = event.position.x
		_min_x = _max_x - (_max_x - screen_origin.x) * 2

	var center_value := 2 * ((event.position.x - _min_x) / (_max_x - _min_x)) - 1
	if is_zero_approx(_last_center_offset):
		_last_center_offset = center_value

	var center_offset := center_value - _last_center_offset
	center_offset = snapped(center_offset, 0.001)
	if _is_warping_mouse:
		center_offset = 0

	_cummulative_center_offset += center_offset
	if _input_string.is_empty():
		match current_session:
			Session.TRANSLATE:
				_editing_transform = _editing_transform.translated(offset)
				_applying_transform.origin = _editing_transform.origin
				if is_snapping:
					var snap := (
						Vector3.ONE * (translate_snap if not precision_mode else translate_snap * precision_factor)
					)
					_applying_transform.origin = _applying_transform.origin.snapped(snap)

			Session.ROTATE:
				var rotation_axis := (-_camera.global_transform.basis.z * constraint_axis).normalized()
				if not rotation_axis.is_equal_approx(Vector3.ZERO):
					_editing_transform.basis = _editing_transform.basis.rotated(rotation_axis, angle_offset)
					var quat := _editing_transform.basis.get_rotation_quaternion()
					if is_snapping:
						var snap := (
							Vector3.ONE * (rotate_snap if not precision_mode else rotate_snap * precision_factor)
						)
						quat = Quaternion.from_euler(quat.get_euler().snapped(snap))

					_applying_transform.basis = Basis(quat)

			Session.SCALE:
				if constraint_axis.x:
					_editing_transform.basis.x = Vector3.RIGHT * (1 + _cummulative_center_offset)

				if constraint_axis.y:
					_editing_transform.basis.y = Vector3.UP * (1 + _cummulative_center_offset)

				if constraint_axis.z:
					_editing_transform.basis.z = Vector3.BACK * (1 + _cummulative_center_offset)

				_applying_transform.basis = _editing_transform.basis
				if is_snapping:
					var snap := Vector3.ONE * (scale_snap if not precision_mode else scale_snap * precision_factor)
					_applying_transform.basis.x = _applying_transform.basis.x.snapped(snap)
					_applying_transform.basis.y = _applying_transform.basis.y.snapped(snap)
					_applying_transform.basis.z = _applying_transform.basis.z.snapped(snap)

	var t := _applying_transform
	if (
		is_global
		or (constraint_axis.is_equal_approx(Vector3.ONE) and current_session == Session.TRANSLATE)
	):
		t.origin += pivot_point
		Utils.apply_global_transform(nodes, t, _cache_transforms)
	else:
		Utils.apply_transform(nodes, t, _cache_global_transforms)

	_last_world_pos = world_pos
	_last_center_offset = center_value
	_last_angle = angle
	_is_warping_mouse = false


func cache_selected_nodes_transforms() -> void:
	var nodes := EditorInterface.get_selection().get_transformable_selected_nodes()
	var inversed_pivot_transform := Transform3D().translated(pivot_point).affine_inverse()
	for i in nodes.size():
		var node := nodes[i] as Node3D
		assert(is_instance_valid(node))
		_cache_global_transforms.append(node.global_transform)
		_cache_transforms.append(inversed_pivot_transform * node.global_transform)


func update_pivot_point() -> void:
	var nodes := EditorInterface.get_selection().get_transformable_selected_nodes()
	var aabb := AABB()
	for i in nodes.size():
		var node := nodes[i] as Node3D
		assert(is_instance_valid(node))
		if i == 0:
			aabb.position = node.global_transform.origin

		aabb = aabb.expand(node.global_transform.origin)

	pivot_point = aabb.position + aabb.size / 2.0


func start_session(session: Session, camera: Camera3D, event: InputEvent) -> void:
	if EditorInterface.get_selection().get_transformable_selected_nodes().size() == 0:
		return

	current_session = session
	_camera = camera
	_is_global_on_session = is_global
	update_pivot_point()
	cache_selected_nodes_transforms()

	var input_event_with_modifiers := event as InputEventWithModifiers
	if input_event_with_modifiers != null and input_event_with_modifiers.alt_pressed:
		commit_reset_transform()
		end_session()
		return

	@warning_ignore("return_value_discarded")
	update_overlays()
	var spatial_editor_viewport := Utils.get_focused_spatial_editor_viewport(spatial_editor_viewports)
	overlay_control = null
	if spatial_editor_viewport:
		overlay_control = Utils.get_spatial_editor_viewport_control(spatial_editor_viewport)


func end_session() -> void:
	_is_editing = EditorInterface.get_selection().get_transformable_selected_nodes().size() > 0
	# Manually set is_global to avoid triggering revert()
	if is_instance_valid(local_space_button):
		local_space_button.button_pressed = not _is_global_on_session
	is_global = _is_global_on_session
	clear_session()
	@warning_ignore("return_value_discarded")
	update_overlays()


func commit_session() -> void:
	var undo_redo := get_undo_redo()
	var nodes := EditorInterface.get_selection().get_transformable_selected_nodes()
	Utils.revert_transform(nodes, _cache_global_transforms)
	var session: String = Session.keys()[current_session]
	undo_redo.create_action(session.to_lower().capitalize())
	var t := _applying_transform
	if (
		is_global
		or (constraint_axis.is_equal_approx(Vector3.ONE) and current_session == Session.TRANSLATE)
	):
		t.origin += pivot_point
		undo_redo.add_do_method(Utils, "apply_global_transform", nodes, t, _cache_transforms)
	else:
		undo_redo.add_do_method(Utils, "apply_transform", nodes, t, _cache_global_transforms)

	undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
	undo_redo.commit_action()


func commit_reset_transform() -> void:
	var undo_redo := get_undo_redo()
	var nodes: Array[Node] = EditorInterface.get_selection().get_transformable_selected_nodes()
	match current_session:
		Session.TRANSLATE:
			undo_redo.create_action("Reset Translation")
			undo_redo.add_do_method(Utils, "reset_translation", nodes)
			undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
			undo_redo.commit_action()
		Session.ROTATE:
			undo_redo.create_action("Reset Rotation")
			undo_redo.add_do_method(Utils, "reset_rotation", nodes)
			undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
			undo_redo.commit_action()
		Session.SCALE:
			undo_redo.create_action("Reset Scale")
			undo_redo.add_do_method(Utils, "reset_scale", nodes)
			undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
			undo_redo.commit_action()

	current_session = Session.NONE


func commit_hide_nodes() -> void:
	var undo_redo := get_undo_redo()
	var nodes: Array[Node] = EditorInterface.get_selection().get_transformable_selected_nodes()
	undo_redo.create_action("Hide Nodes")
	undo_redo.add_do_method(Utils, "hide_nodes", nodes, true)
	undo_redo.add_undo_method(Utils, "hide_nodes", nodes, false)
	undo_redo.commit_action()


## Opens a popup dialog to confirm deletion of selected nodes.
func confirm_delete_selected_nodes() -> void:
	var selected_nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty():
		return

	var editor_theme := EditorInterface.get_base_control().theme
	var popup := ConfirmationDialog.new()
	popup.theme = editor_theme

	# Setting dialog text dynamically depending on the selection to mimick Godot's normal behavior.
	popup.dialog_text = "Delete "
	var selection_size := selected_nodes.size()
	if selection_size == 1:
		popup.dialog_text += selected_nodes[0].get_name()
	elif selection_size > 1:
		popup.dialog_text += str(selection_size) + " nodes"

	for node in selected_nodes:
		if node.get_child_count() > 0:
			popup.dialog_text += " and children"
			break

	popup.dialog_text += "?"

	add_child(popup)
	popup.popup_centered()
	if popup.canceled.connect(popup.queue_free) != OK:
		push_error("Failed to connect canceled signal to popup")

	if popup.confirmed.connect(delete_selected_nodes) != OK:
		push_error("Failed to connect confirmed signal to popup")

	if popup.confirmed.connect(popup.queue_free) != OK:
		push_error("Failed to connect confirmed signal to popup")


## Instantly deletes selected nodes and creates an undo history entry.
func delete_selected_nodes() -> void:
	var undo_redo := get_undo_redo()
	var selected_nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	# Avoid creating an unnecessary history entry if no nodes are selected.
	if selected_nodes.is_empty():
		return

	undo_redo.create_action("Delete Nodes", UndoRedo.MERGE_DISABLE)
	for node in selected_nodes:
		# We can't free nodes, they must be kept in memory for undo to work.
		# That's why we use remove_child instead and call UndoRedo.add_undo_reference() below.
		undo_redo.add_do_method(node.get_parent(), "remove_child", node)
		undo_redo.add_undo_method(node.get_parent(), "add_child", node, true)
		undo_redo.add_undo_method(node.get_parent(), "move_child", node, node.get_index())
		# Every node's owner must be set upon undoing, otherwise, it won't appear in the scene dock
		# and it'll be lost upon saving.
		undo_redo.add_undo_method(node, "set_owner", node.owner)
		for child in Utils.recursive_get_children(node):
			undo_redo.add_undo_method(child, "set_owner", node.owner)

		undo_redo.add_undo_reference(node)

	undo_redo.commit_action()


func revert() -> void:
	var nodes: Array[Node] = EditorInterface.get_selection().get_transformable_selected_nodes()
	Utils.revert_transform(nodes, _cache_global_transforms)
	_editing_transform = Transform3D.IDENTITY
	_applying_transform = Transform3D.IDENTITY
	_last_world_pos = Vector3.ZERO
	axis_im.clear_surfaces()


func clear_session() -> void:
	current_session = Session.NONE
	constraint_axis = Vector3.ONE
	pivot_point = Vector3.ZERO
	precision_mode = false
	_editing_transform = Transform3D.IDENTITY
	_applying_transform = Transform3D.IDENTITY
	_last_world_pos = Vector3.ZERO
	_init_angle = NAN
	_last_angle = 0.0
	_last_center_offset = 0.0
	_cummulative_center_offset = 0.0
	_max_x = 0.0
	_min_x = 0.0
	_cache_global_transforms = []
	_cache_transforms = []
	_input_string = ""
	_is_warping_mouse = false
	axis_im.clear_surfaces()


func sync_settings() -> void:
	if translate_snap_line_edit:
		translate_snap = translate_snap_line_edit.text.to_float()

	if rotate_snap_line_edit:
		rotate_snap = deg_to_rad(rotate_snap_line_edit.text.to_float())

	if scale_snap_line_edit:
		scale_snap = scale_snap_line_edit.text.to_float() / 100.0

	if local_space_button:
		is_global = not local_space_button.button_pressed

	if snap_button:
		is_snapping = snap_button.button_pressed


func _switch_display_mode(debug_draw: Viewport.DebugDraw) -> void:
	var spatial_editor_viewport := Utils.get_focused_spatial_editor_viewport(spatial_editor_viewports)
	if is_instance_valid(spatial_editor_viewport):
		var viewport := Utils.get_spatial_editor_viewport_viewport(spatial_editor_viewport)
		viewport.debug_draw = debug_draw


# Repeatedly applying same axis will results in toggling is_global
# (just like pressing xx, yy or zz in blender)
func toggle_constraint_axis(axis: Vector3) -> void:
	# Following order as below:
	# 1) Apply constraint on current mode
	# 2) Toggle mode
	# 3) Toggle mode again, and remove constraint
	if is_global == _is_global_on_session:
		if not constraint_axis.is_equal_approx(axis):
			# 1
			_set_constraint_axis(axis)
		else:
			# 2
			_set_is_global(!_is_global_on_session)
	else:
		if constraint_axis.is_equal_approx(axis):
			# 3
			_set_is_global(_is_global_on_session)
			_set_constraint_axis(Vector3.ONE)
		else:
			# Others situation
			_set_constraint_axis(axis)


func _toggle_input_string_sign() -> void:
	if _input_string.begins_with("-"):
		_input_string = _input_string.trim_prefix("-")
	else:
		_input_string = "-" + _input_string

	_input_string_changed()


func _trim_input_string() -> void:
	_input_string = _input_string.substr(0, _input_string.length() - 1)
	_input_string_changed()


func _append_input_string(text: String) -> bool:
	text = "." if text == "Period" else text
	if text.is_valid_int() or text == ".":
		_input_string += text
		_input_string_changed()
		return true

	return false


func _input_string_changed() -> void:
	if not _input_string.is_empty():
		text_transform(_input_string)
	else:
		_applying_transform = Transform3D.IDENTITY
		var nodes: Array[Node] = EditorInterface.get_selection().get_transformable_selected_nodes()
		Utils.revert_transform(nodes, _cache_global_transforms)

	@warning_ignore("return_value_discarded")
	update_overlays()


func _get_constraint_axis_count() -> int:
	var axis_count := 3
	if is_zero_approx(constraint_axis.x):
		axis_count -= 1

	if is_zero_approx(constraint_axis.y == 0):
		axis_count -= 1

	if is_zero_approx(constraint_axis.z == 0):
		axis_count -= 1

	return axis_count


func _set_constraint_axis(v: Vector3) -> void:
	revert()
	if constraint_axis != v:
		constraint_axis = v
		_draw_axises()
	else:
		constraint_axis = Vector3.ONE

	if not _input_string.is_empty():
		text_transform(_input_string)

	@warning_ignore("return_value_discarded")
	update_overlays()


func _set_is_global(v: bool) -> void:
	if is_global == v:
		return

	if is_instance_valid(local_space_button):
		local_space_button.button_pressed = not v

	revert()
	is_global = v
	_draw_axises()
	if not _input_string.is_empty():
		text_transform(_input_string)

	@warning_ignore("return_value_discarded")
	update_overlays()


func _draw_axises() -> void:
	if not constraint_axis.is_equal_approx(Vector3.ONE):
		var nodes := EditorInterface.get_selection().get_transformable_selected_nodes()
		# Array[Dictionary[String, Variant]]
		var axis_lines: Array[Dictionary] = []
		if constraint_axis.x > 0:
			axis_lines.append({"axis": Vector3.RIGHT, "color": Color.RED})
		if constraint_axis.y > 0:
			axis_lines.append({"axis": Vector3.UP, "color": Color.GREEN})
		if constraint_axis.z > 0:
			axis_lines.append({"axis": Vector3.BACK, "color": Color.BLUE})

		for axis_line in axis_lines:
			var axis: Vector3 = axis_line.get("axis")
			var color: Color = axis_line.get("color")
			if is_global:
				var is_pivot_point_behind_camera := _camera.is_position_behind(pivot_point)
				var axis_origin := pivot_point
				if is_pivot_point_behind_camera:
					axis_origin = _camera.global_transform.origin - _camera.global_transform.basis.z * 10.0

				Utils.draw_axis(axis_im, axis_origin, axis, axis_length, color)
			else:
				for node: Node3D in nodes:
					var global_transform := node.global_transform
					var origin := global_transform.origin
					var basis := global_transform.basis
					Utils.draw_axis(axis_im, origin, basis * axis, axis_length, color)
