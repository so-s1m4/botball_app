extends Control

const MapLoader = preload("res://src/map_loader.gd")
const Simulation = preload("res://src/simulation.gd")
const RobotFiles = preload("res://src/robot_files.gd")
var robot_files: Node
const Store = preload("res://src/project_store.gd")
const UpdateChecker = preload("res://src/update_checker.gd")
var update_checker: Node
const ProgramEditor = preload("res://src/program_editor.gd")
const AssemblyEditor = preload("res://src/assembly_editor.gd")
var assembly_editor: Window
var sim: Node3D
var viewport: SubViewport
var view_container: SubViewportContainer
var status_label: Label
var score_label: Label
var timer_label: Label
var telemetry_label: Label
var stage_label: Label
var log_text: RichTextLabel
var pause_button: Button
var speed_input: SpinBox
var base_input: SpinBox
var noise_input: SpinBox
var seed_input: SpinBox
var save_dialog: FileDialog
var open_dialog: FileDialog
var inputs: Array[SpinBox] = []
var map_dialog: FileDialog
var map_selector: OptionButton
var map_name: Label
var map_options: VBoxContainer
var map_fit: CheckButton
var map_scale: SpinBox
var syncing_map := false
var program_editor: Window
var actuator_panel: VBoxContainer
var hardware_label: Label
var status_dirty := false
var status_elapsed := 0.0
var current_program: String = ProgramEditor.EXAMPLES[0]

