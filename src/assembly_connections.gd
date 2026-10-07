extends RefCounted
## Connections refer to stable inventory instance and port indices.
static var ports: Dictionary = {}
const LABELS := {"pin_hole":"Отверстие для пина", "axle_hole":"Крестовое отверстие", "pin":"Пин", "axle":"Ось", "stud":"Шип LEGO", "stud_socket":"Гнездо LEGO", "hole_8_32":"Отверстие 8-32", "bolt_8_32":"Винт 8-32", "bolt_m3":"Винт M3", "thread_8_32":"Резьба 8-32", "thread_m3":"Резьба M3", "nut_8_32":"Гайка / стойка 8-32", "nut_m3":"Гайка M3"}

static func ensure_loaded() -> void:
	if ports.is_empty():
		ports = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/connections.json")).parts

static func for_part(id: String) -> Array:
	ensure_loaded()
	return ports.get(id, [])

static func compatible(a: String, b: String) -> bool:
	var pairs := [["pin", "pin_hole"], ["axle", "axle_hole"], ["axle", "pin_hole"], ["stud", "stud_socket"], ["bolt_8_32", "hole_8_32"], ["thread_8_32", "nut_8_32"], ["thread_m3", "nut_m3"]]
	for pair in pairs:
		if (a == pair[0] and b == pair[1]) or (a == pair[1] and b == pair[0]):
			return true
	return false

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

static func transform(entry: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(vector(entry.rotation) * PI / 180.0), vector(entry.position))

static func world_port(entry: Dictionary, port_index: int) -> Dictionary:
	var port: Dictionary = for_part(entry.id)[port_index]
	var pose := transform(entry)
	return {"position": pose * vector(port.position), "normal": (pose.basis * vector(port.normal)).normalized()}

static func shares_socket(id: String, a: int, b: int) -> bool:
	if a == b:
		return true
	var points := for_part(id)
	var first: Dictionary = points[a]
	var second: Dictionary = points[b]
	if first.kind != second.kind or not (first.kind.ends_with("hole") or first.kind.begins_with("hole_") or first.kind.begins_with("nut_")):
		return false
	var normal := vector(first.normal)
	return absf(normal.dot(vector(second.normal))) > .999 and (vector(second.position)-vector(first.position)).cross(normal).length() < .0001

static func occupied(assembly: Array, index: int, port_index: int) -> bool:
	for link in assembly[index].get("links", []):
		if shares_socket(assembly[index].id, port_index, int(link.port)):
			return true
	return false

static func component(assembly: Array, index: int) -> Array[int]:
	var result: Array[int] = [index]
	var cursor := 0
	while cursor < result.size():
		for link in assembly[result[cursor]].get("links", []):
			if not result.has(int(link.other)):
				result.append(int(link.other))
		cursor += 1
	return result

static func move_group(assembly: Array, index: int, pose: Transform3D) -> void:
	var delta := pose * transform(assembly[index]).affine_inverse()
	for member in component(assembly, index):
		set_transform(assembly[member], delta * transform(assembly[member]))

static func set_transform(entry: Dictionary, pose: Transform3D) -> void:
	entry.position = [pose.origin.x, pose.origin.y, pose.origin.z]
	var rotation := pose.basis.get_euler() * 180.0 / PI
	entry.rotation = [rotation.x, rotation.y, rotation.z]

