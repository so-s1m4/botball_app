extends RefCounted
## Simple placement uses the same persisted connections as the advanced editor.
const Connections = preload("res://src/assembly_connections.gd")
const Library = preload("res://src/part_library.gd")
const GROUPS := ["Платформа", "Моторы", "Колёса", "Крепёж", "Все"]
static func in_group(part: Dictionary, group: int) -> bool:
	var name: String = part.name.to_lower()
	match group:
		0: return part.id == "metal_007" or "plate" in name or "channel" in name or "liftarm" in name
		1: return part.id in ["electronics_009", "electronics_010", "electronics_011", "metal_012", "metal_013"]
		2: return ("wheel" in name or "tire" in name) and not "screw" in name
		3: return part.group == "metal" and ("screw" in name or "nut" in name or "washer" in name) or part.group == "lego" and ("pin" in name or "axle" in name)
	return true

static func display_name(id: String) -> String:
	return {"metal_007":"Платформа робота", "electronics_010":"Мотор", "electronics_009":"Сервомотор", "electronics_011":"Маленький сервомотор", "electronics_018":"Колесо Solarbotics", "metal_015":"Винт крепления мотора", "metal_012":"Круглый рычаг серво", "metal_013":"Длинный рычаг серво"}.get(id, Library.find_part(id).get("name", id))

static func tyre_body_mount(id: String, port: Dictionary) -> bool:
	return id in ["lego_55976", "lego_44309", "lego_70162"] and port.kind == "body_mount"

static func candidates(assembly: Array, id: String, source_port: int = -1) -> Array:
	var result: Array = []
	var own := Connections.for_part(id)
	for index in range(assembly.size()):
		var ports := Connections.for_part(assembly[index].id)
		# Keep the two ready-to-drive mounts first, followed by arbitrary holes.
		var destinations := range(ports.size())
		destinations.sort_custom(func(a,b):
			var a_mount: bool = ports[a].kind in ["motor_mount", "servo_mount"]
			var b_mount: bool = ports[b].kind in ["motor_mount", "servo_mount"]
			return a < b if a_mount == b_mount else a_mount)
		for destination in destinations:
			if tyre_body_mount(assembly[index].id, ports[destination]):
				continue
			if ports[destination].kind == "motor_shaft" and not fastening_ports(assembly, index).is_empty():
				continue
			if Connections.occupied(assembly, index, destination):
				continue
			for source in range(own.size()):
				if tyre_body_mount(id, own[source]):
					continue
				if source_port >= 0 and source != source_port:
					continue
				if Connections.compatible(own[source].kind, ports[destination].kind):
					result.append({"part":index, "port":destination, "own":source, "position":Connections.world_port(assembly[index], destination).position})
					break
	return result

static func place(assembly: Array, id: String, candidate: Dictionary, twist: float = 0) -> String:
	var part := Library.find_part(id)
	var count := 0
	for entry in assembly:
		if entry.id == id:
			count += 1
	if part.is_empty() or count >= part.quantity:
		return "Эти детали закончились в наборе"
	var snapshot := assembly.duplicate(true)
	assembly.append({"id":id,"position":[0.0,0.0,0.0],"rotation":[0.0,0.0,0.0]})
	if id == "electronics_010" and candidate.get("part",-1) >= 0 and candidate.part < snapshot.size() and candidate.get("port",-1) >= 0 and candidate.port < Connections.for_part(assembly[int(candidate.part)].id).size():
		var fixed: Dictionary = assembly[int(candidate.part)]
		var mount: Dictionary = Connections.for_part(fixed.id)[int(candidate.port)]
		var local_basis := Basis(Vector3.RIGHT,PI/2)
		if mount.normal[0] > 0:
			local_basis = Basis(Vector3.UP,PI) * Basis(Vector3.RIGHT,-PI/2)
		var basis := Connections.transform(fixed).basis * local_basis
		Connections.set_transform(assembly.back(),Transform3D(basis,Vector3.ZERO))
	var error := Connections.connect_parts(assembly, assembly.size()-1, candidate.get("own",-1), candidate.get("part",-1), candidate.get("port",-1), twist)
	if error.is_empty():
		error = Library.validate(assembly)
	if not error.is_empty():
		assembly.assign(snapshot)
	return error

