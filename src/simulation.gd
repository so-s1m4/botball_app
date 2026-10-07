extends Node3D
## Training task, deliberately independent of official season rules.
signal changed
signal event(message: String)

const Robot = preload("res://src/robot.gd")
const LIMIT := 60.0
const CUBE_START := Vector3(-0.55, 0.10, -0.45)
const GOAL := Vector3(0.90, 0, -0.62)
const GOAL_HALF := Vector2(0.38, 0.32)
var robot: CharacterBody3D
var cube: RigidBody3D
var elapsed := 0.0
var score := 0
var running := false
var paused := false
var autonomous := false
var phase := 0
var seed_value := 42
var orbit := 0.0
var elevation := 0.80
var zoom := 3.8
var camera: Camera3D
var release_wait := 0.0
var manual_forward := 0.0
var manual_turn := 0.0

func _ready() -> void:
	build_world()
	reset_attempt()

func build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("101b2b")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c7d8ed")
	env.environment.ambient_light_energy = 0.3
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 0.65
	light.shadow_enabled = true
	add_child(light)
	static_box(Vector3(3.0, 0.10, 2.4), Vector3(0, -0.05, 0), Color("d5dedb"))
	for x in [-1.54, 1.54]:
		static_box(Vector3(0.08, 0.20, 2.56), Vector3(x, 0.1, 0), Color("365066"))
	for z in [-1.24, 1.24]:
		static_box(Vector3(3.16, 0.20, 0.08), Vector3(0, 0.1, z), Color("365066"))
	# Grid is visual; it does not create collision geometry.
	for i in range(-5, 6):
		visual_box(Vector3(0.003, 0.002, 2.4), Vector3(i * 0.25, 0.002, 0), Color("b3c5c2"))
	for i in range(-4, 5):
		visual_box(Vector3(3, 0.002, 0.003), Vector3(0, 0.002, i * 0.25), Color("b3c5c2"))
	visual_box(Vector3(0.64, 0.004, 0.55), Vector3(-0.95, 0.004, 0.82), Color("7bafcb"))
	visual_box(Vector3(GOAL_HALF.x * 2, 0.005, GOAL_HALF.y * 2), GOAL + Vector3(0, 0.006, 0), Color("52baa0"))
	label_3d("СТАРТ", Vector3(-0.95, 0.014, 1.05), Color("234258"))
	label_3d("ДОСТАВКА · 100", GOAL + Vector3(0, 0.016, 0.23), Color("125f50"))
	robot = Robot.new()
	add_child(robot)
	cube = RigidBody3D.new()
	cube.mass = 0.05
	# This object is repeatedly frozen and teleported by the gripper.
	# Disable sleeping so releasing always resumes gravity.
	cube.can_sleep = false
	cube.physics_material_override = PhysicsMaterial.new()
	cube.physics_material_override.friction = 0.8
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 0.16
	collider.shape = shape
	cube.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.16
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = robot.material(Color("f4ae40"))
	cube.add_child(visual)
	add_child(cube)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48
	add_child(camera)
	update_camera()

func _physics_process(delta: float) -> void:
	if not running or paused:
		return
	elapsed = minf(elapsed + delta, LIMIT)
	if autonomous:
		auto_step(delta)
	else:
		robot.drive(manual_forward, manual_turn)
	robot.step(delta)
	if robot.carrying:
		cube.global_position = robot.grip_position()
		cube.rotation = Vector3.ZERO
	if not robot.carrying and cube_in_goal() and cube.linear_velocity.length() < 0.12:
		release_wait += delta
		if release_wait >= 0.4:
			score = 100
			finish("Куб доставлен: +100 баллов")
	else:
		release_wait = 0.0
	if running and elapsed >= LIMIT:
		finish("Время истекло")
	changed.emit()

func start(auto: bool) -> void:
	reset_attempt()
	autonomous = auto
	running = true
	event.emit("Автономная попытка" if auto else "Ручная попытка")
	changed.emit()

