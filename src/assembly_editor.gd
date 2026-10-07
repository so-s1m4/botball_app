extends Window
signal assembly_changed(assembly: Array)
const Connections = preload("res://src/assembly_connections.gd")
const Library = preload("res://src/part_library.gd")
const Easy = preload("res://src/easy_assembly.gd")
var assembly: Array = []
var catalog_ids: Array[String] = []
var catalog: ItemList
var installed: ItemList
var search: LineEdit
var category: OptionButton
var details: Label
var count_label: Label
var add_button: Button
var remove_button: Button
var fields: Array[SpinBox] = []
var view: SubViewportContainer
var camera: Camera3D
var model_root: Node3D
var selection_root: Node3D
var selected := -1
var catalog_id := ""
var syncing := false
var previewing := false
var own_port: OptionButton
var target_part: OptionButton
var target_port: OptionButton
var twist: SpinBox
var connect_button: Button
var detach_button: Button
var connection_status: Label
var connection_mode: CheckButton
var port_root: Node3D
var picked_ports: Array = []
var advanced: VBoxContainer
var advanced_toggle: CheckButton
var simple_hint: Label
var step_tabs: HBoxContainer
var simple_tools: HBoxContainer
var step_buttons: Array[Button] = []
var simple_group := 0
var pending_id := ""
var pending_twist := 0.0
var ghost_root: Node3D
var simple_targets: Array = []
var undo_history: Array = []
var undo_button: Button
var fasten_button: Button
var hover_target := -1
var orbit := 0.5
var elevation := 0.6
var zoom := 0.65
var target := Vector3(0, 0.08, 0)

