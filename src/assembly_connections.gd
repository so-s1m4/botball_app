extends RefCounted
## Connections refer to stable inventory instance and port indices.
static var ports: Dictionary = {}
const FastenerClearance = preload("res://src/fastener_clearance.gd")
const LABELS := {"rim_30_4":"Посадка шины на диск 30,4 мм", "tire_30_4":"Посадка шины 30,4 мм", "rim_24":"Посадка шины на диск 24 мм", "tire_24":"Посадка шины 24 мм", "pin_hole":"Отверстие для пина", "axle_hole":"Крестовое отверстие", "pin":"Пин", "axle":"Ось", "stud":"Шип LEGO", "stud_socket":"Гнездо LEGO", "hole_8_32":"Отверстие 8-32", "bolt_8_32":"Винт 8-32", "bolt_m3":"Винт M3", "thread_8_32":"Резьба 8-32", "thread_m3":"Резьба M3", "nut_8_32":"Гайка / стойка 8-32", "nut_m3":"Гайка M3", "motor_mount":"Место для мотора", "motor_body_mount":"Крепление мотора", "motor_shaft":"Вал мотора", "motor_wheel_socket":"Ступица колеса", "body_mount":"Крепление корпуса", "servo_mount":"Место для серво", "servo_body_mount":"Крепление серво", "servo_output":"Выход серво", "servo_socket":"Крепление рычага"}

static func ensure_loaded() -> void:
	if ports.is_empty():
		ports = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/connections.json")).parts
		var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/easy_mounts.json")).parts
		for id in extra:
			if not ports.has(id):
				ports[id] = []
			ports[id].append_array(extra[id])


		# Append after all historical ports: saved projects persist port indices.
		# Gear centres are derived from the imported mesh's Z shaft axis.
		var models: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/models.json")).models
		for id in ["lego_3647", "lego_32270", "lego_6589", "lego_4019", "lego_32269", "lego_3648", "lego_32498", "lego_3649"]:
			if ports[id].any(func(point): return point.kind == "axle_hole"):
				continue
			var size: Array = models[id].size
			for side in [-1, 1]:
				ports[id].append({"kind":"axle_hole", "position":[0, float(size[1])/2, side*float(size[2])/2], "normal":[0,0,side], "tangent":[1,0,0], "quality":"estimated", "label":"Центр шестерни · крестовая ось"})
		# Imported 1x5 horn lies in XY, with its holes running through Z.
		# Hole spacing is approximate; retain the original servo socket at index 0.
		var horn_size: Array = models.metal_013.size
		for x in [-0.0254, -0.0127, 0.0127, 0.0254, 0.0]:
			for side in [-1, 1]:
				ports.metal_013.append({"kind":"hole_8_32", "position":[x, float(horn_size[1])/2, side*float(horn_size[2])/2], "normal":[0,0,side], "quality":"estimated", "label":"Отверстие рычага серво"})

		ports.metal_013.append({"kind":"servo_socket", "position":[0, float(horn_size[1])/2, -float(horn_size[2])/2], "normal":[0,0,-1], "quality":"estimated", "label":"Соосный выход серво · плоскость рычага"})
		for x in [-.012, -.004, .004, .012]:
			ports.lego_3743.append({"kind":"stud_socket", "position":[x,0,0], "normal":[0,-1,0], "quality":"estimated", "label":"Рейка · крепление к каретке"})

static func for_part(id: String) -> Array:
	ensure_loaded()
	return ports.get(id, [])

static func is_hole(kind: String) -> bool:
	return kind in ["pin_hole", "axle_hole", "hole_8_32"]

static func compatible(a: String, b: String) -> bool:
	# A direct hole joint is a rigid teaching attachment, without a modelled screw.
	if is_hole(a) and is_hole(b):
		return true
	if a in ["motor_body_mount", "servo_body_mount", "body_mount"] and is_hole(b) or b in ["motor_body_mount", "servo_body_mount", "body_mount"] and is_hole(a):
		return true
	var pairs := [["rim_30_4", "tire_30_4"], ["rim_24", "tire_24"], ["servo_mount", "servo_body_mount"], ["servo_output", "servo_socket"], ["motor_mount", "motor_body_mount"], ["motor_shaft", "motor_wheel_socket"], ["pin", "pin_hole"], ["axle", "axle_hole"], ["axle", "pin_hole"], ["stud", "stud_socket"], ["bolt_8_32", "hole_8_32"], ["thread_8_32", "nut_8_32"], ["thread_m3", "nut_m3"]]
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
	var delta := vector(second.position) - vector(first.position)
	# Separate channel walls are distinct holes even when their axes line up.
	return absf(normal.dot(vector(second.normal))) > .999 and delta.cross(normal).length() < .0001 and absf(delta.dot(normal)) <= .016

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

