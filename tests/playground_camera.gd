extends SceneTree
const Main = preload("res://src/main.gd")
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
	var sim = main.sim
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in range(25):
		main.view_container.gui_input.emit(wheel)
	check(sim.zoom < .5, "Wheel zoom reaches robot detail instead of stopping at whole-table view")
	for i in range(80):
		main.view_container.gui_input.emit(wheel)
	check(is_equal_approx(sim.zoom, sim.camera_min_zoom), "Zoom has a safe lower bound")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in range(100):
		main.view_container.gui_input.emit(wheel)
	check(is_equal_approx(sim.zoom, sim.camera_max_zoom), "Zoom out has an upper bound")
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 2.0
	main.view_container.gui_input.emit(pinch)
	check(is_equal_approx(sim.zoom, sim.camera_max_zoom / 2.0), "Trackpad pinch zooms in")
	var pan := InputEventMouseMotion.new()
	pan.button_mask = MOUSE_BUTTON_MASK_RIGHT
	pan.shift_pressed = true
	pan.relative = Vector2(100, 30)
	var target: Vector3 = sim.camera_target
	main.view_container.gui_input.emit(pan)
	check(sim.camera_target.distance_to(target) > .01, "Shift-right drag pans the view")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F
	main.view_container.gui_input.emit(key)
	check(sim.camera_target.is_equal_approx(sim.robot.global_transform * sim.robot.center_of_mass), "F focuses the robot after panning")
	check(sim.camera.near < sim.camera_min_zoom and sim.camera.position.is_finite(), "Close camera has a small clipping plane and finite coordinates")
	main.queue_free()
	await process_frame
	print("PLAYGROUND CAMERA: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