static func connect_parts(assembly: Array, moving: int, own: int, fixed: int, destination: int, twist: float = 0) -> String:
	if moving < 0 or fixed < 0 or moving >= assembly.size() or fixed >= assembly.size() or moving == fixed:
		return "Выбери другую деталь для соединения"
	var own_ports := for_part(assembly[moving].id)
	var fixed_ports := for_part(assembly[fixed].id)
	if own < 0 or destination < 0 or own >= own_ports.size() or destination >= fixed_ports.size():
		return "Выбери две точки крепления"
	var same_group := component(assembly, moving).has(fixed)
	if occupied(assembly, moving, own) or occupied(assembly, fixed, destination):
		return "Точка крепления занята; сначала отсоедини деталь"
	if not compatible(own_ports[own].kind, fixed_ports[destination].kind):
		return "Несовместимые крепления: нужен подходящий пин, ось или винт"
	var source := world_port(assembly[moving], own)
	var target := world_port(assembly[fixed], destination)
	var from: Vector3 = source.normal
	var to: Vector3 = -target.normal
	var alignment := Basis.IDENTITY
	if from.dot(to) < -0.99999:
		var perpendicular := from.cross(Vector3.RIGHT)
		if perpendicular.length_squared() < 0.001:
			perpendicular = from.cross(Vector3.UP)
		alignment = Basis(perpendicular.normalized(), PI)
	elif from.dot(to) < 0.99999:
		alignment = Basis(Quaternion(from, to))
	var keyed: bool = own_ports[own].kind == "axle" and fixed_ports[destination].kind == "axle_hole" or own_ports[own].kind == "axle_hole" and fixed_ports[destination].kind == "axle"
	if keyed:
		if absf(twist / 90.0 - roundf(twist / 90.0)) > .0001:
			return "Крестовая ось поворачивается только с шагом 90°"
		var source_tangent := alignment * transform(assembly[moving]).basis * vector(own_ports[own].tangent)
		var target_tangent := transform(assembly[fixed]).basis * vector(fixed_ports[destination].tangent)
		var angle := atan2(to.dot(source_tangent.cross(target_tangent)), source_tangent.dot(target_tangent))
		alignment = Basis(to, angle) * alignment
	alignment = Basis(to, deg_to_rad(twist)) * alignment
	var pose := transform(assembly[moving])
	pose.basis = alignment * pose.basis
	pose.origin = target.position - pose.basis * vector(own_ports[own].position)
	# Refuse out-of-workspace transforms before changing any member.
	var delta := pose * transform(assembly[moving]).affine_inverse()
	for member in component(assembly, moving):
		var p: Vector3 = (delta * transform(assembly[member])).origin
		if maxf(absf(p.x), maxf(absf(p.y), absf(p.z))) > 0.6:
			return "Соединение выходит за пределы рабочей области"
	if same_group:
		if source.position.distance_to(target.position) > .0001 or from.dot(target.normal) > -.999 or absf(twist) > .001:
			return "Для дополнительного крепежа точки должны уже совпадать. Отсоедини деталь, если нужно изменить её положение."
		if keyed:
			var first_tangent := transform(assembly[moving]).basis * vector(own_ports[own].tangent)
			var second_tangent := transform(assembly[fixed]).basis * vector(fixed_ports[destination].tangent)
			var dot := absf(first_tangent.dot(second_tangent))
			if dot > .001 and dot < .999:
				return "Крестовая ось не совмещена с профилем отверстия"
	else:
		move_group(assembly, moving, pose)
	if not assembly[moving].has("links"):
		assembly[moving].links = []
	if not assembly[fixed].has("links"):
		assembly[fixed].links = []
	assembly[moving].links.append({"port":own, "other":fixed, "other_port":destination})
	assembly[fixed].links.append({"port":destination, "other":moving, "other_port":own})
	return ""

static func detach(assembly: Array, index: int) -> void:
	assembly[index].erase("links")
	for entry in assembly:
		var remaining: Array = []
		for link in entry.get("links", []):
			if link.other != index:
				remaining.append(link)
		if entry.has("links"):
			entry.links = remaining

static func remove(assembly: Array, index: int) -> void:
	detach(assembly, index)
	assembly.remove_at(index)
	for entry in assembly:
		for link in entry.get("links", []):
			if link.other > index:
				link.other -= 1

static func validate(assembly: Array) -> String:
	for index in range(assembly.size()):
		var links = assembly[index].get("links", [])
		if not links is Array or links.size() > for_part(assembly[index].id).size():
			return "Неверный список соединений"
		var seen := {}
		for link in links:
			if not link is Dictionary:
				return "Неверное соединение"
			for key in ["port", "other", "other_port"]:
				var value = link.get(key)
				if not (value is int or value is float) or not is_finite(value) or value != int(value):
					return "Неверный индекс соединения"
			var other := int(link.other)
			var own := int(link.port)
			var destination := int(link.other_port)
			if other < 0 or other >= assembly.size() or other == index or own < 0 or own >= for_part(assembly[index].id).size():
				return "Соединение с отсутствующей деталью"
			if destination < 0 or destination >= for_part(assembly[other].id).size() or seen.has(own):
				return "Неверная или повторная точка крепления"
			for previous in seen:
				if shares_socket(assembly[index].id, own, int(previous)):
					return "Отверстие занято с другой стороны"
			seen[own] = true
			if not compatible(for_part(assembly[index].id)[own].kind, for_part(assembly[other].id)[destination].kind):
				return "Несовместимое соединение"
			var reciprocal := false
			var other_links = assembly[other].get("links", [])
			if not other_links is Array:
				return "Неверный список соединений"
			for reverse in other_links:
				if reverse is Dictionary and reverse.get("port") == destination and reverse.get("other") == index and reverse.get("other_port") == own:
					reciprocal = true
			if not reciprocal:
				return "Соединение должно быть взаимным"
			var a := world_port(assembly[index], own)
			var b := world_port(assembly[other], destination)
			if a.position.distance_to(b.position) > .0001 or a.normal.dot(b.normal) > -.999:
				return "Точки соединения не совмещены"
			var source_port: Dictionary = for_part(assembly[index].id)[own]
			var destination_port: Dictionary = for_part(assembly[other].id)[destination]
			if source_port.kind == "axle" and destination_port.kind == "axle_hole":
				var at := (transform(assembly[index]).basis * vector(source_port.tangent)).normalized()
				var bt := (transform(assembly[other]).basis * vector(destination_port.tangent)).normalized()
				var dot := absf(at.dot(bt))
				if dot > .001 and dot < .999:
					return "Крестовая ось не совмещена с профилем отверстия"
	return ""
