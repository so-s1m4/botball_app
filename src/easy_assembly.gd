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

static func candidates(assembly: Array, id: String) -> Array:
	var result: Array = []
	var own := Connections.for_part(id)
	for index in range(assembly.size()):
		var ports := Connections.for_part(assembly[index].id)
		for destination in range(ports.size()):
			if ports[destination].kind == "motor_shaft" and not fastening_ports(assembly, index).is_empty():
				continue
			if Connections.occupied(assembly, index, destination):
				continue
			for source in range(own.size()):
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
		if ports[i].get("purpose", "") == "motor_fastener" and not Connections.occupied(assembly, index, i):
			result.append(i)
	return result

static func fasten_motor(assembly: Array, index: int) -> String:
	if index < 0 or index >= assembly.size() or assembly[index].id != "electronics_010":
		return "Выбери установленный мотор"
	var holes := fastening_ports(assembly, index)
	if holes.is_empty():
		return "Мотор уже закреплён"
	var snapshot := assembly.duplicate(true)
	for hole in holes:
		var error := place(assembly, "metal_015", {"part":index,"port":hole,"own":0})
		if not error.is_empty():
			assembly.assign(snapshot)
			return error
	return ""
