extends SceneTree
const Program = preload("res://src/robot_program.gd")
const Runtime = preload("res://src/assembly_runtime.gd")
const Easy = preload("res://src/easy_assembly.gd")
const Connections = preload("res://src/assembly_connections.gd")
const Library = preload("res://src/part_library.gd")
const Simulation = preload("res://src/simulation.gd")
const Store = preload("res://src/project_store.gd")
var failures := 0
class FakeRobot:
	extends Node
	var assembly: Array = []
	var actuators := {"motors":[]}
	var motor_calls: Array = []
	var servo_calls: Array = []
	var stopped := false
	func command_motor(port: float, power: float) -> String:
		if port < 1 or port > 2 or port != int(port): return "нет мотора"
		if absf(power) > 100: return "неверная мощность"
		motor_calls.append([port,power])
		return ""
	func command_servo(port: float, angle: float) -> String:
		if port != 1: return "нет серво"
		if angle < 0 or angle > 180: return "неверный угол"
		servo_calls.append(angle)
		return ""
	func command_drive(left: float,right: float) -> void:
		motor_calls.append([left,right])
	func stop() -> void:
		stopped = true
	func distance_sensor() -> float:
		return 1.25
	func encoder_for_port(_port: int) -> float:
		return .42
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func execute(source: String, robot: Node) -> RefCounted:
	var runner := Program.new()
	var compiled := Program.compile(source)
	if compiled.has("error"):
		check(false,"Compile valid program: " + compiled.error)
		return runner
	runner.start(compiled)
	for i in range(1000):
		runner.advance(.01,robot)
		if not runner.running:
			break
	return runner
