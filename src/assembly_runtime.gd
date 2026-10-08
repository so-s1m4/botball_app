extends RefCounted
## Runtime actuators leave the saved rest assembly and its links untouched.
const Connections = preload("res://src/assembly_connections.gd")
const Easy = preload("res://src/easy_assembly.gd")
const Mechanisms = preload("res://src/mechanical_solver.gd")
const Library = preload("res://src/part_library.gd")
static func inspect(assembly: Array) -> Dictionary:
	var motors: Array[int] = []
	var wheels: Array = []
	var servos: Array = []
	for index in range(assembly.size()):
		var entry: Dictionary = assembly[index]
		if entry.id == "electronics_010":
			motors.append(index)
		if entry.id == "electronics_010" and Easy.fastening_ports(assembly,index).is_empty():
			for link in entry.get("links",[]):
				if Connections.for_part(entry.id)[int(link.port)].kind == "motor_shaft" and assembly[int(link.other)].id == "electronics_018":
					var wheel := int(link.other)
					var size: Array = Library.models[assembly[wheel].id].size
					wheels.append({"motor":index,"wheel":wheel,"center":Connections.transform(assembly[wheel])*Vector3(0,float(size[1])/2,0),"radius":maxf(size[0],size[2])/2})
		if entry.id in ["electronics_009","electronics_011"]:
			var servo := {"index":index,"followers":[],"angle":90.0,"pivot":Vector3.ZERO,"axis":Vector3.FORWARD,"locked":false}
			for link in entry.get("links",[]):
				if Connections.for_part(entry.id)[int(link.port)].kind != "servo_output":
					continue
				var output := Connections.world_port(entry,int(link.port))
				servo.pivot = output.position
				servo.axis = output.normal
				servo.followers = branch(assembly,index,int(link.other))
				servo.locked = servo.followers.has(index)
			servos.append(servo)
	wheels.sort_custom(func(a,b):return a.center.x < b.center.x)
	var base := 0.0
	if wheels.size() >= 2:
		base = wheels.back().center.x - wheels.front().center.x
	var result := {"motors":motors,"wheels":wheels,"servos":servos,"wheel_base":base,"can_drive":wheels.size() >= 2 and base > .005}
	result.mechanisms = Mechanisms.inspect(assembly, servos)
	return result

static func branch(assembly: Array, servo: int, output: int) -> Array[int]:
	var result: Array[int] = [output]
	var cursor := 0
	while cursor < result.size():
		var current := result[cursor]
		for link in assembly[current].get("links",[]):
			if link.get("mode", "fixed") != "fixed":
				continue
			var other := int(link.other)
			if current == output and other == servo or current == servo and other == output:
				continue
			if not result.has(other):
				result.append(other)
		cursor += 1
	return result

static func posed(assembly: Array, actuators: Dictionary) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for entry in assembly:
		poses.append(Connections.transform(entry))
	return Mechanisms.posed(assembly, actuators, poses)
