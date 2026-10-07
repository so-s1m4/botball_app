extends Node3D
## Training task, deliberately independent of official season rules.
signal changed
signal event(message: String)

const Program = preload("res://src/robot_program.gd")
const MapLoader = preload("res://src/map_loader.gd")
const Robot = preload("res://src/robot.gd")
const LIMIT := 60.0
const CUBE_START := Vector3(-0.55, 0.10, -0.45)
const GOAL := Vector3(0.90, 0, -0.62)
const GOAL_HALF := Vector2(0.38, 0.32)
var map_config := {"id":"training_delivery"}
var field_root: Node3D
var imported_root: Node3D
var camera_target := Vector3.ZERO
var camera_min_zoom := 2.3
var camera_max_zoom := 6.0
var map_revision := 0
var program: RefCounted
var program_mode := false
var program_output_count := 0
var program_source := ""
var paused_commands: Dictionary = {}
var map_ground := 0.0
var robot_spawn_y := .015
var cube_spawn_y := .10
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
	field_root = Node3D.new()
	add_child(field_root)
	build_training_field()
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
	elapsed = elapsed + delta if program_mode else minf(elapsed + delta, LIMIT)
	if program_mode:
		program.advance(delta,robot)
		while not program.output.is_empty():
			event.emit("print: " + program.output.pop_front())
		if not program.running:
			finish(program.error if not program.error.is_empty() else "Программа завершена")
			return
	elif autonomous:
		auto_step(delta)
	else:
		robot.drive(manual_forward, manual_turn)
	robot.step(delta)
	if robot.carrying:
		cube.global_position = robot.grip_position()
		cube.rotation = Vector3.ZERO
	if not robot.carrying and cube_in_goal() and cube.linear_velocity.length() < 0.12:
		release_wait += delta
		if release_wait >= 0.4 and score < 100:
			score = 100
			if program_mode:
				event.emit("Куб доставлен: +100 баллов")
			else:
				finish("Куб доставлен: +100 баллов")
	else:
		release_wait = 0.0
	if running and not program_mode and elapsed >= LIMIT:
		finish("Время истекло")
	changed.emit()

func start(auto: bool) -> void:
	reset_attempt()
	autonomous = auto
	running = true
	event.emit("Автономная попытка" if auto else "Ручная попытка")
	changed.emit()

func reset_attempt() -> void:
	if program != null:
		program.running = false
	program_mode = false
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
	robot.position.y = robot_spawn_y
	cube.freeze = true
	cube.collision_layer = 1
	cube.collision_mask = 1
	cube.global_position = Vector3(CUBE_START.x,cube_spawn_y,CUBE_START.z)
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
	if paused:
		paused_commands = {"left":robot.left_command,"right":robot.right_command,"motors":robot.motor_commands.duplicate()}
		robot.stop()
	elif program_mode and not paused_commands.is_empty():
		robot.left_command = paused_commands.left
		robot.right_command = paused_commands.right
		robot.motor_commands = paused_commands.motors.duplicate()
	cube.freeze = paused or robot.carrying
	event.emit("Пауза" if paused else "Продолжение")
	changed.emit()

func toggle_grip() -> void:
	if not running or paused:
		return
	if not robot.assembly.is_empty():
		event.emit("Для своей сборки управлять рычагом можно командой servo. Учебный захват доступен у учебного робота.")
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
			if navigate(Vector3(CUBE_START.x, map_ground, CUBE_START.z + 0.34), 0.035):
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
			if navigate(Vector3(GOAL.x, map_ground, GOAL.z + 0.32), 0.04):
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
	return absf(p.x - GOAL.x) <= GOAL_HALF.x - extent_x and absf(p.z - GOAL.z) <= GOAL_HALF.y - extent_z and p.y < map_ground + 0.13

func finish(message: String) -> void:
	running = false
	if program != null:
		program.running = false
	robot.stop()
	event.emit(message)
	changed.emit()

func update_camera() -> void:
	camera.position = camera_target + Vector3(sin(orbit) * cos(elevation), sin(elevation), cos(orbit) * cos(elevation)) * zoom
	camera.look_at(camera_target)