func run() -> void:
	var fake := FakeRobot.new()
	var source := "count = 0\nfor i in range(3):\n    count = count + 1\n    if count == 2:\n        servo(1, 30)\n    else:\n        servo(1, 120)\n    wait(0.05)\nwhile count < 5:\n    count = count + 1\nprint(count)\nprint('ready # True')\nprint(distance() + encoder(1))\nstop()"
	var runner := execute(source,fake)
	check(runner.error.is_empty() and not runner.running,"Variables, loops and branches execute")
	check(fake.servo_calls == [120.0,30.0,120.0] and fake.stopped,"Each servo call reaches its numbered actuator")
	check(runner.output.size() == 3 and runner.output[0] == "5" and runner.output[1] == "ready # True" and is_equal_approx(float(runner.output[2]),1.67),"Print and sensors, preserving string literals")
	runner = execute("for i in range(3, 0, -1):\n    motor(1, i * 10)\nprint(abs(-4))\nif not False:\n    print(7)",fake)
	check(runner.error.is_empty() and fake.motor_calls[-1][1] == 10 and runner.output == ["4","7"],"Reverse range, arithmetic and boolean condition")
	for invalid in ["import os","motor(1)","if True\n    stop()","    stop()","if True:\nstop()","else:\n    stop()"]:
		check(Program.compile(invalid).has("error"),"Reject invalid syntax with a diagnostic")
	for invalid in ["motor(99, 50)","servo(1, 181)","wait(-1)","print(load('res://project.godot'))","print(unknown)","print(1 / 0)"]:
		runner = execute(invalid,fake)
		check(not runner.error.is_empty() and not runner.running,"Runtime error stops bad program: " + invalid)
	runner = Program.new()
	runner.start(Program.compile("while True:\n    motor(1, 10)"))
	runner.advance(.01,fake)
	check(runner.running and runner.tasks.size() < 10,"Loop without waits yields to UI")
	runner.running = false
	fake.free()
	var assembly: Array = [{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}]
	for side in range(2):
		check(Easy.place(assembly,"electronics_010",Easy.candidates(assembly,"electronics_010")[0]).is_empty(),"Mount motor")
		var motor := assembly.size()-1
		check(Easy.fasten_motor(assembly,motor).is_empty(),"Fasten motor")
		check(Easy.place(assembly,"electronics_018",Easy.candidates(assembly,"electronics_018")[0]).is_empty(),"Mount wheel")
	check(Easy.place(assembly,"electronics_009",Easy.candidates(assembly,"electronics_009")[0]).is_empty(),"Mount servo")
	var servo_index := assembly.size()-1
	check(Easy.place(assembly,"metal_013",Easy.candidates(assembly,"metal_013")[0]).is_empty(),"Mount servo horn")
	var horn_index := assembly.size()-1
	check(Library.validate(assembly).is_empty(),"Servo rest connections validate")
	var actuators := Runtime.inspect(assembly)
	check(actuators.can_drive and actuators.motors.size() == 2 and actuators.servos.size() == 1,"Detect actuators in actual assembly")
	var sim := Simulation.new()
	root.add_child(sim)
	await process_frame
	sim.robot.set_assembly(assembly)
	check(sim.robot.part_colliders.size() == assembly.size() and sim.robot.training_collider.disabled and not sim.robot.fingers[0].visible,"Physical shape and visuals come from actual assembly")
	var before: Transform3D = sim.robot.assembly_root.get_child(horn_index).transform
	check(sim.robot.command_servo(1,150).is_empty(),"Address servo by port")
	var after: Transform3D = sim.robot.assembly_root.get_child(horn_index).transform
	check(not before.basis.is_equal_approx(after.basis) and sim.robot.assembly == assembly and Library.validate(sim.robot.assembly).is_empty(),"Servo rotates attached horn without altering saved rest geometry")
	check(sim.robot.assembly_root.get_child(servo_index).transform.is_equal_approx(Connections.transform(assembly[servo_index])),"Servo body stays fixed while output moves")
	var program := "motor(1, 45)\nmotor(2, 45)\nservo(1, 120)\nwait(0.5)\nstop()\nprint('done')"
	check(sim.start_program(program).is_empty(),"Start code on assembled robot")
	var start_position: Vector3 = sim.robot.position
	await physics_frame
	await physics_frame
	sim.toggle_pause()
	var waiting_before: float = sim.program.waiting
	var elapsed_before: float = sim.program.elapsed
	for i in range(10):
		await physics_frame
	check(is_equal_approx(sim.program.waiting,waiting_before) and is_equal_approx(sim.program.elapsed,elapsed_before),"Pause suspends code and wait timer")
	sim.toggle_pause()
	for i in range(150):
		await physics_frame
		if not sim.running:
			break
	check(not sim.running and sim.program.error.is_empty() and sim.robot.position.z < start_position.z-.05,"Code drives actual assembled robot across map")
	check(sim.robot.wheel_angles.size() == 2 and sim.robot.actuators.servos[0].angle == 120,"Wheel animation and servo angle follow program")
	check(sim.robot.left_command == 0 and sim.robot.right_command == 0,"Program completion stops motors")
	check(sim.start_program("while True:\n    drive(30, 30)").is_empty(),"Long-running program starts")
	await physics_frame
	sim.stop_program()
	check(not sim.running and not sim.program.running and sim.robot.left_command == 0,"Stop halts interpreter and all motors")
	var filename := "user://program-project-test.json"
	check(Store.write_project(filename,{"speed":.65,"wheel_base":.3,"noise":.02,"seed":42},assembly,{"id":"training_delivery"},program) == OK,"Save source alongside robot")
	check(Store.read_project(filename).program == program,"Preserve program indentation and source in project")
	DirAccess.remove_absolute(filename)
	sim.robot.set_assembly([{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}])
	sim.start(false)
	sim.robot.drive(1,0)
	var stationary: Vector3 = sim.robot.position
	sim.robot.step(.01)
	check(sim.robot.position.is_equal_approx(stationary),"Platform without driven wheels cannot move")
	sim.queue_free()
	await process_frame
	print("PROGRAMS: ","PASS" if failures == 0 else "FAIL"," (",failures," failures)")
	quit(0 if failures == 0 else 1)