static func connect_parts(assembly: Array, moving: int, own: int, fixed: int, destination: int, twist: float = 0, mode: String = "fixed", lower: float = -180, upper: float = 180) -> String:
	if moving < 0 or fixed < 0 or moving >= assembly.size() or fixed >= assembly.size() or moving == fixed:
		return "Выбери другую деталь для соединения"
	var own_ports := for_part(assembly[moving].id)
	var fixed_ports := for_part(assembly[fixed].id)
	if own < 0 or destination < 0 or own >= own_ports.size() or destination >= fixed_ports.size():
		return "Выбери две точки крепления"
	if mode not in ["fixed", "hinge", "slider"] or not is_finite(lower) or not is_finite(upper) or lower > 0 or upper < 0 or lower >= upper or absf(lower) > 360 or absf(upper) > 360:
		return "Неверный тип или пределы подвижного соединения"
	if mode == "hinge" and not (is_hole(own_ports[own].kind) and is_hole(fixed_ports[destination].kind)):
		return "Свободная ось требует двух отверстий; привод серво подключается через его выход"
	if mode == "hinge" and own_ports[own].kind == "axle_hole" and fixed_ports[destination].kind == "axle_hole":
		return "Два крестовых отверстия фиксируют ось. Для вращения нужна опора с круглым отверстием"
	if mode != "fixed" and component(assembly, moving).has(fixed):
		return "Подвижный узел уже связан с опорой другим креплением"
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
		var clearance_error := fastener_move_error(assembly, moving, delta)
		if not clearance_error.is_empty():
			return clearance_error
		move_group(assembly, moving, pose)
	if not assembly[moving].has("links"):
		assembly[moving].links = []
	if not assembly[fixed].has("links"):
		assembly[fixed].links = []
	var joint := {"port":own, "other":fixed, "other_port":destination}
	if mode != "fixed":
		joint.merge({"mode":mode, "moving":moving, "lower":lower, "upper":upper})
	assembly[moving].links.append(joint)
	var reverse := joint.duplicate(true)
	reverse.merge({"port":destination, "other":moving, "other_port":own}, true)
	assembly[fixed].links.append(reverse)
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
			if link.has("moving") and link.moving > index:
				link.moving -= 1

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
			if link.get("mode", "fixed") not in ["fixed", "hinge", "slider"]:
				return "Неверный тип соединения"
			if link.get("mode", "fixed") != "fixed":
				if not (link.get("moving") is int or link.get("moving") is float) or not is_finite(link.moving) or link.moving != int(link.moving) or int(link.moving) not in [index, other]:
					return "Неверная подвижная деталь"
				for key in ["lower", "upper"]:
					if not (link.get(key) is float or link.get(key) is int) or not is_finite(link[key]):
						return "Неверный предел соединения"
				if link.lower > 0 or link.upper < 0 or link.lower >= link.upper or absf(link.lower) > 360 or absf(link.upper) > 360:
					return "Пределы соединения должны включать исходное положение"
				if link.mode == "hinge" and (not is_hole(for_part(assembly[index].id)[own].kind) or not is_hole(for_part(assembly[other].id)[destination].kind) or for_part(assembly[index].id)[own].kind == "axle_hole" and for_part(assembly[other].id)[destination].kind == "axle_hole"):
					return "Неверная вращательная опора"
			var reciprocal := false
			var other_links = assembly[other].get("links", [])
			if not other_links is Array:
				return "Неверный список соединений"
			for reverse in other_links:
				if reverse is Dictionary and reverse.get("port") == destination and reverse.get("other") == index and reverse.get("other_port") == own:
					if reverse.get("mode", "fixed") != link.get("mode", "fixed") or reverse.get("moving") != link.get("moving") or reverse.get("lower") != link.get("lower") or reverse.get("upper") != link.get("upper"):
						return "Параметры соединения должны быть взаимными"
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

static func fastener_move_error(assembly: Array, moving: int, delta: Transform3D) -> String:
	var members := component(assembly,moving)
	for screw in range(assembly.size()):
		if assembly[screw].id != "metal_015":
			continue
		for motor in range(assembly.size()):
			if assembly[motor].id != "electronics_010" or members.has(screw) == members.has(motor):
				continue
			var bolt_pose := transform(assembly[screw])
			var motor_pose := transform(assembly[motor])
			if members.has(screw):
				bolt_pose = delta * bolt_pose
			else:
				motor_pose = delta * motor_pose
			if FastenerClearance.intersects_motor(bolt_pose,motor_pose):
				return "Винт пересекает корпус мотора. Выбери монтажную прорезь или другое отверстие."
	return ""

static func migrate_v1(assembly: Array) -> Dictionary:
	# Validate against the geometry the file was written with before touching it.
	ensure_loaded()
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/legacy/connections_v1.json")).parts
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/legacy/easy_mounts_v1.json")).parts
	for id in extra:
		legacy[id].append_array(extra[id])
	return migrate_ports(assembly, legacy)

static func migrate_v2(assembly: Array) -> Dictionary:
	ensure_loaded()
	var legacy := ports.duplicate(true)
	# Revision 2 used the case boundary instead of the mounting flange.
	for index in [0, 2, 3]:
		legacy.electronics_010[index].position[0] = .0187939
		legacy.electronics_010[index].position[2] = 0.0
	return migrate_ports(assembly, legacy)

static func migrate_ports(assembly: Array, legacy: Dictionary) -> Dictionary:
	var current := ports
	ports = legacy
	var error: String = load("res://src/part_library.gd").validate(assembly)
	ports = current
	if not error.is_empty():
		return {"error":error}
	var result := assembly.duplicate(true)
	for entry in result:
		entry.erase("links")
	var visited := {}
	for start in range(result.size()):
		if visited.has(start):
			continue
		visited[start] = true
		var queue: Array[int] = [start]
		var cursor := 0
		while cursor < queue.size():
			var fixed := queue[cursor]
			cursor += 1
			for link in assembly[fixed].get("links", []):
				var moving := int(link.other)
				if visited.has(moving):
					continue
				error = connect_parts(result,moving,int(link.other_port),fixed,int(link.port))
				if not error.is_empty():
					return {"error":"Не удалось обновить крепления старой сборки: " + error}
				visited[moving] = true
				queue.append(moving)
	# Restore redundant links as well; refuse inconsistent closed constraints.
	for index in range(result.size()):
		if assembly[index].has("links"):
			result[index].links = assembly[index].links.duplicate(true)
	error = validate(result)
	return {"assembly":result} if error.is_empty() else {"error":"Старой сборке требуется повторное крепление деталей: " + error}
