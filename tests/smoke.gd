extends SceneTree

const Simulation = preload("res://src/simulation.gd")
const Store = preload("res://src/project_store.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func run() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	await frames(3)
	sim.event.connect(func(message): print("EVENT ", message))
	sim.start(true)
	for i in range(7205):
		await physics_frame
		if not sim.running:
			break
	print("AUTO score=", sim.score, " time=", sim.elapsed, " phase=", sim.phase, " robot=", sim.robot.position, " cube=", sim.cube.position)
	check(sim.score == 100, "Default autonomous attempt must deliver the cube")
	check(sim.elapsed < 60, "Autonomous attempt must finish before deadline")
	# Repeat the same route at parameter boundaries with different noise seeds.
	for variant in [[0.2, 0.24, 0.15, 7], [1.0, 0.4, 0.15, 2027], [0.65, 0.3, 0.02, 42]]:
		sim.robot.max_speed = variant[0]
		sim.robot.wheel_base = variant[1]
		sim.robot.motor_error = variant[2]
		sim.seed_value = variant[3]
		sim.start(true)
		for i in range(7205):
			await physics_frame
			if not sim.running:
				break
		print("VARIANT ", variant, " score=", sim.score, " time=", sim.elapsed)
		check(sim.score == 100, "Autonomous route must work at supported parameter boundaries")
		if variant[3] == 42:
			check(absf(sim.elapsed - 9.6416666667) < 0.05, "Same seed should reproduce default attempt time")
	sim.reset_attempt()
	await frames(3)
	check(sim.score == 0 and sim.elapsed == 0 and not sim.robot.carrying, "Reset must clear attempt state")
	sim.start(false)
	sim.manual_forward = 1
	await frames(60)
	check(sim.robot.position.z < 0.82, "Manual drive must move forward")
	sim.toggle_pause()
	var elapsed_before := sim.elapsed
	var before := sim.robot.position
	await frames(20)
	check(sim.elapsed == elapsed_before and sim.robot.position == before, "Pause must stop robot and timer")
	sim.toggle_pause()
	sim.robot.position = Vector3(0, 0.015, -0.7)
	sim.robot.rotation.y = 0
	await frames(300)
	check(sim.robot.position.z > -1.1, "Robot must collide with table wall")
	sim.reset_attempt()
	await frames(3)
	sim.start(false)
	sim.toggle_grip()
	check(not sim.robot.carrying, "Cannot grasp distant cube")
	sim.cube.freeze = true
	sim.cube.position = sim.GOAL + Vector3(0.35, 0.08, 0)
	await frames(60)
	check(sim.score == 0, "Partially inside cube must not score")
	sim.cube.rotation.y = PI / 4
	sim.cube.position = sim.GOAL + Vector3(0.285, 0.08, 0)
	await frames(60)
	check(sim.score == 0, "Rotated cube protruding from zone must not score")
	sim.cube.rotation = Vector3.ZERO
	sim.cube.position = sim.GOAL + Vector3(0, 0.08, 0)
	sim.robot.set_grip(true)
	await frames(3)
	check(sim.score == 0, "Held cube must not score")
	sim.robot.set_grip(false)
	sim.cube.position = sim.GOAL + Vector3(0, 0.08, 0)
	await frames(60)
	check(sim.score == 100, "Fully delivered stationary cube must score")
	sim.start(false)
	sim.elapsed = 59.98
	await frames(10)
	check(not sim.running and sim.score == 0, "Deadline must end the attempt")
	var settings := {"speed": 0.65, "wheel_base": 0.3, "noise": 0.02, "seed": 42}
	var path := "user://test.botball.json"
	check(Store.write_project(path, settings) == OK, "Save project")
	var restored := Store.read_project(path)
	check(restored.has("settings") and is_equal_approx(restored.settings.speed, settings.speed) and is_equal_approx(restored.settings.wheel_base, settings.wheel_base) and is_equal_approx(restored.settings.noise, settings.noise) and restored.settings.seed == settings.seed, "Project round trip")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version":1,"table":"training_delivery","robot":{"speed":"bad"}}')
	file.close()
	check(Store.read_project(path).has("error"), "Malformed settings must be rejected")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(Store.read_project(path).has("error"), "Broken JSON must be rejected")
	DirAccess.remove_absolute(path)
	sim.queue_free()
	await process_frame
	print("SMOKE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
