extends SceneTree
const Files = preload("res://src/robot_files.gd")
const Easy = preload("res://src/easy_assembly.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var robot := Easy.default_robot()
	var result := Files.decode(Files.encode(robot))
	check(not result.has("error") and result.assembly == JSON.parse_string(Files.encode(robot)).assembly, "Robot parts, transforms and connections survive JSON round trip")
	check(Files.decode(Files.encode([])).get("assembly") == [], "Empty robot round trip")
	for text in ["{", "[]", '{"format":"botball-robot","version":2}', '{"format":"botball-robot","version":1,"geometry_revision":3,"assembly":{}}', '{"format":"botball-robot","version":1,"geometry_revision":3,"assembly":[{"id":"unknown","position":[0,0,0],"rotation":[0,0,0]}]}', " ".repeat(Files.MAX_BYTES + 1)]:
		check(Files.decode(text).has("error"), "Invalid or oversized import rejected")
	var broken := robot.duplicate(true)
	broken[0].links[0].other = 9999
	check(Files.decode(JSON.stringify({"format":"botball-robot","version":1,"geometry_revision":3,"assembly":broken})).has("error"), "Broken connections rejected")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var before: Array = main.sim.robot.assembly.duplicate(true)
	var saved_map: Dictionary = main.sim.map_config.duplicate(true)
	var saved_program: String = main.current_program
	main.robot_files.import_text(Files.encode([]))
	check(main.sim.robot.assembly.is_empty(), "Import updates simulator")
	check(main.sim.map_config == saved_map and main.current_program == saved_program, "Robot import preserves map and program")
	main.assembly_editor.undo_step()
	check(main.sim.robot.assembly == before, "Robot import is undoable")
	main.robot_files.import_text("invalid")
	check(main.sim.robot.assembly == before, "Invalid import leaves existing robot intact")
	check(main.robot_files.notice.visible, "Invalid import displays visible error")
	main.queue_free()
	await process_frame
	print("ROBOT FILES: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
