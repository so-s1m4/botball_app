extends Node
## Portable assembly files contain no map, program or simulation settings.
signal imported(assembly: Array)
signal message(text: String)
const Library = preload("res://src/part_library.gd")
const MAX_BYTES := 4 * 1024 * 1024
var open_dialog: FileDialog
var save_dialog: FileDialog
var notice: AcceptDialog
var pending_export := ""
var web_callback
var web_busy := false

func _ready() -> void:
	open_dialog = make_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	open_dialog.file_selected.connect(read_file)
	save_dialog = make_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	save_dialog.current_file = "robot.botball-robot.json"
	save_dialog.file_selected.connect(write_file)
	notice = AcceptDialog.new()
	notice.title = "Модель робота"
	add_child(notice)
	if OS.has_feature("web"):
		web_callback = JavaScriptBridge.create_callback(receive_web_file)

func make_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Модель робота Botball"])
	dialog.use_native_dialog = true
	add_child(dialog)
	return dialog

static func encode(assembly: Array) -> String:
	if not Library.validate(assembly).is_empty():
		return ""
	return JSON.stringify({"format":"botball-robot", "version":1, "geometry_revision":3, "assembly":assembly}, "\t")

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"error":"Файл слишком большой (максимум 4 МБ)"}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"error":"Файл содержит некорректный JSON"}
	var data = parser.data
	if not data is Dictionary or data.get("format") != "botball-robot" or data.get("version") != 1 or data.get("geometry_revision") != 3:
		return {"error":"Выбери файл модели робота Botball (.botball-robot.json)"}
	var assembly = data.get("assembly")
	if not assembly is Array:
		return {"error":"В файле нет сборки робота"}
	var error := Library.validate(assembly)
	if not error.is_empty():
		return {"error":error}
	return {"assembly":assembly}

func import_robot() -> void:
	if OS.has_feature("web"):
		if web_busy:
			return
		web_busy = true
		JavaScriptBridge.get_interface("window").botballRobotUpload = web_callback
		JavaScriptBridge.eval("""
		(() => {
		 const input = document.createElement('input');
		 input.type = 'file'; input.accept = '.json,application/json';
		 input.style.display = 'none'; document.body.appendChild(input);
		 const finish = (kind, text) => { window.botballRobotUpload(kind, text); input.remove(); };
		 input.addEventListener('cancel', () => finish('cancel', ''));
		 input.addEventListener('change', async () => {
		   const file = input.files[0];
		   if (!file) { finish('cancel', ''); return; }
		   if (file.size > 4194304) { finish('error', 'Файл слишком большой (максимум 4 МБ)'); return; }
		   try { finish('file', await file.text()); }
		   catch (_) { finish('error', 'Не удалось прочитать файл'); }
		 });
		 input.click();
		})();
		""", true)
	else:
		open_dialog.popup_centered_ratio(.7)

func export_robot(assembly: Array) -> void:
	pending_export = encode(assembly)
	if pending_export.is_empty():
		show_error("Не удалось экспортировать: сборка содержит ошибки")
		return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(pending_export.to_utf8_buffer(), "robot.botball-robot.json", "application/json")
		message.emit("Модель робота экспортирована")
	else:
		save_dialog.popup_centered_ratio(.7)

func receive_web_file(args: Array) -> void:
	web_busy = false
	if args.size() < 2 or str(args[0]) == "cancel":
		return
	if str(args[0]) == "error":
		show_error(str(args[1]))
	else:
		import_text(str(args[1]))

func read_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		show_error("Не удалось открыть файл")
		return
	if file.get_length() > MAX_BYTES:
		show_error("Файл слишком большой (максимум 4 МБ)")
		return
	import_text(file.get_as_text())

func import_text(text: String) -> void:
	var result := decode(text)
	if result.has("error"):
		show_error(result.error)
		return
	imported.emit(result.assembly)

func write_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		show_error("Не удалось сохранить файл: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(pending_export)
	var error := file.get_error()
	file.close()
	if error != OK:
		show_error("Ошибка записи: " + error_string(error))
	else:
		message.emit("Модель робота экспортирована")

func show_error(text: String) -> void:
	message.emit(text)
	notice.dialog_text = text
	notice.popup_centered(Vector2i(540, 160))

func is_busy() -> bool:
	return web_busy or open_dialog.visible or save_dialog.visible or notice.visible