func reset_attempt() -> void:
	running = false
	paused = false
	autonomous = false
	elapsed = 0
	score = 0
	phase = 0
	release_wait = 0
	manual_forward = 0
	manual_turn = 0
	robot.reset_robot(seed_value)
	cube.freeze = true
	cube.collision_layer = 1
	cube.collision_mask = 1
	cube.global_position = CUBE_START
	cube.rotation = Vector3.ZERO
	cube.linear_velocity = Vector3.ZERO
	cube.angular_velocity = Vector3.ZERO
	# Keep the object stationary until the next physics tick, including after reset.
	cube.set_deferred("freeze", false)
	cube.set_deferred("sleeping", false)
	changed.emit()

func toggle_pause() -> void:
	if not running:
		return
	paused = not paused
	robot.stop()
	cube.freeze = paused or robot.carrying
	event.emit("Пауза" if paused else "Продолжение")
	changed.emit()

func toggle_grip() -> void:
	if not running or paused:
		return
	if robot.carrying:
		robot.set_grip(false)
		cube.freeze = false
		cube.sleeping = false
		cube.collision_layer = 1
		cube.collision_mask = 1
		cube.linear_velocity = Vector3.ZERO
		event.emit("Захват открыт")
	elif robot.grip_position().distance_to(cube.global_position) < 0.19:
		robot.set_grip(true)
		cube.freeze = true
		cube.collision_layer = 0
		cube.collision_mask = 0
		event.emit("Куб захвачен")
	else:
		event.emit("Куб слишком далеко от захвата")

func auto_step(_delta: float) -> void:
	# Demonstration controller uses known coordinates, not a sensor-only program.
	match phase:
		0:
			if navigate(Vector3(CUBE_START.x, 0, CUBE_START.z + 0.34), 0.035):
				phase = 1
		1:
			if orient(0.0):
				robot.stop()
				toggle_grip()
				if robot.carrying:
					phase = 2
				else:
					finish("Не удалось захватить куб. Сбрось попытку.")
		2:
			if navigate(Vector3(GOAL.x, 0, GOAL.z + 0.32), 0.04):
				phase = 3
		3:
			if orient(0.0):
				robot.stop()
				toggle_grip()
				phase = 4
		4:
			robot.stop()

func navigate(target: Vector3, tolerance: float) -> bool:
	var offset := target - robot.global_position
	offset.y = 0
	if offset.length() < tolerance:
		robot.stop()
		return true
	var heading := atan2(-offset.x, -offset.z)
	var error := wrapf(heading - robot.rotation.y, -PI, PI)
	var forward := clampf(offset.length() * 1.8, 0.08, 0.75) if absf(error) < 0.35 else 0.0
	robot.drive(forward, clampf(error * 1.4, -0.75, 0.75))
	return false

func orient(heading: float) -> bool:
	var error := wrapf(heading - robot.rotation.y, -PI, PI)
	if absf(error) < 0.03:
		robot.stop()
		return true
	robot.drive(0, clampf(error * 1.5, -0.6, 0.6))
	return false

func cube_in_goal() -> bool:
	var p := cube.global_position
	# Require the entire 16 cm cube inside the zone, resting on the table.
	var basis := cube.global_basis
	var extent_x := 0.08 * (absf(basis.x.x) + absf(basis.y.x) + absf(basis.z.x))
	var extent_z := 0.08 * (absf(basis.x.z) + absf(basis.y.z) + absf(basis.z.z))
	return absf(p.x - GOAL.x) <= GOAL_HALF.x - extent_x and absf(p.z - GOAL.z) <= GOAL_HALF.y - extent_z and p.y < 0.13

func finish(message: String) -> void:
	running = false
	robot.stop()
	event.emit(message)
	changed.emit()

func update_camera() -> void:
	camera.position = Vector3(sin(orbit) * cos(elevation), sin(elevation), cos(orbit) * cos(elevation)) * zoom
	camera.look_at(Vector3.ZERO)

func visual_box(size: Vector3, at: Vector3, color: Color, parent: Node = self) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	instance.material_override = mat
	parent.add_child(instance)

func static_box(size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	visual_box(size, Vector3.ZERO, color, body)
	add_child(body)

func label_3d(text: String, at: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.rotation.x = -PI / 2
	label.font_size = 40
	label.pixel_size = 0.0018
	label.modulate = color
	label.outline_size = 0
	add_child(label)