static func fastening_ports(assembly: Array, index: int) -> Array[int]:
	var result: Array[int] = []
	var ports := Connections.for_part(assembly[index].id)
	for i in range(ports.size()):
		if ports[i].get("purpose", "") == "motor_fastener" and not Connections.occupied(assembly, index, i) and matching_screw(assembly, index, i) < 0:
			result.append(i)
	return result

static func matching_screw(assembly: Array, motor: int, hole: int) -> int:
	var target := Connections.world_port(assembly[motor], hole)
	for member in Connections.component(assembly, motor):
		if assembly[member].id != "metal_015":
			continue
		var screw := Connections.world_port(assembly[member], 0)
		var delta: Vector3 = screw.position - target.position
		if delta.cross(target.normal).length() < .0001 and absf(delta.dot(target.normal)) <= .0016:
			return member
	return -1

static func platform_fastener(assembly: Array, motor: int, hole: int) -> Dictionary:
	var target := Connections.world_port(assembly[motor], hole)
	for member in Connections.component(assembly, motor):
		if member == motor or assembly[member].id == "metal_015":
			continue
		var ports := Connections.for_part(assembly[member].id)
		for i in range(ports.size()):
			if ports[i].kind != "hole_8_32" or Connections.occupied(assembly, member, i):
				continue
			var point := Connections.world_port(assembly[member], i)
			var delta: Vector3 = point.position - target.position
			# Enter from the opposite sheet face, through the sheet into the motor.
			if point.normal.dot(target.normal) > .999 and delta.cross(target.normal).length() < .0001 and delta.dot(target.normal) >= -.0001 and delta.dot(target.normal) <= .0016:
				return {"part":member, "port":i, "own":0}
	return {}

static func fasten_motor(assembly: Array, index: int) -> String:
	if index < 0 or index >= assembly.size() or assembly[index].id != "electronics_010":
		return "Выбери установленный мотор"
	var holes := fastening_ports(assembly, index)
	if holes.is_empty():
		return "Мотор уже закреплён"
	var mounted := false
	for link in assembly[index].get("links", []):
		var own: Dictionary = Connections.for_part(assembly[index].id)[int(link.port)]
		var target: Dictionary = Connections.for_part(assembly[int(link.other)].id)[int(link.other_port)]
		if own.kind == "motor_body_mount" or own.get("purpose", "") == "motor_fastener" and Connections.is_hole(target.kind):
			mounted = true
	if not mounted:
		return "Сначала установи мотор: выбери свободное отверстие или место «Слева» / «Справа»"
	var snapshot := assembly.duplicate(true)
	for hole in holes:
		var candidate := platform_fastener(assembly, index, hole)
		if candidate.is_empty():
			assembly.assign(snapshot)
			return "Отверстия под оба винта не совпадают. Выбери другое отверстие или поверни мотор."
		var error := place(assembly, "metal_015", candidate)
		if not error.is_empty():
			assembly.assign(snapshot)
			return error
	return ""


static func install_motor(assembly: Array, candidate: Dictionary, twist: float = 0) -> String:
	var snapshot := assembly.duplicate(true)
	var motor := assembly.size()
	var error := place(assembly,"electronics_010",candidate,twist)
	if error.is_empty():
		error = fasten_motor(assembly,motor)
	if not error.is_empty():
		assembly.assign(snapshot)
	return error

static func default_robot() -> Array:
	var assembly: Array = [{"id":"metal_007","position":[0.0,0.0,0.0],"rotation":[0.0,0.0,0.0]}]
	for side in range(2):
		var targets := candidates(assembly,"electronics_010")
		if targets.is_empty() or not install_motor(assembly,targets[0]).is_empty():
			return []
		var wheels := candidates(assembly,"electronics_018")
		if wheels.is_empty() or not place(assembly,"electronics_018",wheels[0]).is_empty():
			return []
	return assembly

static func motor_to_fasten(assembly: Array, selected: int) -> int:
	if selected >= 0 and selected < assembly.size() and assembly[selected].id == "electronics_010" and not fastening_ports(assembly,selected).is_empty():
		return selected
	for index in range(assembly.size()):
		if assembly[index].id == "electronics_010" and not fastening_ports(assembly,index).is_empty():
			return index
	return -1
