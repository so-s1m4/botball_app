extends Window
signal assembly_changed(assembly: Array)
const Library = preload("res://src/part_library.gd")
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
var orbit := 0.5
var elevation := 0.6
var zoom := 0.65
var target := Vector3(0, 0.08, 0)

func _ready() -> void:
	Library.ensure_loaded()
	title = "Конструктор · Botball 2026"
	size = Vector2i(1000, 720)
	min_size = Vector2i(850, 600)
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
	inventory.custom_minimum_size.x = 300
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
	catalog = ItemList.new()
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.custom_minimum_size.y = 160
	catalog.item_selected.connect(select_catalog)
	inventory.add_child(catalog)
	details = caption("Выбери деталь для просмотра в 3D")
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.add_child(details)
	add_button = action("Добавить в сборку", add_part)
	inventory.add_child(add_button)
	inventory.add_child(caption("СОБРАНО"))
	installed = ItemList.new()
	installed.custom_minimum_size.y = 130
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
	camera.current = true
	world.add_child(camera)
	view.gui_input.connect(camera_input)
	workspace.add_child(caption("ЛКМ — разместить · ПКМ — камера · колесо — масштаб · сетка 8 мм"))
	var show_button := action("Показать всю сборку", show_assembly)
	workspace.add_child(show_button)
	for key in ["Положение, мм", "Поворот, °"]:
		var row := HBoxContainer.new()
		workspace.add_child(row)
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
	var hint := caption("Модели: LDraw.org и KIPR Simulator. Остальные помечены как приближённые.\nСоединения вручную; физика поля использует учебный корпус и захват.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workspace.add_child(hint)
	refresh_catalog()
	refresh_installed()
	show_assembly()

func set_assembly(value: Array) -> void:
	assembly = value.duplicate(true)
	selected = -1
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
	for part in Library.parts:
		if not part.usable_on_robot or not Library.models.has(part.id):
			continue
		if category.selected > 0 and part.group != groups[category.selected]:
			continue
		if not search.text.is_empty() and not (part.name + " " + part.id).to_lower().contains(search.text.to_lower()):
			continue
		var remaining: int = part.quantity - used(part.id)
		catalog_ids.append(part.id)
		catalog.add_item("%s  ·  %d/%d" % [part.name, remaining, part.quantity])
		catalog.set_item_tooltip(catalog.item_count-1, part.name + "\n" + part.id)
		if part.id == catalog_id:
			catalog.select(catalog.item_count-1)
	update_actions()

func select_catalog(index: int) -> void:
	catalog_id = catalog_ids[index]
	var part := Library.find_part(catalog_id)
	var meta: Dictionary = Library.models[catalog_id]
	var dims: Array = meta.size
	details.text = "%s\n%.1f × %.1f × %.1f мм\n%s" % [part.name,dims[0]*1000,dims[1]*1000,dims[2]*1000,"Модель LDraw" if meta.quality == "ldraw" else "Модель KIPR" if meta.quality == "kipr" else "Приближённая модель"]
	Library.populate(model_root, [{"id":catalog_id,"position":[0,0,0],"rotation":[0,0,0]}])
	previewing = true
	count_label.text = "Просмотр детали: " + part.name
	clear_selection()
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
	var entry := {"id":catalog_id,"position":[0.0,0.0,0.0],"rotation":[0.0,0.0,0.0]}
	if selected >= 0 and selected < assembly.size():
		entry.position = assembly[selected].position.duplicate()
		entry.position[1] += Library.models[assembly[selected].id].size[1]
	assembly.append(entry)
	selected = assembly.size()-1
	commit()
	select_installed(selected)

func remove_part() -> void:
	if selected < 0:
		return
	assembly.remove_at(selected)
	selected = mini(selected,assembly.size()-1)
	commit()
	if selected >= 0:
		select_installed(selected)
	else:
		show_assembly()

func commit() -> void:
	refresh_catalog()
	refresh_installed()
	show_assembly()
	assembly_changed.emit(assembly.duplicate(true))

func refresh_installed() -> void:
	installed.clear()
	for entry in assembly:
		installed.add_item(Library.find_part(entry.id).name)
	count_label.text = "Сборка: %d деталей" % assembly.size()
	update_actions()

func select_installed(index: int) -> void:
	selected = index
	installed.select(index)
	syncing = true
	for i in range(3):
		fields[i].value = assembly[index].position[i]*1000
		fields[i+3].value = assembly[index].rotation[i]
	syncing = false
	show_assembly()
	var p: Array = assembly[index].position
	target = Vector3(p[0],p[1],p[2])
	update_camera()
	update_actions()

func transform_selected(_value: float) -> void:
	if syncing or selected < 0:
		return
	for i in range(3):
		assembly[selected].position[i] = fields[i].value/1000
		assembly[selected].rotation[i] = fields[i+3].value
	Library.populate(model_root,assembly)
	previewing = false
	mark_selection()
	assembly_changed.emit(assembly.duplicate(true))

func show_assembly() -> void:
	previewing = false
	Library.populate(model_root,assembly)
	target = Vector3(0,.05,0)
	zoom = .65
	count_label.text = "Сборка: %d деталей" % assembly.size()
	update_actions()
	mark_selection()
	update_camera()

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
	for field in fields:
		field.editable = selected >= 0 and not previewing

func camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and selected >= 0 and not previewing:
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
		elevation = clampf(elevation+event.relative.y*.008,.08,1.5)
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
