extends SceneTree
const Runtime = preload("res://src/assembly_runtime.gd")
const Examples = preload("res://src/mechanical_examples.gd")
const Library = preload("res://src/part_library.gd")
const Connections = preload("res://src/assembly_connections.gd")
const Robot = preload("res://src/robot.gd")
const Store = preload("res://src/project_store.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var example := Examples.lift()
	check(not example.has("error"),"Lift fixture validates: " + str(example.get("error","")))
	if example.has("error"):
		quit(1)
		return
	var assembly: Array = example.assembly
	var saved := assembly.duplicate(true)
	var actuators := Runtime.inspect(assembly)
	print("Transmission edges: ",actuators.mechanisms.edges)
	check(actuators.mechanisms.edges.size() == 2,"Detect centred spur gear pair and rack engagement")
	var rest := Runtime.posed(assembly,actuators)
	actuators.servos[0].angle = 120.0
	var poses := Runtime.posed(assembly,actuators)
	var values := Runtime.Mechanisms.values(actuators)
	check(not actuators.mechanisms.blocked,"Valid gear train is free to move")
	check(is_equal_approx(absf(values.get(1,0)),PI/4),"24-to-16 gears multiply angular travel by 1.5")
	check(is_equal_approx(absf(values.get(2,0)),PI*.002),"Rack displacement is pinion pitch radius times rotation")
	check(absf((poses[5].origin-rest[5].origin).y) > .006,"Rack lifts vertically")
	check(poses[0].is_equal_approx(rest[0]) and poses[4].is_equal_approx(rest[4]),"Motor housing and bearing support remain fixed")
	check(assembly == saved,"Constraint solver leaves saved rest assembly unchanged")
	actuators.servos[0].angle = 180.0
	Runtime.posed(assembly,actuators)
	check(actuators.mechanisms.blocked,"Guide end stop prevents excessive travel")
	actuators.servos[0].angle = 90.0
	check(Runtime.posed(assembly,actuators)[5].is_equal_approx(rest[5]),"Reversing to neutral restores the carriage")
	var unmated := assembly.duplicate(true)
	# Move the whole rack/guide component away from the pitch circle.
	Connections.move_group(unmated,5,Transform3D(Connections.transform(unmated[5]).basis,Connections.transform(unmated[5]).origin+Vector3(.04,0,0)))
	var isolated := Runtime.inspect(unmated)
	check(isolated.mechanisms.edges.size()==1,"Incorrect spacing does not invent rack contact")
	var frozen := assembly.duplicate(true)
	for entry in frozen:
		for link in entry.get("links",[]):
			if link.get("mode") == "hinge":
				link.erase("mode"); link.erase("moving"); link.erase("lower"); link.erase("upper")
	var locked := Runtime.inspect(frozen)
	locked.servos[0].angle = 120.0
	Runtime.posed(frozen,locked)
	check(locked.mechanisms.blocked,"A fixed gear blocks the driving pinion")
	var path := "user://transmission-test.json"
	check(Store.write_project(path,{"speed":.65,"wheel_base":.3,"noise":.02,"seed":42},assembly)==OK,"Save dynamic connections")
	var reopened := Store.read_project(path)
	check(not reopened.has("error") and Library.validate(reopened.assembly).is_empty() and reopened.assembly[3].links[0].mode == "hinge","Joint modes, limits and reciprocity survive project roundtrip")
	check(Runtime.inspect(reopened.assembly).mechanisms.edges.size()==2,"Loaded transmission remains operational")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var invalid := assembly.duplicate(true)
	invalid[3].links[0].upper = NAN
	check(not Library.validate(invalid).is_empty(),"Reject nonfinite guide/joint limits")
	var robot := Robot.new()
	root.add_child(robot)
	await process_frame
	robot.set_assembly(assembly)
	check(robot.command_servo(1,120).is_empty(),"Preview accepts a feasible lift command")
	check(not robot.command_servo(1,180).is_empty(),"Preview explains infeasible travel before teleporting")
	check(is_equal_approx(robot.actuators.servos[0].angle,120),"Invalid preview preserves previous state")
	robot.simulate_actuators = true
	robot.command_servo(1,180)
	for i in range(180): robot.advance_servos(1.0/120)
	check(robot.actuators.servos[0].angle < 180,"Runtime servo stops at finite guide travel")
	check(not robot.mechanism_message.is_empty(),"Runtime explains an end stop")
	robot.reset_robot(42)
	robot.simulate_actuators = true
	robot.servo_torque = .000001
	# Identify the command direction that raises the carriage.
	robot.command_servo(1,80)
	robot.advance_servos(.1)
	if absf(robot.actuators.servos[0].angle-90) > .0001:
		robot.reset_robot(42)
		robot.simulate_actuators = true
		robot.command_servo(1,100)
		robot.advance_servos(.1)
	check(is_equal_approx(robot.actuators.servos[0].angle,90),"Insufficient torque stalls lifting through the gear train")
	check(robot.mechanism_message.contains("момент"),"Servo overload is visible to the user")
	robot.reset_robot(42)
	robot.servo_torque = .18
	robot.simulate_actuators = true
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.003,.003,.003)
	collider.shape = box
	obstacle.add_child(collider)
	root.add_child(obstacle)
	obstacle.global_position = robot.global_transform*robot.assembly_root.transform*robot.assembly_root.get_child(5).transform*Library.meshes[assembly[5].id].get_aabb().get_center()
	await physics_frame
	await physics_frame
	robot.command_servo(1,120)
	robot.advance_servos(.1)
	check(absf(robot.actuators.servos[0].angle-90)<.1,"Moving mechanism stalls against a world obstacle")
	check(robot.mechanism_message.contains("препятствие"),"Collision stop is visible")
	obstacle.queue_free()
	await process_frame
	robot.reset_robot(42)
	check(robot.assembly_root.get_child(5).transform.is_equal_approx(rest[5]),"Reset restores lift to its rest pose")
	var passive: Array = [Examples.part("lego_3743",Vector3(0,.1,0))]
	passive[0].rotation = [0,0,90]
	check(Examples.support(passive,0,Examples.port("lego_3743","stud_socket"),"lego_6587","stud","slider",-5,5).is_empty(),"Create a free vertical guide")
	robot.set_assembly(passive)
	robot.simulate_actuators = true
	for i in range(60): robot.advance_free_joints(1.0/120)
	check(is_equal_approx(robot.actuators.mechanisms.channels[0].value,-.005),"Unpowered vertical carriage falls under gravity to its stop")
	check(is_zero_approx(robot.actuators.mechanisms.channels[0].velocity),"Guide stop removes free velocity")
	robot.reset_robot(42)
	check(is_zero_approx(robot.actuators.mechanisms.channels[0].value),"Reset clears passive joint travel")
	var pendulum: Array = [Examples.part("metal_013",Vector3(0,.1,0))]
	check(Examples.support(pendulum,0,Examples.port("metal_013","hole_8_32"),"lego_3700","pin_hole","hinge",-180,180).is_empty(),"Create a free hinge")
	robot.set_assembly(pendulum)
	robot.simulate_actuators = true
	var support_before: Transform3D = robot.assembly_root.get_child(1).transform
	for i in range(60): robot.advance_free_joints(1.0/120)
	check(absf(robot.actuators.mechanisms.channels[0].value)>.1,"Off-centre arm swings down under gravity")
	check(robot.assembly_root.get_child(1).transform.is_equal_approx(support_before),"Passive hinge preserves its bearing support")
	var nested: Array = [Examples.part("electronics_009"),Examples.part("metal_013")]
	check(Connections.connect_parts(nested,1,Examples.port("metal_013","servo_socket",true),0,Examples.port("electronics_009","servo_output")).is_empty(),"Attach horn for nested mechanism")
	check(Examples.support(nested,0,Examples.port("electronics_009","servo_body_mount"),"lego_3700","pin_hole","slider",-10,10).is_empty(),"Mount servo housing on moving carriage")
	var nested_actuators := Runtime.inspect(nested)
	nested_actuators.servos[0].angle = 120
	var base_poses := Runtime.posed(nested,nested_actuators)
	nested_actuators.mechanisms.channels[1].value = .004
	var moving_poses := Runtime.posed(nested,nested_actuators)
	var translation: Vector3 = nested_actuators.mechanisms.channels[1].axis*.004
	check((moving_poses[0].origin-base_poses[0].origin).is_equal_approx(translation),"Carriage moves servo housing")
	check((moving_poses[1].origin-base_poses[1].origin).is_equal_approx(translation),"Servo output follows its moving parent pivot")
	check(moving_poses[1].basis.is_equal_approx(base_poses[1].basis),"Moving parent preserves servo relative rotation")
	robot.queue_free()
	await process_frame
	print("TRANSMISSIONS: ","PASS" if failures == 0 else "FAIL"," (",failures," failures)")
	quit(0 if failures == 0 else 1)
