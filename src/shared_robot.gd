extends Node
signal remote_changed(assembly: Array)
signal message(text: String)
signal status_changed(text: String)
const Library = preload("res://src/part_library.gd")
const SERVICE := "https://botball-lab.preview.s1m4.com"
var service := SERVICE
var room := ""
var client := Crypto.new().generate_random_bytes(16).hex_encode()
var revision := 0
var participants := 0
var base: Array = []
var local: Array = []
var sent: Array = []
var busy := false
var dirty := false
var action := ""
var elapsed := 0.0
var http: HTTPRequest
var panel: AcceptDialog
var link_input: LineEdit
var status: Label
var editor: Window
var leave_button: Button
var copy_button: Button

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 12
	http.body_size_limit = 4 * 1024 * 1024
	add_child(http)
	http.request_completed.connect(completed)
	panel = AcceptDialog.new()
	panel.title = "Совместная сборка"
	panel.min_size = Vector2i(620, 300)
	panel.ok_button_text = "Закрыть"
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var description := Label.new()
	description.text = "Создай комнату и отправь ссылку участникам.\nПо ссылке можно редактировать общего робота.\nКамера, карта и запуск симуляции у каждого свои.\nПодключение загрузит робота из комнаты."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	link_input = LineEdit.new()
	link_input.placeholder_text = "Вставь ссылку на комнату…"
	link_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(link_input)
	var row := HFlowContainer.new()
	box.add_child(row)
	for item in [["Создать комнату", create_room], ["Подключиться", join_from_input]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		row.add_child(button)
	copy_button = Button.new()
	copy_button.text = "Копировать ссылку"
	copy_button.disabled = true
	copy_button.pressed.connect(func(): DisplayServer.clipboard_set(link_input.text); link_input.select_all())
	row.add_child(copy_button)
	leave_button = Button.new()
	leave_button.text = "Отключиться"
	leave_button.disabled = true
	leave_button.pressed.connect(leave)
	row.add_child(leave_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	set_status("Локальная сборка")

func show_panel() -> void:
	panel.popup_centered(Vector2i(680, 330))

func auto_join() -> void:
	if OS.has_feature("web"):
		var token = JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('room') || ''", true)
		if token is String and valid_room(token):
			join_room(token)

static func valid_room(value: String) -> bool:
	return value.length() == 48 and value == value.to_lower() and value.is_valid_hex_number(false)

static func ensure_ids(assembly: Array) -> void:
	var used := {}
	for part in assembly:
		var uid: String = str(part.get("uid", "")).to_lower()
		if uid.length() != 32 or not uid.is_valid_hex_number(false) or used.has(uid):
			uid = Crypto.new().generate_random_bytes(16).hex_encode()
		part.uid = uid
		used[uid] = true

static func to_wire(assembly: Array) -> Array:
	ensure_ids(assembly)
	var result: Array = []
	for part in assembly:
		var links: Array = []
		for link in part.get("links", []):
			var converted: Dictionary = link.duplicate(true)
			converted.other = assembly[int(link.other)].uid
			links.append(converted)
		result.append({"uid":part.uid, "id":part.id, "position":part.position.duplicate(), "rotation":part.rotation.duplicate(), "links":links})
	return result

static func from_wire(value: Variant) -> Dictionary:
	if not value is Array or value.size() > 2048:
		return {"error":"Неверная сборка в комнате"}
	var indexes := {}
	for i in range(value.size()):
		if not value[i] is Dictionary or not value[i].get("uid") is String or indexes.has(value[i].uid):
			return {"error":"Неверные идентификаторы деталей"}
		indexes[value[i].uid] = i
	var assembly: Array = value.duplicate(true)
	for part in assembly:
		if not part.get("links") is Array:
			return {"error":"Неверные соединения в комнате"}
		for link in part.links:
			if not link is Dictionary or not indexes.has(link.get("other")):
				return {"error":"Соединённая деталь не найдена"}
			link.other = indexes[link.other]
	var error := Library.validate(assembly)
	return {"error":error} if not error.is_empty() else {"assembly":assembly}

func create_room() -> void:
	if busy or not room.is_empty():
		return
	local = to_wire(editor.assembly)
	sent = local.duplicate(true)
	dirty = false
	action = "create"
	request("/api/rooms", HTTPClient.METHOD_POST, {"assembly":sent,"client":client})

func join_from_input() -> void:
	var token := link_input.text.strip_edges()
	if token.contains("?room="):
		token = token.get_slice("?room=",1).get_slice("&",0).get_slice("#",0)
	join_room(token)

func join_room(token: String) -> void:
	if busy:
		return
	if not valid_room(token):
		set_status("Вставь ссылку на комнату Botball")
		return
	room = token
	local = to_wire(editor.assembly)
	dirty = false
	action = "join"
	request("/api/rooms/" + room + "?client=" + client)

func local_changed(assembly: Array) -> void:
	if room.is_empty() and action != "create":
		return
	local = to_wire(assembly)
	dirty = true
	elapsed = 0.0
	set_status("Отправка изменений…")

func _process(delta: float) -> void:
	if busy or room.is_empty():
		return
	elapsed += delta
	if elapsed < (0.15 if dirty else 0.8):
		return
	elapsed = 0.0
	if dirty:
		sent = local.duplicate(true)
		dirty = false
		action = "write"
		request("/api/rooms/" + room, HTTPClient.METHOD_POST, {"before":base,"after":sent,"client":client})
	else:
		action = "poll"
		request("/api/rooms/" + room + "?client=" + client)

func request(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, data: Dictionary = {}) -> void:
	busy = true
	var error := http.request(service + path, PackedStringArray(["Content-Type: application/json"]), method, "" if data.is_empty() else JSON.stringify(data))
	if error != OK:
		fail("Не удалось подключиться. Твоя сборка остаётся локально.")

func completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not busy:
		return
	busy = false
	var parser := JSON.new()
	var valid_response := result == HTTPRequest.RESULT_SUCCESS and parser.parse(body.get_string_from_utf8()) == OK
	var data = parser.data
	if not valid_response or not data is Dictionary:
		fail("Связь потеряна. Твоя сборка остаётся локально; подключись снова по ссылке.")
		return
	if code < 200 or code >= 300:
		fail(str(data.get("error", "Ошибка комнаты")) + ". Твоя версия остаётся локально; её можно экспортировать.")
		return
	if action == "join" and dirty:
		fail("Сборка изменена во время подключения. Твоя версия остаётся локально; подключись снова.")
		return
	var parsed := from_wire(data.get("assembly"))
	if parsed.has("error") or not data.get("revision") is float and not data.get("revision") is int:
		fail("Не удалось проверить общую сборку. Твоя версия остаётся локально.")
		return
	if action == "create":
		room = str(data.get("room", ""))
		if not valid_room(room):
			fail("Сервер вернул неверную комнату")
			return
	var changed: bool = int(data.revision) != revision or action in ["create", "join"]
	revision = int(data.revision)
	participants = int(data.get("participants", 1))
	# Edits made while a request was in flight are a diff against the sent state.
	# The server merges that diff with other participants' changes atomically.
	if dirty:
		if action in ["write", "create"]:
			base = sent.duplicate(true)
		# A poll started before the edit: retain the previous editing base.
	else:
		base = data.assembly.duplicate(true)
		local = base.duplicate(true)
		if changed and action != "create" and not (action == "write" and data.assembly == JSON.parse_string(JSON.stringify(sent))):
			remote_changed.emit(parsed.assembly)
	link_input.text = SERVICE + "/?room=" + room
	copy_button.disabled = false
	leave_button.disabled = false
	set_status("Комната · участников: %d · сохранено" % participants if not dirty else "Отправка изменений…")
	if action == "create":
		link_input.select_all()
		message.emit("Комната создана. Отправь ссылку участникам.")
	action = ""

func leave() -> void:
	http.cancel_request()
	busy = false
	room = ""
	action = ""
	dirty = false
	revision = 0
	leave_button.disabled = true
	set_status("Локальная сборка. Робот сохранён в этом окне.")

func fail(text: String) -> void:
	leave()
	set_status(text)
	message.emit(text)
	show_panel()

func set_status(text: String) -> void:
	status.text = text
	status_changed.emit("Совместно · %d" % participants if not room.is_empty() else "Совместно")
