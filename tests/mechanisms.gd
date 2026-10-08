extends SceneTree
const Connections = preload("res://src/assembly_connections.gd")
const Library = preload("res://src/part_library.gd")
const Runtime = preload("res://src/assembly_runtime.gd")
const Easy = preload("res://src/easy_assembly.gd")
const Robot = preload("res://src/robot.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func port(id: String, kind: String) -> int:
	var points := Connections.for_part(id)
	for i in range(points.size()):
		if points[i].kind == kind:
			return i
	return -1
func run() -> void:
	var assembly: Array = [
		{"id":"electronics_009", "position":[0,0,0], "rotation":[0,0,0]},
		{"id":"metal_013", "position":[0,0,0], "rotation":[0,0,0]},
		{"id":"lego_3648", "position":[0,0,0], "rotation":[0,0,0]}]
	check(Connections.connect_parts(assembly,1,port("metal_013","servo_socket"),0,port("electronics_009","servo_output")).is_empty(),"Horn mounts on servo output")
	check(Connections.connect_parts(assembly,2,port("lego_3648","axle_hole"),1,port("metal_013","hole_8_32")).is_empty(),"Gear mounts through its central hole to the horn")
	check(Library.validate(assembly).is_empty(),"Servo/horn/gear assembly validates")
	var socket_index: int = Easy.candidates([{ "id":"electronics_009", "position":[0,0,0], "rotation":[0,0,0]}], "metal_013")[0].own
	var socket: Dictionary = Connections.for_part("metal_013")[socket_index]
	check(socket.kind == "servo_socket" and absf(float(socket.normal[2])) > .999, "Simple horn mounting aligns the output axis perpendicular to the horn plane")
	var saved := assembly.duplicate(true)
	var robot := Robot.new()
	root.add_child(robot)
	await process_frame
	robot.set_assembly(assembly)
	var before: Transform3D = robot.assembly_root.get_child(2).transform
	check(robot.command_servo(1,150).is_empty(),"Servo accepts command")
	var after: Transform3D = robot.assembly_root.get_child(2).transform
	check(not before.is_equal_approx(after),"Motion propagates through horn to LEGO gear")
	check(robot.assembly_root.get_child(0).transform.is_equal_approx(Connections.transform(assembly[0])),"Servo housing stays fixed")
	var center: Vector3 = Library.meshes[assembly[2].id].get_aabb().get_center()
	check(robot.part_colliders[2].transform.is_equal_approx(robot.assembly_root.transform*after*Transform3D(Basis.IDENTITY,center)),"Gear collision shape follows its pose")
	check(assembly == saved,"Runtime movement leaves saved construction unchanged")
	for id in ["lego_3647", "lego_32270", "lego_6589", "lego_4019", "lego_32269", "lego_3648", "lego_32498", "lego_3649"]:
		check(port(id,"axle_hole") >= 0,"Gear exposes shaft hole: " + id)
	check(robot.command_servo(1,90).is_empty(),"Servo returns to neutral")
	check(robot.assembly_root.get_child(2).transform.is_equal_approx(before),"Returning servo restores attached assembly")
	# A loose neighbouring gear has no transmission link and must stay still.
	assembly.append({"id":"lego_4019","position":[.04,0,0],"rotation":[0,0,0]})
	var actuators := Runtime.inspect(assembly)
	actuators.servos[0].angle = 150
	check(Runtime.posed(assembly,actuators)[3].is_equal_approx(Connections.transform(assembly[3])),"Proximity alone does not invent a gear transmission")
	robot.queue_free()
	await process_frame
	print("MECHANISMS: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
