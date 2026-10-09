extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for dimensions in [Vector2i(1024,740),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size = dimensions
		for i in range(5):
			await process_frame
		check(main.view_container.size.x > 0 and main.view_container.size.y >= 360, "Main viewport stays usable")
		check(main.get_child(1).get_rect().end.x <= dimensions.x+1, "Main UI fits window width")
		var editor = main.assembly_editor
		editor.size = dimensions
		editor.set_assembly([{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}])
		editor.choose_step(1)
		editor.select_catalog(editor.catalog_ids.find("electronics_010"))
		for i in range(5):
			await process_frame
		check(editor.view.size.x >= 400 and editor.view.size.y >= 300, "Constructor viewport stays usable")
		check(editor.get_child(0).get_combined_minimum_size().x <= dimensions.x, "Constructor panels fit window width")
		var candidate: Dictionary = editor.simple_targets[0]
		var point = editor.camera.unproject_position(candidate.position) * editor.view.size / Vector2(editor.view.get_child(0).size)
		check(editor.nearest_simple_target(point) >= 0, "Hole picking works after resizing")
	main.shared_robot.show_panel()
	for i in range(8):
		await process_frame
	check(main.shared_robot.panel.size.y < 700, "Shared room dialog stays compact with wrapped text")
	main.shared_robot.panel.hide()
	main.queue_free()
	await process_frame
	print("LAYOUT: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
