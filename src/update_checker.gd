extends Node

const RELEASE_API = "https://api.github.com/repos/so-s1m4/botball_app/releases/latest"
const RELEASE_PAGE = "https://github.com/so-s1m4/botball_app/releases/latest"
const DOWNLOAD_PREFIX = "https://github.com/so-s1m4/botball_app/releases/download/"
var request: HTTPRequest
var dialog: AcceptDialog
var download_button: Button
var download_url := ""
var manual := false
var busy := false

func _ready() -> void:
	request = HTTPRequest.new()
	request.timeout = 15.0
	request.body_size_limit = 1024 * 1024
	add_child(request)
	request.request_completed.connect(completed)
	dialog = AcceptDialog.new()
	dialog.title = "Обновления Botball Lab"
	dialog.min_size = Vector2i(470, 180)
	add_child(dialog)
	download_button = dialog.add_button("Скачать .dmg", false, "download")
	download_button.visible = false
	dialog.custom_action.connect(func(action):
		if action == "download" and not download_url.is_empty():
			OS.shell_open(download_url)
	)

func check(show_result := true) -> void:
	manual = manual or show_result
	if busy:
		return
	busy = true
	download_url = ""
	download_button.visible = false
	if manual:
		show_message("Проверяем обновления…")
	var error := request.request(RELEASE_API, ["Accept: application/vnd.github+json", "User-Agent: Botball-Lab"])
	if error != OK:
		busy = false
		if manual:
			show_message("Не удалось проверить обновления. Проверь подключение к интернету и повтори попытку.")
		manual = false

static func version_numbers(value: String) -> PackedInt32Array:
	var numbers := PackedInt32Array()
	var fields := value.trim_prefix("v").split(".")
	if fields.size() != 3:
		return numbers
	for field in fields:
		if not field.is_valid_int() or int(field) < 0:
			return PackedInt32Array()
		numbers.append(int(field))
	return numbers

static func is_newer(candidate: String, current: String) -> bool:
	var next := version_numbers(candidate)
	var installed := version_numbers(current)
	if next.size() != 3 or installed.size() != 3:
		return false
	for index in range(3):
		if next[index] != installed[index]:
			return next[index] > installed[index]
	return false

static func release_download(release: Dictionary) -> String:
	if release.get("draft", false) or release.get("prerelease", false):
		return ""
	var tag: String = str(release.get("tag_name", ""))
	if version_numbers(tag).size() != 3:
		return ""
	var assets: Variant = release.get("assets", [])
	if not assets is Array:
		return ""
	for asset in assets:
		if not asset is Dictionary:
			continue
		var url: String = str(asset.get("browser_download_url", ""))
		if asset.get("name", "") == "Botball-Lab-macOS.dmg" and float(asset.get("size", 0)) > 0 and url == DOWNLOAD_PREFIX + tag + "/Botball-Lab-macOS.dmg":
			return url
	return ""

func completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var report := manual
	manual = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if report:
			show_message("Релиз пока не опубликован." if code == 404 else "Не удалось проверить обновления. Проверь интернет и повтори попытку.")
		return
	var parser := JSON.new()
	var parse_error := parser.parse(body.get_string_from_utf8())
	var release: Variant = parser.data
	if parse_error != OK or not release is Dictionary:
		if report:
			show_message("Сервис обновлений вернул неверный ответ. Повтори попытку позже.")
		return
	var url := release_download(release)
	if url.is_empty():
		if report:
			show_message("Установщик новой версии пока недоступен. Повтори попытку позже.")
		return
	var current: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	var tag: String = str(release.get("tag_name", ""))
	if is_newer(tag, current):
		download_url = url
		download_button.visible = true
		show_message("Доступна версия %s (установлена %s).\nСкачай .dmg, закрой приложение и перенеси новую\nверсию в «Программы» с заменой старой.\nСохранённые проекты останутся на месте." % [tag, current])
	elif report:
		show_message("Установлена актуальная версия %s." % current)

func show_message(message: String) -> void:
	dialog.dialog_text = message
	dialog.popup_centered()