func _ready() -> void:
	Library.ensure_loaded()
	title = "Конструктор · Botball 2026"
	size = Vector2i(1100, 860)
	min_size = Vector2i(1000, 780)
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	margin.add_child(columns)
	var inventory := VBoxContainer.new()
	inventory.custom_minimum_size.x = 332
	columns.add_child(inventory)
	inventory.add_child(caption("ДЕТАЛИ НАБОРА 2026"))
	search = LineEdit.new()
	search.placeholder_text = "Название или артикул…"
	search.text_changed.connect(func(_text): refresh_catalog())
	inventory.add_child(search)
	category = OptionButton.new()
	for text in ["Все детали", "LEGO", "Металл", "Электроника"]:
		category.add_item(text)
	category.item_selected.connect(func(_index): refresh_catalog())
	inventory.add_child(category)
	step_tabs = HBoxContainer.new()
	inventory.add_child(step_tabs)
	for i in range(Easy.GROUPS.size()):
		var tab := action(Easy.GROUPS[i], choose_step.bind(i))
		tab.add_theme_font_size_override("font_size", 11)
		tab.toggle_mode = true
		step_buttons.append(tab)
		step_tabs.add_child(tab)
	step_buttons[0].button_pressed = true
	category.visible = false
	catalog = ItemList.new()
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.custom_minimum_size.y = 160
	catalog.max_columns = 2
	catalog.same_column_width = true
	catalog.fixed_column_width = 148
	catalog.icon_mode = ItemList.ICON_MODE_TOP
	catalog.fixed_icon_size = Vector2i(140, 104)
	catalog.max_text_lines = 3
	catalog.add_theme_font_size_override("font_size", 12)
	catalog.item_selected.connect(select_catalog)
	inventory.add_child(catalog)
	details = caption("Выбери деталь для просмотра в 3D")
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.add_child(details)
	add_button = action("Добавить в сборку", add_part)
	inventory.add_child(add_button)
	inventory.add_child(caption("СОБРАНО"))
	installed = ItemList.new()
	installed.custom_minimum_size.y = 150
	installed.fixed_icon_size = Vector2i(64, 48)
	installed.item_selected.connect(select_installed)
	inventory.add_child(installed)
	remove_button = action("Удалить выбранную деталь", remove_part)
	inventory.add_child(remove_button)
	var workspace := VBoxContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(workspace)
	count_label = caption("")
	workspace.add_child(count_label)
	view = SubViewportContainer.new()
	view.stretch = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(400, 300)
	workspace.add_child(view)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(650, 440)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("152234")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("dbe7f3")
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	world.add_child(light)
	model_root = Node3D.new()
	world.add_child(model_root)
	selection_root = Node3D.new()
	world.add_child(selection_root)
	port_root = Node3D.new()
	world.add_child(port_root)
	ghost_root = Node3D.new()
	world.add_child(ghost_root)
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-30,31):
		grid.surface_add_vertex(Vector3(i*.008,-.001,-.24))
		grid.surface_add_vertex(Vector3(i*.008,-.001,.24))
		grid.surface_add_vertex(Vector3(-.24,-.001,i*.008))
		grid.surface_add_vertex(Vector3(.24,-.001,i*.008))
	grid.surface_end()
	var grid_visual := MeshInstance3D.new()
	grid_visual.mesh = grid
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color("355268")
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_visual.material_override = grid_mat
	world.add_child(grid_visual)
	camera = Camera3D.new()
	camera.near = .001
	camera.fov = 42
	camera.current = true
	world.add_child(camera)
	view.gui_input.connect(camera_input)
	workspace.add_child(caption("Нажми на зелёное место — поставить деталь · ПКМ — осмотреть"))
	simple_hint = caption("1. Выбери платформу на картинке и нажми «Взять платформу».")
	simple_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	simple_hint.add_theme_font_size_override("font_size", 18)
	workspace.add_child(simple_hint)
	simple_tools = HBoxContainer.new()
	workspace.add_child(simple_tools)
	simple_tools.add_child(action("Перевернуть", flip_assembly))
	simple_tools.add_child(action("Повернуть", turn_pending))
	fasten_button = action("Прикрутить мотор", fasten_selected)
	simple_tools.add_child(fasten_button)
	undo_button = action("Отмена шага", undo_step)
	simple_tools.add_child(undo_button)
	simple_tools.add_child(action("Отложить", cancel_pending))
	for tool in simple_tools.get_children():
		tool.add_theme_font_size_override("font_size", 14)
		tool.custom_minimum_size.y = 36
	advanced_toggle = CheckButton.new()
	advanced_toggle.text = "Дополнительно: координаты и отдельные крепления"
	advanced_toggle.toggled.connect(toggle_advanced)
	workspace.add_child(advanced_toggle)
	advanced = VBoxContainer.new()
	advanced.visible = false
	workspace.add_child(advanced)
	connection_mode = CheckButton.new()
	connection_mode.text = "Сборка по креплениям (свободное размещение — выключить)"
	connection_mode.button_pressed = true
	connection_mode.toggled.connect(func(_enabled): mark_ports())
	advanced.add_child(connection_mode)
	var own_row := HBoxContainer.new()
	advanced.add_child(own_row)
	own_row.add_child(caption("Крепление выбранной детали"))
	own_port = OptionButton.new()
	own_port.clip_text = true
	own_port.custom_minimum_size.x = 150
	own_port.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	own_port.item_selected.connect(func(_index): twist.value = 0; refresh_destinations())
	own_row.add_child(own_port)
	var target_row := HBoxContainer.new()
	advanced.add_child(target_row)
	target_row.add_child(caption("Соединить с"))
	target_part = OptionButton.new()
	target_part.clip_text = true
	target_part.custom_minimum_size.x = 150
	target_part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_part.item_selected.connect(func(_index): refresh_target_ports())
	target_row.add_child(target_part)
	target_port = OptionButton.new()
	target_port.clip_text = true
	target_port.custom_minimum_size.x = 150
	target_port.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_port.item_selected.connect(func(_index): update_connection_actions())
	target_row.add_child(target_port)
	var attach_row := HBoxContainer.new()
	advanced.add_child(attach_row)
	attach_row.add_child(caption("Угол вокруг крепления, °"))
	twist = SpinBox.new()
	twist.min_value = -180
	twist.max_value = 180
	twist.step = 90
	attach_row.add_child(twist)
	connect_button = action("Соединить", attach_selected)
	attach_row.add_child(connect_button)
	detach_button = action("Отсоединить", detach_selected)
	attach_row.add_child(detach_button)
	connection_status = caption("Добавь основание, затем пин, ось или винт и выбери точки крепления.")
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advanced.add_child(connection_status)
	var show_button := action("Показать всю сборку", func(): cancel_pending(); frame_assembly())
	workspace.add_child(show_button)
	for key in ["Положение, мм", "Поворот, °"]:
		var row := HBoxContainer.new()
		advanced.add_child(row)
		row.add_child(caption(key))
		for axis in ["X", "Y", "Z"]:
			row.add_child(caption(axis))
			var field := SpinBox.new()
			field.min_value = -600 if fields.size() < 3 else -360
			field.max_value = 600 if fields.size() < 3 else 360
			field.step = 0.1 if fields.size() < 3 else 15
			field.custom_minimum_size.x = 85
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fields.append(field)
			field.value_changed.connect(transform_selected)
			row.add_child(field)
	var hint := caption("Модели: LDraw.org и KIPR Simulator. Остальные помечены как приближённые.\nЦветные точки — крепления; соединённые детали перемещаются вместе.\nКрепления металла приближённые. Физика поля использует учебный корпус и захват.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advanced.add_child(hint)
	refresh_catalog()
	refresh_installed()
	refresh_connections()
	show_assembly()

func set_assembly(value: Array) -> void:
	cancel_pending(false)
	undo_history.clear()
	assembly = value.duplicate(true)
	selected = -1
	refresh_connections()
	refresh_catalog()
	refresh_installed()
	show_assembly()

func used(id: String) -> int:
	var count := 0
	for entry in assembly:
		if entry.id == id:
			count += 1
	return count

func refresh_catalog() -> void:
	catalog.clear()
	catalog_ids.clear()
	var groups := ["", "lego", "metal", "electronics"]
	var visible_parts: Array = Library.parts.duplicate()
	if not advanced_toggle.button_pressed and simple_group == 0:
		visible_parts.sort_custom(func(a, b): return a.id == "metal_007" and b.id != "metal_007")
	for part in visible_parts:
		if not part.usable_on_robot or not Library.models.has(part.id):
			continue
		if category.selected > 0 and part.group != groups[category.selected]:
			continue
		if not advanced_toggle.button_pressed and not Easy.in_group(part, simple_group):
			continue
		if not search.text.is_empty() and not (part.name + " " + part.id).to_lower().contains(search.text.to_lower()):
			continue
		var remaining: int = part.quantity - used(part.id)
		catalog_ids.append(part.id)
		catalog.add_item("%s\n%d / %d в наборе" % [Easy.display_name(part.id), remaining, part.quantity], Library.thumbnail(part.id))
		catalog.set_item_tooltip(catalog.item_count-1, part.name + "\n" + part.id + "\n" + ("Приближённая модель" if Library.models[part.id].quality == "estimated" else "Модель " + Library.models[part.id].quality.to_upper()))
		if remaining == 0:
			catalog.set_item_custom_fg_color(catalog.item_count-1, Color("8793a0"))
		if part.id == catalog_id:
			catalog.select(catalog.item_count-1)
	update_actions()

func select_catalog(index: int) -> void:
	catalog_id = catalog_ids[index]
	var part := Library.find_part(catalog_id)
	var meta: Dictionary = Library.models[catalog_id]
	var dims: Array = meta.size
	details.text = "%s\n%.1f × %.1f × %.1f мм\n%s" % [Easy.display_name(part.id),dims[0]*1000,dims[1]*1000,dims[2]*1000,"Модель LDraw" if meta.quality == "ldraw" else "Модель KIPR" if meta.quality == "kipr" else "Приближённая модель"]
	if not advanced_toggle.button_pressed and not assembly.is_empty():
		pending_id = catalog_id
		pending_twist = 0
		show_assembly(false)
		refresh_simple_targets()
		return
	Library.populate(model_root, [{"id":catalog_id,"position":[0,0,0],"rotation":[0,0,0]}])
	previewing = true
	count_label.text = "Просмотр детали: " + part.name
	clear_selection()
	mark_ports()
	target = Vector3(0, dims[1]/2, 0)
	zoom = maxf(.04, maxf(dims[0], maxf(dims[1], dims[2]))*2.4)
	update_camera()
	update_actions()

func add_part() -> void:
	if catalog_id.is_empty():
		return
	var part := Library.find_part(catalog_id)
	if used(catalog_id) >= part.quantity:
		return
	remember_step()
	cancel_pending(false)
	var entry := {"id":catalog_id,"position":[0.0,0.0,0.0],"rotation":[0.0,0.0,0.0]}
	if selected >= 0 and selected < assembly.size():
		entry.position = assembly[selected].position.duplicate()
		entry.position[0] += (Library.models[assembly[selected].id].size[0] + Library.models[catalog_id].size[0])/2 + .016
		entry.position[0] = clampf(entry.position[0], -.5, .5)
	assembly.append(entry)
	selected = assembly.size()-1
	commit()
	select_installed(selected)
	if not advanced_toggle.button_pressed:
		frame_assembly()
		if assembly.size() == 1:
			choose_step(1)
			simple_hint.text = "2. Выбери мотор. Зелёные места покажут, куда его поставить."

func remove_part() -> void:
	if selected < 0:
		return
	remember_step()
	cancel_pending(false)
	Connections.remove(assembly, selected)
	selected = mini(selected,assembly.size()-1)
	commit()
	if selected >= 0:
		select_installed(selected)
	else:
		show_assembly()

func commit() -> void:
	refresh_catalog()
	refresh_installed()
	refresh_connections()
	show_assembly(false)
	assembly_changed.emit(assembly.duplicate(true))

func refresh_installed() -> void:
	installed.clear()
	for entry in assembly:
		installed.add_item(Easy.display_name(entry.id), Library.thumbnail(entry.id))
	count_label.text = "Сборка: %d деталей" % assembly.size()
	update_actions()

func select_installed(index: int) -> void:
	cancel_pending(false)
	selected = index
	installed.select(index)
	syncing = true
	for i in range(3):
		fields[i].value = assembly[index].position[i]*1000
		fields[i+3].value = assembly[index].rotation[i]
	syncing = false
	refresh_connections()
	show_assembly(false)
	var p: Array = assembly[index].position
	target = Vector3(p[0],p[1],p[2])
	update_camera()
	update_actions()
	update_simple_hint()

func transform_selected(_value: float) -> void:
	if syncing or selected < 0:
		return
	var backup := assembly.duplicate(true)
	var position := Vector3(fields[0].value, fields[1].value, fields[2].value)/1000
	var rotation := Vector3(fields[3].value, fields[4].value, fields[5].value)*PI/180
	Connections.move_group(assembly, selected, Transform3D(Basis.from_euler(rotation), position))
	var error := Library.validate(assembly)
	if not error.is_empty():
		assembly = backup
		select_installed(selected)
		connection_status.text = error
		return
	Library.populate(model_root,assembly)
	previewing = false
	mark_selection()
	mark_ports()
	assembly_changed.emit(assembly.duplicate(true))

func show_assembly(reset_camera: bool = true) -> void:
	previewing = false
	Library.populate(model_root,assembly)
	if reset_camera:
		target = Vector3(0,.05,0)
		zoom = .65
	count_label.text = "Сборка: %d деталей" % assembly.size()
	update_actions()
	mark_selection()
	mark_ports()
	update_camera()
	if not pending_id.is_empty():
		refresh_simple_targets()

func clear_selection() -> void:
	for child in selection_root.get_children():
		selection_root.remove_child(child)
		child.queue_free()

func mark_selection() -> void:
	clear_selection()
	if selected < 0 or selected >= assembly.size():
		return
	var entry: Dictionary = assembly[selected]
	var dims: Array = Library.models[entry.id].size
	var bounds := Vector3(dims[0],dims[1],dims[2]) + Vector3.ONE*.001
	var edges := ImmediateMesh.new()
	edges.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in range(3):
		for first in [-1,1]:
			for second in [-1,1]:
				for sign_value in [-1,1]:
					var point := Vector3.ZERO
					point[axis] = sign_value*bounds[axis]/2
					point[(axis+1)%3] = first*bounds[(axis+1)%3]/2
					point[(axis+2)%3] = second*bounds[(axis+2)%3]/2
					edges.surface_add_vertex(point + Vector3(0,dims[1]/2,0))
	edges.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = edges
	visual.position = Vector3(entry.position[0],entry.position[1],entry.position[2])
	visual.rotation_degrees = Vector3(entry.rotation[0],entry.rotation[1],entry.rotation[2])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("51e9c2")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = mat
	selection_root.add_child(visual)

func update_actions() -> void:
	add_button.disabled = catalog_id.is_empty() or used(catalog_id) >= Library.find_part(catalog_id).get("quantity",0)
	remove_button.disabled = selected < 0
	if advanced_toggle != null and not advanced_toggle.button_pressed:
		add_button.text = "Взять платформу" if assembly.is_empty() else "Положить рядом"
	else:
		add_button.text = "Добавить в сборку"
	if undo_button != null:
		undo_button.disabled = undo_history.is_empty()
	if fasten_button != null:
		fasten_button.disabled = selected < 0 or assembly[selected].id != "electronics_010" or Easy.fastening_ports(assembly, selected).is_empty()
	for field in fields:
		field.editable = selected >= 0 and not previewing

func camera_input(event: InputEvent) -> void:
	if not advanced_toggle.button_pressed:
		if event is InputEventMouseMotion and not pending_id.is_empty():
			preview_simple_target(event.position)
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not pending_id.is_empty():
				var nearest := nearest_simple_target(event.position)
				if nearest >= 0:
					place_simple(nearest)
				else:
					simple_hint.text = "Нажми на зелёное место. Колёсиком можно приблизить сборку."
			else:
				select_in_scene(event.position)
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and selected >= 0 and not previewing and advanced_toggle.button_pressed:
		if connection_mode.button_pressed:
			pick_port(event.position)
			return
		var viewport_position: Vector2 = event.position * Vector2(view.get_child(0).size) / view.size
		var origin := camera.project_ray_origin(viewport_position)
		var direction := camera.project_ray_normal(viewport_position)
		var placement = Plane(Vector3.UP, assembly[selected].position[1]).intersects_ray(origin,direction)
		if placement != null:
			syncing = true
			fields[0].value = clampf(snappedf(placement.x,.008)*1000,-600,600)
			fields[2].value = clampf(snappedf(placement.z,.008)*1000,-600,600)
			syncing = false
			transform_selected(0)
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		orbit -= event.relative.x*.008
		elevation = clampf(elevation+event.relative.y*.008,-1.5,1.5)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(.015,zoom*.85)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(3,zoom/ .85)
	update_camera()

func update_camera() -> void:
	camera.position = target + Vector3(sin(orbit)*cos(elevation),sin(elevation),cos(orbit)*cos(elevation))*zoom
	camera.look_at(target)

func caption(text: String) -> Label:
	var result := Label.new()
	result.text = text
	return result

func action(text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(callback)
	return result

func port_label(port: Dictionary, index: int) -> String:
	return "%d · %s%s" % [index+1, Connections.LABELS.get(port.kind, port.kind), " ≈" if port.quality == "estimated" else ""]

func refresh_connections() -> void:
	own_port.clear()
	twist.value = 0
	if selected >= 0:
		var ports := Connections.for_part(assembly[selected].id)
		for i in range(ports.size()):
			own_port.add_item(port_label(ports[i], i), i)
			own_port.set_item_disabled(i, Connections.occupied(assembly, selected, i))
		for i in range(ports.size()):
			if not own_port.is_item_disabled(i):
				own_port.select(i)
				break
	refresh_destinations()

func refresh_destinations() -> void:
	if own_port.selected >= 0:
		var kind: String = Connections.for_part(assembly[selected].id)[own_port.selected].kind
		twist.step = 90 if kind in ["axle", "axle_hole", "stud", "stud_socket"] else 15
	var previous := target_part.get_selected_id()
	target_part.clear()
	if selected >= 0 and own_port.item_count > 0:
		for i in range(assembly.size()):
			if i == selected or Connections.for_part(assembly[i].id).is_empty():
				continue
			target_part.add_item("%d · %s" % [i+1, Library.find_part(assembly[i].id).name], i)
			if i == previous:
				target_part.select(target_part.item_count-1)
	refresh_target_ports()

func refresh_target_ports() -> void:
	target_port.clear()
	var other := target_part.get_selected_id()
	if selected >= 0 and other >= 0 and own_port.item_count > 0:
		var own: Dictionary = Connections.for_part(assembly[selected].id)[own_port.selected]
		var ports := Connections.for_part(assembly[other].id)
		for i in range(ports.size()):
			if Connections.compatible(own.kind, ports[i].kind) and not Connections.occupied(assembly, other, i):
				target_port.add_item(port_label(ports[i], i), i)
	update_connection_actions()

func update_connection_actions() -> void:
	connect_button.disabled = selected < 0 or own_port.selected < 0 or target_port.item_count == 0
	if selected >= 0 and own_port.selected >= 0:
		connect_button.disabled = connect_button.disabled or own_port.is_item_disabled(own_port.selected)
	detach_button.disabled = selected < 0 or assembly[selected].get("links", []).is_empty()
	if selected < 0:
		connection_status.text = "Добавь основание, затем следующую деталь."
	elif own_port.item_count == 0:
		connection_status.text = "Для этой детали крепления ещё не размечены. Доступно свободное размещение."
	else:
		connection_status.text = "Соединений: %d · В группе: %d деталей. Выбери крепление и оранжевую точку, затем «Соединить»." % [assembly[selected].get("links", []).size(), Connections.component(assembly, selected).size()]
	mark_ports()

func attach_selected() -> void:
	if connect_button.disabled:
		return
	var error := Connections.connect_parts(assembly, selected, own_port.selected, target_part.get_selected_id(), target_port.get_selected_id(), twist.value)
	if not error.is_empty():
		connection_status.text = error
		return
	commit()
	select_installed(selected)
	connection_status.text = "Соединено. Группа перемещается вместе; для отдельной детали нажми «Отсоединить»."

func detach_selected() -> void:
	if selected < 0:
		return
	Connections.detach(assembly, selected)
	commit()
	connection_status.text = "Деталь отсоединена; крепления свободны."

func mark_ports() -> void:
	if advanced_toggle != null and not advanced_toggle.button_pressed:
		refresh_simple_targets()
		return
	if port_root == null:
		return
	for child in port_root.get_children():
		port_root.remove_child(child)
		child.queue_free()
	picked_ports.clear()
	if previewing or selected < 0 or own_port == null or not connection_mode.button_pressed:
		return
	var group := Connections.component(assembly, selected)
	var source_kind := ""
	if own_port.selected >= 0:
		source_kind = Connections.for_part(assembly[selected].id)[own_port.selected].kind
	for i in range(assembly.size()):
		var ports := Connections.for_part(assembly[i].id)
		for j in range(ports.size()):
			if Connections.occupied(assembly, i, j):
				continue
			if i != selected and (not Connections.compatible(source_kind, ports[j].kind)):
				continue
			var point: Vector3 = Connections.world_port(assembly[i], j).position
			if i != selected and group.has(i) and point.distance_to(Connections.world_port(assembly[selected], own_port.selected).position) > .0001:
				continue
			var visual := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = .0014
			sphere.height = .0028
			sphere.radial_segments = 8
			sphere.rings = 4
			visual.mesh = sphere
			visual.position = point
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color("51e9c2") if i == selected else Color("ffb35a")
			if i == selected and j == own_port.selected:
				mat.albedo_color = Color.WHITE
			if i == target_part.get_selected_id() and j == target_port.get_selected_id():
				mat.albedo_color = Color("ff655a")
			visual.material_override = mat
			port_root.add_child(visual)
			picked_ports.append({"part":i, "port":j, "position":point})

func pick_port(mouse_position: Vector2) -> void:
	var viewport_position := mouse_position * Vector2(view.get_child(0).size) / view.size
	var nearest: Dictionary = {}
	var best := 14.0 * Vector2(view.get_child(0).size).x/view.size.x
	for candidate in picked_ports:
		if camera.is_position_behind(candidate.position):
			continue
		var distance := camera.unproject_position(candidate.position).distance_to(viewport_position)
		if distance < best:
			best = distance
			nearest = candidate
	if nearest.is_empty():
		connection_status.text = "Нажми на цветную точку крепления или выбери её в списке."
		return
	if nearest.part == selected:
		own_port.select(nearest.port)
		refresh_destinations()
	else:
		for i in range(target_part.item_count):
			if target_part.get_item_id(i) == nearest.part:
				target_part.select(i)
				break
		refresh_target_ports()
		for i in range(target_port.item_count):
			if target_port.get_item_id(i) == nearest.port:
				target_port.select(i)
				break
		update_connection_actions()

func choose_step(index: int) -> void:
	simple_group = index
	for i in range(step_buttons.size()):
		step_buttons[i].button_pressed = i == index
	cancel_pending(false)
	refresh_catalog()
	show_assembly(false)
	update_simple_hint()

func toggle_advanced(enabled: bool) -> void:
	cancel_pending(false)
	advanced.visible = enabled
	step_tabs.visible = not enabled
	category.visible = enabled
	simple_hint.visible = not enabled
	simple_tools.visible = not enabled
	refresh_catalog()
	show_assembly(false)

func remember_step() -> void:
	undo_history.append(assembly.duplicate(true))
	if undo_history.size() > 40:
		undo_history.pop_front()

func undo_step() -> void:
	if undo_history.is_empty():
		return
	cancel_pending(false)
	assembly = undo_history.pop_back()
	selected = mini(selected, assembly.size()-1)
	commit()
	frame_assembly()
	update_simple_hint()

func cancel_pending(redraw: bool = true) -> void:
	pending_id = ""
	hover_target = -1
	if ghost_root != null:
		for child in ghost_root.get_children():
			ghost_root.remove_child(child)
			child.queue_free()
	if redraw and model_root != null:
		show_assembly(false)
		update_simple_hint()

func update_simple_hint() -> void:
	if simple_hint == null:
		return
	if assembly.is_empty():
		simple_hint.text = "1. Выбери платформу на картинке и нажми «Взять платформу»."
	elif selected >= 0 and assembly[selected].id == "electronics_010":
		simple_hint.text = "Мотор ещё не прикручен. Нажми «Прикрутить мотор»: возьмём 2 винта из набора." if not Easy.fastening_ports(assembly, selected).is_empty() else "Мотор прикручен. Выбери колёса и нажми на зелёный вал мотора."
	elif simple_group == 1:
		simple_hint.text = "2. Выбери мотор на картинке и нажми на зелёное место платформы."
	elif simple_group == 2:
		simple_hint.text = "3. Выбери колесо Solarbotics и нажми на зелёный вал мотора."
	else:
		simple_hint.text = "Выбери деталь на картинке. Зелёные места покажут подходящие крепления."

func frame_assembly() -> void:
	if assembly.is_empty():
		show_assembly()
		return
	var bounds := assembly_bounds()
	target = bounds.get_center()
	zoom = maxf(.08, bounds.size.length()*1.3)
	update_camera()

func assembly_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for entry in assembly:
		var mesh: Mesh = Library.meshes[entry.id]
		var box: AABB = Connections.transform(entry) * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func flip_assembly() -> void:
	if assembly.is_empty():
		return
	remember_step()
	var before := assembly.duplicate(true)
	var pivot := assembly_bounds().get_center()
	var flip := Transform3D(Basis(Vector3.FORWARD, PI), pivot)
	flip.origin -= flip.basis * pivot
	for entry in assembly:
		Connections.set_transform(entry, flip * Connections.transform(entry))
	var error := Library.validate(assembly)
	if not error.is_empty():
		assembly = before
		undo_history.pop_back()
		simple_hint.text = error
		return
	commit()
	frame_assembly()
	simple_hint.text = "Платформа перевёрнута. Можно крепить детали с другой стороны."

func turn_pending() -> void:
	if pending_id.is_empty():
		simple_hint.text = "Сначала возьми деталь на картинке."
		return
	pending_twist = fmod(pending_twist + 90, 360)
	if hover_target >= 0:
		show_ghost(hover_target)
	simple_hint.text = "Деталь повёрнута на %d°. Нажми на зелёное место." % int(pending_twist)

func refresh_simple_targets() -> void:
	if port_root == null:
		return
	for child in port_root.get_children():
		port_root.remove_child(child)
		child.queue_free()
	simple_targets.clear()
	if pending_id.is_empty():
		return
	simple_targets = Easy.candidates(assembly, pending_id)
	for candidate in simple_targets:
		var visual := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = maxf(.002, zoom*.006)
		sphere.height = sphere.radius * 2
		visual.mesh = sphere
		visual.position = candidate.position
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("51e9a7")
		mat.no_depth_test = true
		visual.material_override = mat
		port_root.add_child(visual)
	if simple_targets.is_empty():
		if pending_id in ["electronics_009", "electronics_011"]:
			simple_hint.text = "Сервомотор пока можно разместить как 3D-деталь. Управление углом ещё не подключено."
		elif pending_id == "electronics_018":
			simple_hint.text = "Свободного вала пока нет. Сначала установи и прикрути мотор."
		else:
			simple_hint.text = "Подходящих креплений пока нет. LEGO-колесу нужна ось; деталь можно положить рядом."
	else:
		simple_hint.text = "В руках: %s. Наведи на зелёное место и нажми — деталь встанет сама." % Easy.display_name(pending_id)

func nearest_simple_target(mouse_position: Vector2) -> int:
	var point := mouse_position * Vector2(view.get_child(0).size) / view.size
	var nearest := -1
	var best := 24.0 * Vector2(view.get_child(0).size).x / view.size.x
	for i in range(simple_targets.size()):
		var position: Vector3 = simple_targets[i].position
		if camera.is_position_behind(position):
			continue
		var distance := camera.unproject_position(position).distance_to(point)
		if distance < best:
			best = distance
			nearest = i
	return nearest

func preview_simple_target(mouse_position: Vector2) -> void:
	var nearest := nearest_simple_target(mouse_position)
	if nearest == hover_target:
		return
	hover_target = nearest
	for child in ghost_root.get_children():
		ghost_root.remove_child(child)
		child.queue_free()
	if nearest >= 0:
		show_ghost(nearest)

func show_ghost(index: int) -> void:
	for child in ghost_root.get_children():
		ghost_root.remove_child(child)
		child.queue_free()
	var preview := assembly.duplicate(true)
	if not Easy.place(preview, pending_id, simple_targets[index], pending_twist).is_empty():
		return
	Library.populate(ghost_root, [preview.back()])
	var mesh: MeshInstance3D = ghost_root.get_child(0).get_child(0)
	mesh.transparency = 0.45

func place_simple(index: int) -> void:
	remember_step()
	var error := Easy.place(assembly, pending_id, simple_targets[index], pending_twist)
	if not error.is_empty():
		undo_history.pop_back()
		simple_hint.text = error
		return
	selected = assembly.size()-1
	cancel_pending(false)
	commit()
	select_installed(selected)
	frame_assembly()
	update_simple_hint()

func fasten_selected() -> void:
	remember_step()
	var index := selected
	var error := Easy.fasten_motor(assembly, index)
	if not error.is_empty():
		undo_history.pop_back()
		simple_hint.text = error
		return
	cancel_pending(false)
	commit()
	selected = index
	choose_step(2)
	update_actions()
	update_simple_hint()

func select_in_scene(mouse_position: Vector2) -> void:
	var point := mouse_position * Vector2(view.get_child(0).size) / view.size
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var nearest := -1
	var best := INF
	for i in range(assembly.size()):
		var inverse := Connections.transform(assembly[i]).affine_inverse()
		var box: AABB = Library.meshes[assembly[i].id].get_aabb()
		var hit = box.intersects_ray(inverse * origin, inverse.basis * direction)
		if hit != null:
			var distance := origin.distance_to(Connections.transform(assembly[i]) * hit)
			if distance < best:
				best = distance
				nearest = i
	if nearest >= 0:
		select_installed(nearest)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_pending()
		set_input_as_handled()
