extends SceneTree
const Main = preload("res://src/main.gd")
const Library = preload("res://src/part_library.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main := Main.new()
	root.add_child(main)
	await process_frame
	check(main.sim.robot.assembly.size()==9 and main.sim.robot.actuators.can_drive, "App opens with a drivable assembled robot")
	check(main.assembly_editor.assembly==main.sim.robot.assembly, "Constructor shows the same default robot as the map")
	check(Library.validate(main.sim.robot.assembly).is_empty(), "Default robot uses aligned persistent connections")
	check(main.sim.start_program(main.current_program).is_empty(), "Default program starts without installing any parts")
	await physics_frame
	var before: Vector3 = main.sim.robot.position
	for i in range(140):
		await physics_frame
	check(before.distance_to(main.sim.robot.position)>.1 and not main.sim.program.running and main.sim.program.error.is_empty(), "Default program moves the robot and finishes without errors")
	main.assembly_editor.start_empty_robot()
	check(main.sim.robot.assembly.is_empty(), "Starting from scratch updates the map")
	main.assembly_editor.load_default_robot()
	check(main.sim.robot.assembly.size()==9 and main.sim.robot.actuators.can_drive, "Restoring ready robot updates the map")
	main.queue_free()
	await process_frame
	print("STARTER: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
