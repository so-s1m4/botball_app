extends Control


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Botball Simulator"
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)

	var status := Label.new()
	status.text = "Начальная структура проекта. Симуляция пока не реализована."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)

	var next_steps := Label.new()
	next_steps.text = "Следующий этап: модель стола, настройка коллайдеров, один робот и одно задание.\nДля начала нужны модель GLB/GLTF, год комплекта и проверенные правила."
	next_steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(next_steps)