func visual_box(size: Vector3, at: Vector3, color: Color, parent: Node = null) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	instance.material_override = mat
	(parent if parent != null else field_root).add_child(instance)

func static_box(size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	visual_box(size, Vector3.ZERO, color, body)
	field_root.add_child(body)

func label_3d(text: String, at: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.rotation.x = -PI / 2
	label.font_size = 40
	label.pixel_size = 0.0018
	label.modulate = color
	label.outline_size = 0
	field_root.add_child(label)

func build_training_field() -> void:
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

func set_map(config: Dictionary) -> String:
	var error := MapLoader.validate(config)
	if not error.is_empty():
		return error
	var loaded: Dictionary = {}
	if config.id == "custom":
		loaded = MapLoader.load_scene(config)
		if loaded.has("error"):
			return loaded.error
	map_revision += 1
	# Load and validate before replacing the active map.
	for child in field_root.get_children():
		field_root.remove_child(child)
		child.queue_free()
	imported_root = null
	map_ground = 0
	robot_spawn_y = .015
	cube_spawn_y = .10
	map_config = config.duplicate(true)
	camera_target = Vector3.ZERO
	zoom = 3.8
	camera_min_zoom = 2.3
	camera_max_zoom = 6.0
	if config.id == "custom":
		imported_root = loaded.scene
		field_root.add_child(imported_root)
		# A support plane catches the robot if the imported scene has no floor.
		static_box(Vector3(3.0,.1,2.4),Vector3(0,-.055,0),Color("d5dedb"))
		var bounds: AABB = loaded.bounds
		camera_target = Vector3(0,bounds.size.y*.25,0)
		zoom = maxf(.1,bounds.size.length()*1.35)
		camera_min_zoom = maxf(.01,bounds.size.length()*.05)
		camera_max_zoom = maxf(6,bounds.size.length()*3)
		event.emit("Карта: " + config.get("name","Своя карта") + ". Геометрия и столкновения загружены.")
		call_deferred("place_on_imported_ground",map_revision)
	else:
		build_training_field()
		if config.id == "obstacles":
			static_box(Vector3(.18,.25,.6),Vector3(.25,.125,.55),Color("b18353"))
			static_box(Vector3(.45,.18,.16),Vector3(-.7,.09,-.9),Color("b18353"))
			event.emit("Карта: полоса препятствий")
		else:
			event.emit("Карта: учебный стол")
	reset_attempt()
	update_camera()
	return ""

func place_on_imported_ground(revision: int) -> void:
	await get_tree().physics_frame
	if map_config.id != "custom" or map_revision != revision:
		return
	var query := PhysicsRayQueryParameters3D.create(Vector3(GOAL.x,100,GOAL.z),Vector3(GOAL.x,-1,GOAL.z))
	query.exclude = [robot.get_rid(),cube.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	map_ground = float(hit.position.y) if not hit.is_empty() else 0.0
	for body in [robot,cube]:
		query.from = Vector3(body.position.x,100,body.position.z)
		query.to = Vector3(body.position.x,-1,body.position.z)
		hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			if body == robot:
				robot_spawn_y = hit.position.y + .015
			else:
				cube_spawn_y = hit.position.y + .10
	reset_attempt()
	visual_box(Vector3(GOAL_HALF.x*2,.005,GOAL_HALF.y*2),GOAL+Vector3(0,map_ground+.006,0),Color("52baa0"))
	label_3d("ДОСТАВКА · 100",GOAL+Vector3(0,map_ground+.016,.23),Color("125f50"))

func start_program(source: String) -> String:
	var compiled := Program.compile(source)
	if compiled.has("error"):
		return compiled.error
	reset_attempt()
	program_source = source
	program = Program.new()
	program.start(compiled)
	program_mode = true
	program_output_count = 0
	running = true
	event.emit("Программа запущена")
	changed.emit()
	return ""

func stop_program() -> void:
	if program != null:
		program.running = false
	finish("Программа остановлена")
