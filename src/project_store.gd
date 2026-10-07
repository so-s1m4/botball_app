extends RefCounted
## A settings project, not a saved mid-attempt physics snapshot.
const FORMAT_VERSION := 1
const MapLoader = preload("res://src/map_loader.gd")
const PartLibrary = preload("res://src/part_library.gd")

static func write_project(path: String, settings: Dictionary, assembly: Array = [], map_config: Dictionary = {"id":"training_delivery"}) -> Error:
	if not PartLibrary.validate(assembly).is_empty() or not MapLoader.validate(map_config).is_empty():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "table": "training_delivery", "robot": settings, "assembly": assembly, "map": map_config}, "\t"))
	file.close()
	return OK

static func read_project(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Не удалось открыть файл"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"error": "Файл содержит некорректный JSON"}
	var data = parser.data
	if not data is Dictionary:
		return {"error": "Неверный формат проекта"}
	if data.get("version") != FORMAT_VERSION or data.get("table") != "training_delivery":
		return {"error": "Версия проекта или стол не поддерживается"}
	var settings = data.get("robot")
	if not settings is Dictionary:
		return {"error": "В проекте нет настроек робота"}
	for key in ["speed", "wheel_base", "noise", "seed"]:
		if not settings.get(key) is float and not settings.get(key) is int:
			return {"error": "Неверное значение: " + key}
		if not is_finite(float(settings[key])):
			return {"error": "Недопустимое число: " + key}
	if settings.speed < 0.2 or settings.speed > 1.0 or settings.wheel_base < 0.24 or settings.wheel_base > 0.4 or settings.noise < 0 or settings.noise > 0.15 or settings.seed < 1 or settings.seed > 999999 or float(settings.seed) != floor(float(settings.seed)):
		return {"error": "Параметры выходят за допустимые пределы"}
	var assembly = data.get("assembly", [])
	var assembly_error := PartLibrary.validate(assembly)
	if not assembly_error.is_empty():
		return {"error": assembly_error}
	var map_config = data.get("map", {"id":"training_delivery"})
	var map_error := MapLoader.validate(map_config)
	if not map_error.is_empty():
		return {"error":map_error}
	return {"settings": settings, "assembly": assembly, "map": map_config}
