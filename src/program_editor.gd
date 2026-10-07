extends Window
signal run_requested(source: String)
signal stop_requested
signal source_changed(source: String)
const EXAMPLES := [
	"# Мощность: -100…100. Время: секунды.\nmotor(1, 60)\nmotor(2, 60)\nwait(1)\nstop()\n",
	"# Установи серво и прикрепи рычаг к его выходу.\nfor angle in range(30, 151, 30):\n    servo(1, angle)\n    wait(0.5)\n",
	"# Квадрат: подстрой время поворота под свою колею.\nfor i in range(4):\n    drive(50, 50)\n    wait(0.8)\n    drive(-35, 35)\n    wait(0.25)\nstop()\n",
	"# Встроенный виртуальный дальномер: метры.\nwhile distance() > 0.4:\n    drive(30, 30)\n    wait(0.02)\nstop()\nprint(distance())\n"
]
var code: CodeEdit
var console: RichTextLabel
var status: Label
var ports: Label
var run_button: Button
var stop_button: Button
var initial_source := EXAMPLES[0]
func _ready() -> void:
	title = "Программа робота · Python-подобные команды"
	size = Vector2i(960,760)
	min_size = Vector2i(780,620)
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,16)
	add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	ports = Label.new()
	ports.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(ports)
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	run_button = action("Запустить на карте",func():run_requested.emit(code.text))
	toolbar.add_child(run_button)
	stop_button = action("Остановить",func():stop_requested.emit())
	toolbar.add_child(stop_button)
	var examples := OptionButton.new()
	for text in ["Пример: моторы","Пример: серво","Пример: квадрат","Пример: дальномер"]:
		examples.add_item(text)
	examples.item_selected.connect(func(index):set_source(EXAMPLES[index]))
	toolbar.add_child(examples)
	code = CodeEdit.new()
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.gutters_draw_line_numbers = true
	code.indent_size = 4
	code.indent_use_spaces = true
	code.add_theme_font_size_override("font_size",16)
	code.text = initial_source
	code.text_changed.connect(func():source_changed.emit(code.text))
	layout.add_child(code)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "motor(номер, мощность) · servo(номер, угол 0…180°) · drive(лево, право)\nwait(секунды) · stop() · print(значение) · distance() — метры · encoder(номер) — метры · time() — секунды\nПеременные, арифметика, for … in range(…), while, if / else. Отступ — 4 пробела. Это небольшой Python-подобный язык."
	layout.add_child(help)
	console = RichTextLabel.new()
	console.custom_minimum_size.y = 90
	console.scroll_following = true
	layout.add_child(console)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Напиши команды и нажми «Запустить на карте»."
	layout.add_child(status)
func action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	return button
func set_source(source: String) -> void:
	initial_source = source
	if code != null:
		code.text = source
func set_ports(text: String) -> void:
	if ports != null:
		ports.text = text

func append_output(message: String) -> void:
	if console == null:
		return
	if console.text.length() > 12000:
		console.text = console.text.right(6000)
	console.append_text(message+"\n")