func _ready() -> void:
	build_theme()
	var background := ColorRect.new()
	background.color = Color("191d23")
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var header := HFlowContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var title := label("BOTBALL  /  LAB", 26)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(label("v" + str(ProjectSettings.get_setting("application/config/version")), 13, Color("51d8bb")))
	header.add_child(button("3D-конструктор", open_constructor))
	header.add_child(button("Код робота", open_program_editor))
	update_checker = UpdateChecker.new()
	add_child(update_checker)
	var file_menu := MenuButton.new()
	file_menu.text = "Файл"
	header.add_child(file_menu)
	for item in ["Импорт робота…", "Экспорт робота…", "Открыть проект…", "Сохранить проект…", "Обновления"]:
		file_menu.get_popup().add_item(item)
	file_menu.get_popup().id_pressed.connect(func(id):
		match id:
			0: robot_files.import_robot()
			1: robot_files.export_robot(sim.robot.assembly)
			2: open_dialog.popup_centered_ratio(0.7)
			3: save_dialog.popup_centered_ratio(0.7)
			4: update_checker.check()
	)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.add_child(left)
	var info := HFlowContainer.new()
	left.add_child(info)
	map_selector = OptionButton.new()
	for name in ["Учебный стол", "Полоса препятствий", "Своя карта (.glb)…"]:
		map_selector.add_item(name)
	map_selector.size_flags_horizontal = SIZE_EXPAND_FILL
	map_selector.item_selected.connect(select_map)
	info.add_child(map_selector)
	status_label = label("Готов к запуску", 14, Color("51d8bb"))
	info.add_child(status_label)
	view_container = SubViewportContainer.new()
	view_container.stretch = true
	view_container.focus_mode = Control.FOCUS_ALL
	view_container.size_flags_horizontal = SIZE_EXPAND_FILL
	view_container.size_flags_vertical = SIZE_EXPAND_FILL
	view_container.custom_minimum_size = Vector2(480, 360)
	left.add_child(view_container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.physics_object_picking = false
	view_container.add_child(viewport)
	sim = Simulation.new()
	viewport.add_child(sim)
	view_container.gui_input.connect(camera_input)
	var camera_hint := label("Камера: ПКМ — вращать · Shift+ПКМ — сдвиг · колесо — приблизить · F — робот", 13, Color("93a9bd"))
	camera_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(camera_hint)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 360
	sidebar.add_theme_constant_override("separation", 10)
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size.x = 376
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(sidebar_scroll)
	sidebar_scroll.add_child(sidebar)
	sidebar.size_flags_horizontal = SIZE_EXPAND_FILL
	map_name = label("Учебный стол · 3 × 2,4 м", 13, Color("93a9bd"))
	map_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(map_name)
	map_options = VBoxContainer.new()
	map_options.visible = false
	sidebar.add_child(map_options)
	map_fit = CheckButton.new()
	map_fit.text = "Вписать карту в размер стола"
	map_fit.button_pressed = true
	map_fit.toggled.connect(func(_value): adjust_map())
	map_options.add_child(map_fit)
	var scale_row := HBoxContainer.new()
	map_options.add_child(scale_row)
	scale_row.add_child(label("Масштаб карты", 13))
	map_scale = SpinBox.new()
	map_scale.min_value = .001
	map_scale.max_value = 10000
	map_scale.step = .01
	map_scale.value = 1
	map_scale.value_changed.connect(func(_value): adjust_map())
	scale_row.add_child(map_scale)
	hardware_label = label("",13,Color("51d8bb"))
	hardware_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actuator_panel = VBoxContainer.new()
	sidebar.add_child(actuator_panel)
	sidebar.add_child(label("ПОПЫТКА", 13, Color("93a9bd")))
	var stats := HBoxContainer.new()
	sidebar.add_child(stats)
	score_label = label("0 / 100", 30, Color("51d8bb"))
	score_label.size_flags_horizontal = SIZE_EXPAND_FILL
	stats.add_child(score_label)
	timer_label = label("60.0 с", 26)
	stats.add_child(timer_label)
	var task := label("Захвати оранжевый куб и отпусти его целиком в зелёной зоне. Доставка: 100 баллов.", 15)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(task)
	sidebar.add_child(button("Автономная попытка", func(): start_attempt(true), true))
	sidebar.add_child(button("Ручное управление", func(): start_attempt(false)))
	var actions := HBoxContainer.new()
	sidebar.add_child(actions)
	pause_button = button("Пауза", func(): sim.toggle_pause())
	pause_button.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(pause_button)
	var reset_button := button("Сброс", func(): sim.reset_attempt(); log_event("Поле сброшено"))
	reset_button.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(reset_button)
	sidebar.add_child(button("Захват / отпустить · Пробел", func(): sim.toggle_grip()))
	var keys := label("W / ↑ — вперёд    S / ↓ — назад\nA / ←, D / → — поворот    P — пауза", 13, Color("93a9bd"))
	sidebar.add_child(keys)
	var details_toggle := CheckButton.new()
	details_toggle.text = "Настройки и телеметрия"
	sidebar.add_child(details_toggle)
	var details_panel := VBoxContainer.new()
	details_panel.visible = false
	sidebar.add_child(details_panel)
	details_toggle.toggled.connect(func(value): details_panel.visible = value)
	details_panel.add_child(hardware_label)
	details_panel.add_child(HSeparator.new())
	details_panel.add_child(label("ПАРАМЕТРЫ РОБОТА", 13, Color("93a9bd")))
	speed_input = setting(details_panel, "Скорость, м/с", 0.2, 1.0, 0.05, 0.65)
	base_input = setting(details_panel, "Колея, м", 0.24, 0.40, 0.01, 0.30)
	noise_input = setting(details_panel, "Ошибка приводов, %", 0, 15, 1, 2)
	seed_input = setting(details_panel, "Seed попытки", 1, 999999, 1, 42)
	for control in inputs:
		control.value_changed.connect(func(_value): apply_settings())
	details_panel.add_child(HSeparator.new())
	stage_label = label("Ожидание запуска", 14, Color("51d8bb"))
	details_panel.add_child(stage_label)
	telemetry_label = label("", 13, Color("93a9bd"))
	details_panel.add_child(telemetry_label)
	log_text = RichTextLabel.new()
	log_text.custom_minimum_size.y = 70
	log_text.size_flags_vertical = SIZE_EXPAND_FILL
	log_text.scroll_following = true
	log_text.add_theme_font_size_override("normal_font_size", 18)
	details_panel.add_child(log_text)
	var footer := label("Учебные размеры и правила. Упрощённая физика; автопилот использует известные координаты поля.", 12, Color("93a9bd"))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(footer)
	save_dialog = dialog(FileDialog.FILE_MODE_SAVE_FILE)
	save_dialog.current_file = "robot.botball.json"
	save_dialog.file_selected.connect(save_project)
	open_dialog = dialog(FileDialog.FILE_MODE_OPEN_FILE)
	open_dialog.file_selected.connect(open_project)
	map_dialog = FileDialog.new()
	map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	map_dialog.filters = PackedStringArray(["*.glb ; 3D-карта GLB"])
	map_dialog.use_native_dialog = true
	map_dialog.file_selected.connect(load_map_file)
	map_dialog.canceled.connect(sync_map_controls)
	add_child(map_dialog)
	assembly_editor = AssemblyEditor.new()
	assembly_editor.visible = false
	add_child(assembly_editor)
	assembly_editor.assembly_changed.connect(func(assembly):
		sim.robot.set_assembly(assembly)
		refresh_actuator_controls()
	)
	assembly_editor.test_requested.connect(test_assembled_robot)
	robot_files = RobotFiles.new()
	add_child(robot_files)
	robot_files.imported.connect(func(value):
		sim.reset_attempt()
		assembly_editor.import_model(value)
		log_event("Модель робота импортирована. Отмена доступна в конструкторе."))
	robot_files.message.connect(log_event)
	assembly_editor.import_requested.connect(robot_files.import_robot)
	assembly_editor.export_requested.connect(func(): robot_files.export_robot(assembly_editor.assembly))
	program_editor = ProgramEditor.new()
	program_editor.visible = false
	add_child(program_editor)
	program_editor.run_requested.connect(run_robot_program)
	program_editor.stop_requested.connect(func():sim.stop_program())
	program_editor.source_changed.connect(func(source):current_program = source)
	var starter: Array = preload("res://src/easy_assembly.gd").default_robot()
	sim.robot.set_assembly(starter)
	assembly_editor.set_assembly(starter)
	assembly_editor.choose_step(4)
	refresh_actuator_controls()
	sim.changed.connect(func(): status_dirty = true)
	sim.event.connect(log_event)
	apply_settings()
	update_status()
	log_event("Готовый робот установлен. Нажми «Ручное управление» или запусти пример в «Код робота».")
	if not OS.has_feature("editor"):
		update_checker.call_deferred("check", false)

func _process(delta: float) -> void:
	# Telemetry needs ten updates a second, independent of 120 Hz physics.
	status_elapsed += delta
	if status_dirty and status_elapsed >= 0.1:
		status_dirty = false
		status_elapsed = 0.0
		update_status()
	if sim == null or not sim.running or sim.paused or sim.autonomous or sim.program_mode:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is SpinBox or save_dialog.visible or open_dialog.visible or map_dialog.visible or program_editor.visible or assembly_editor.visible or robot_files.is_busy():
		sim.manual_forward = 0
		sim.manual_turn = 0
		return
	sim.manual_forward = float(pressed(KEY_W, KEY_UP)) - float(pressed(KEY_S, KEY_DOWN))
	sim.manual_turn = float(pressed(KEY_A, KEY_LEFT)) - float(pressed(KEY_D, KEY_RIGHT))

func pressed(first: Key, second: Key) -> bool:
	return Input.is_physical_key_pressed(first) or Input.is_physical_key_pressed(second)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
		return
	if program_editor.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			sim.toggle_grip()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_P:
			sim.toggle_pause()
			get_viewport().set_input_as_handled()

func camera_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (event.button_mask & MOUSE_BUTTON_MASK_RIGHT and event.shift_pressed):
			sim.pan_camera(event.relative, view_container.size.y)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			sim.orbit -= event.relative.x * 0.008
			sim.elevation = clampf(sim.elevation + event.relative.y * 0.008, 0.05, 1.5)
			sim.update_camera()
		else:
			return
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			sim.zoom_camera(pow(0.9, event.factor))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			sim.zoom_camera(pow(0.9, -event.factor))
		else:
			return
	elif event is InputEventMagnifyGesture:
		sim.zoom_camera(1.0 / maxf(event.factor, 0.01))
	elif event is InputEventPanGesture:
		sim.zoom_camera(exp(event.delta.y * 0.05))
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		sim.focus_robot()
	else:
		return
	view_container.accept_event()

func start_attempt(auto: bool) -> void:
	apply_settings()
	sim.start(auto)
	view_container.grab_focus()

func apply_settings() -> void:
	sim.robot.max_speed = speed_input.value
	sim.robot.wheel_base = base_input.value
	sim.robot.motor_error = noise_input.value / 100.0
	sim.seed_value = int(seed_input.value)

func update_status() -> void:
	hardware_label.text = sim.robot.hardware_status() + "\n" + sim.robot.physics_status()
	score_label.text = "%d / 100" % sim.score
	timer_label.text = "%.1f с" % (sim.elapsed if sim.program_mode else sim.LIMIT - sim.elapsed)
	status_label.text = "Пауза" if sim.paused else ("Программа" if sim.program_mode else "Автономно" if sim.autonomous else "Вручную") if sim.running else ("Доставлено" if sim.score > 0 else "Готов к запуску" if sim.elapsed == 0 else "Попытка завершена")
	pause_button.text = "Продолжить" if sim.paused else "Пауза"
	pause_button.disabled = not sim.running
	for control in inputs:
		control.editable = not sim.running
	var stages := ["Едем к кубу", "Закрываем захват", "Едем к зоне", "Отпускаем куб", "Проверяем доставку"]
	stage_label.text = ("Код · строка %d" % sim.program.line if sim.running else "Программа остановлена") if sim.program_mode else stages[sim.phase] if sim.running and sim.autonomous else ("Куб в захвате" if sim.robot.carrying else "Ожидание команды")
	if program_editor != null and program_editor.status != null and sim.program_mode:
		program_editor.status.text = "Пауза" if sim.paused else "Выполняется строка %d · %.1f с" % [sim.program.line,sim.elapsed] if sim.running else sim.program.error if not sim.program.error.is_empty() else "Программа завершена"
	for row in actuator_panel.get_children():
		for control in row.get_children():
			if control is SpinBox:
				var port: int = control.get_meta("servo_port")
				var servo: Dictionary = sim.robot.actuators.servos[port]
				control.set_value_no_signal(servo.angle)
				control.editable = not servo.locked and not (sim.running and sim.program_mode)
	telemetry_label.text = "Дальномер: %.2f м\nЭнкодеры L / R: %.2f / %.2f м" % [sim.robot.distance_sensor(), sim.robot.left_encoder, sim.robot.right_encoder]

func save_project(path: String) -> void:
	var result := Store.write_project(path, {"speed": speed_input.value, "wheel_base": base_input.value, "noise": noise_input.value / 100.0, "seed": int(seed_input.value)}, sim.robot.assembly, sim.map_config, current_program)
	log_event("Настройки проекта сохранены" if result == OK else "Ошибка сохранения: " + error_string(result))

func open_project(path: String) -> void:
	var result := Store.read_project(path)
	if result.has("error"):
		log_event(result.error)
		return
	var map_error: String = sim.set_map(result.map)
	if not map_error.is_empty():
		show_map_error(map_error)
		return
	sync_map_controls()
	var settings: Dictionary = result.settings
	speed_input.value = settings.speed
	base_input.value = settings.wheel_base
	noise_input.value = settings.noise * 100
	seed_input.value = settings.seed
	sim.robot.set_assembly(result.assembly)
	assembly_editor.set_assembly(result.assembly)
	current_program = result.program if not result.program.is_empty() else ProgramEditor.EXAMPLES[0]
	program_editor.set_source(current_program)
	refresh_actuator_controls()
	apply_settings()
	log_event("Проект открыт. Поле сброшено.")

func log_event(message: String) -> void:
	if log_text.text.length() > 24000:
		log_text.text = log_text.text.right(12000)
	log_text.append_text("[%04.1f] %s\n" % [sim.elapsed, message])
	if program_editor != null:
		program_editor.append_output(message)

func dialog(mode: FileDialog.FileMode) -> FileDialog:
	var file_dialog := FileDialog.new()
	file_dialog.file_mode = mode
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; Проект Botball"])
	file_dialog.use_native_dialog = true
	add_child(file_dialog)
	return file_dialog

func setting(parent: VBoxContainer, text: String, low: float, high: float, step_value: float, initial: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := label(text, 13, Color("b1c3d3"))
	caption.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(caption)
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step_value
	input.value = initial
	input.custom_minimum_size.x = 115
	row.add_child(input)
	inputs.append(input)
	return input

func label(text: String, size: int, color := Color("e6eef6")) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", roundi((size + 2) * 1.2))
	result.add_theme_color_override("font_color", color)
	return result

func button(text: String, action: Callable, primary := false) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 48
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(action)
	if primary:
		result.add_theme_stylebox_override("normal", style(Color("176e62")))
		result.add_theme_stylebox_override("hover", style(Color("208574")))
	return result

func style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", Color("e6eef6"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", style(Color("3d4652") if state == "hover" else Color("282e37")))
	theme.set_color("font_color", "Button", Color("e6eef6"))
	theme.set_stylebox("normal", "LineEdit", style(Color("1e3043")))
	theme.set_stylebox("read_only", "LineEdit", style(Color("172535")))

func open_constructor() -> void:
	sim.reset_attempt()
	assembly_editor.set_assembly(sim.robot.assembly)
	assembly_editor.popup_centered_ratio(0.9)

func select_map(index: int) -> void:
	if syncing_map:
		return
	if index == 2:
		map_dialog.popup_centered_ratio(.7)
		return
	var error: String = sim.set_map({"id":"training_delivery" if index == 0 else "obstacles"})
	if not error.is_empty():
		show_map_error(error)
	sync_map_controls()

func load_map_file(path: String) -> void:
	var loaded := MapLoader.import_glb(path)
	if loaded.has("error"):
		show_map_error(loaded.error)
		sync_map_controls()
		return
	var error: String = sim.set_map(loaded.config)
	if not error.is_empty():
		show_map_error(error)
	sync_map_controls()

func sync_map_controls() -> void:
	if sim == null:
		return
	syncing_map = true
	var custom: bool = sim.map_config.id == "custom"
	map_selector.select(2 if custom else 1 if sim.map_config.id == "obstacles" else 0)
	map_options.visible = custom
	map_name.text = "Своя карта: " + sim.map_config.get("name","GLB") if custom else "Полоса препятствий" if sim.map_config.id == "obstacles" else "Учебный стол · 3 × 2,4 м"
	map_fit.button_pressed = sim.map_config.get("fit",true)
	map_scale.value = sim.map_config.get("scale",1.0)
	syncing_map = false

func adjust_map() -> void:
	if syncing_map or sim == null or sim.map_config.id != "custom":
		return
	var config: Dictionary = sim.map_config.duplicate(true)
	config.fit = map_fit.button_pressed
	config.scale = map_scale.value
	var error: String = sim.set_map(config)
	if not error.is_empty():
		show_map_error(error)
		sync_map_controls()

func show_map_error(message: String) -> void:
	log_event(message)
	var popup := AcceptDialog.new()
	popup.title = "Не удалось загрузить карту"
	popup.dialog_text = message
	popup.confirmed.connect(popup.queue_free)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered()

func refresh_actuator_controls() -> void:
	for child in actuator_panel.get_children():
		actuator_panel.remove_child(child)
		child.queue_free()
	hardware_label.text = sim.robot.hardware_status()
	var labels := ""
	if sim.robot.assembly.is_empty():
		labels = "Учебный робот: мотор 1 — левый, мотор 2 — правый. Серво нет: установи его в конструкторе."
	else:
		for port in range(sim.robot.actuators.motors.size()):
			var index: int = sim.robot.actuators.motors[port]
			labels += "Мотор %d → деталь %d. " % [port+1,index+1]
		for port in range(sim.robot.actuators.servos.size()):
			var servo: Dictionary = sim.robot.actuators.servos[port]
			labels += "Серво %d → деталь %d%s. " % [port+1,servo.index+1," (добавь рычаг)" if servo.followers.is_empty() else " (рычаг закреплён неподвижно)" if servo.locked else ""]
			var row := HBoxContainer.new()
			actuator_panel.add_child(row)
			row.add_child(label("Серво %d, °" % [port+1],13))
			var angle := SpinBox.new()
			angle.min_value = 0
			angle.max_value = 180
			angle.value = servo.angle
			angle.set_meta("servo_port",port)
			angle.editable = not servo.locked
			angle.value_changed.connect(func(value):sim.robot.command_servo(port+1,value))
			row.add_child(angle)
	if labels.is_empty():
		labels = "В сборке пока нет приводов. Поставь моторы и серво в конструкторе."
	if program_editor != null:
		program_editor.set_ports(labels)

func test_assembled_robot() -> void:
	assembly_editor.hide()
	sim.start(false)
	refresh_actuator_controls()
	log_event(sim.robot.hardware_status())

func open_program_editor() -> void:
	program_editor.set_source(current_program)
	refresh_actuator_controls()
	program_editor.popup_centered()

func run_robot_program(source: String) -> void:
	current_program = source
	program_editor.console.clear()
	var error: String = sim.start_program(source)
	if not error.is_empty():
		program_editor.status.text = error
		log_event(error)
	else:
		refresh_actuator_controls()
