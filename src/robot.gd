extends CharacterBody3D
## Simplified differential drive. Units: metres, seconds, radians.

var left_command := 0.0
var right_command := 0.0
var max_speed := 0.65
var wheel_base := 0.30
var motor_error := 0.02
var left_encoder := 0.0
var right_encoder := 0.0
var carrying := false
var rng := RandomNumberGenerator.new()
var sensor: RayCast3D
var fingers: Array[MeshInstance3D] = []
const Runtime = preload("res://src/assembly_runtime.gd")
const PartLibrary = preload("res://src/part_library.gd")
var assembly: Array = []
var assembly_root: Node3D
var training_visuals: Array[MeshInstance3D] = []
var training_collider: CollisionShape3D
var part_colliders: Array[CollisionShape3D] = []
var actuators := {"motors":[],"wheels":[],"servos":[],"wheel_base":0.0,"can_drive":false}
var wheel_angles: Dictionary = {}
var motor_commands: Dictionary = {}
var motor_encoders: Dictionary = {}

func _ready() -> void:
	var collider := CollisionShape3D.new()
	training_collider = collider
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.36, 0.28, 0.40)
	collider.shape = shape
	collider.position.y = 0.14
	add_child(collider)
	box(Vector3(0.32, 0.14, 0.38), Vector3(0, 0.18, 0), Color("e3e9ee"))
	box(Vector3(0.23, 0.07, 0.23), Vector3(0, 0.285, 0.015), Color("1e3349"))
	box(Vector3(0.10, 0.012, 0.08), Vector3(0, 0.327, -0.025), Color("39d7b7"))
	for x in [-0.19, 0.19]:
		for z in [-0.105, 0.105]:
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.082
			mesh.bottom_radius = 0.082
			mesh.height = 0.06
			wheel.mesh = mesh
			wheel.rotation.z = PI / 2
			wheel.position = Vector3(x, 0.085, z)
			wheel.material_override = material(Color("17212d"))
			add_child(wheel)
	for x in [-0.13, 0.13]:
		fingers.append(box(Vector3(0.035, 0.08, 0.26), Vector3(x, 0.13, -0.29), Color("f7b64c")))
	for child in get_children():
		if child is MeshInstance3D and not fingers.has(child):
			training_visuals.append(child)
	assembly_root = Node3D.new()
	add_child(assembly_root)
	sensor = RayCast3D.new()
	sensor.position = Vector3(0, 0.19, -0.23)
	sensor.target_position = Vector3(0, 0, -2.0)
	sensor.enabled = true
	add_child(sensor)
	rng.seed = 42

func step(delta: float) -> void:
	if not assembly.is_empty() and not actuators.can_drive:
		velocity = Vector3.ZERO
		animate_wheels(delta)
		return
	if not motor_commands.is_empty() and actuators.can_drive:
		var midpoint: float = (actuators.wheels.front().center.x + actuators.wheels.back().center.x)/2
		var left_sum := 0.0
		var right_sum := 0.0
		var left_count := 0
		var right_count := 0
		for wheel in actuators.wheels:
			if wheel.center.x < midpoint:
				left_sum += motor_commands.get(wheel.motor,0.0)
				left_count += 1
			else:
				right_sum += motor_commands.get(wheel.motor,0.0)
				right_count += 1
		left_command = left_sum/maxi(left_count,1)
		right_command = right_sum/maxi(right_count,1)
	var left := left_command * max_speed * (1.0 + rng.randf_range(-motor_error, motor_error))
	var right := right_command * max_speed * (1.0 + rng.randf_range(-motor_error, motor_error))
	left_encoder += left * delta
	right_encoder += right * delta
	rotation.y += (right - left) / (actuators.wheel_base if not assembly.is_empty() else wheel_base) * delta
	velocity = -global_transform.basis.z * (left + right) * 0.5
	velocity.y = -0.8
	move_and_slide()
	animate_wheels(delta)

func animate_wheels(delta: float) -> void:
	for wheel in actuators.wheels:
		var midpoint: float = (actuators.wheels.front().center.x+actuators.wheels.back().center.x)/2
		var speed: float = motor_commands.get(wheel.motor,0.0)*max_speed if not motor_commands.is_empty() else (left_command if wheel.center.x < midpoint else right_command)*max_speed
		var axis := PartLibrary.Connections.transform(assembly[wheel.wheel]).basis.y
		wheel_angles[wheel.wheel] = wheel_angles.get(wheel.wheel,0.0) - speed / wheel.radius * delta * signf(axis.x)
		motor_encoders[wheel.motor] = motor_encoders.get(wheel.motor,0.0) + speed*delta
	update_assembly_pose()

func drive(forward: float, turn: float) -> void:
	motor_commands.clear()
	left_command = clampf(forward - turn, -1, 1)
	right_command = clampf(forward + turn, -1, 1)

func stop() -> void:
	drive(0, 0)
	velocity = Vector3.ZERO

func reset_robot(seed_value: int) -> void:
	position = Vector3(-0.95, 0.015, 0.82)
	rotation = Vector3.ZERO
	left_encoder = 0
	right_encoder = 0
	rng.seed = seed_value
	set_grip(false)
	stop()
	wheel_angles.clear()
	motor_encoders.clear()
	for servo in actuators.servos:
		servo.angle = 90.0
	update_assembly_pose()

func set_grip(closed: bool) -> void:
	carrying = closed
	for i in range(fingers.size()):
		fingers[i].position.x = (-1.0 if i == 0 else 1.0) * (0.095 if closed else 0.13)

func grip_position() -> Vector3:
	return global_transform * Vector3(0, 0.14, -0.32)

func distance_sensor() -> float:
	sensor.force_raycast_update()
	if sensor.is_colliding():
		return sensor.global_position.distance_to(sensor.get_collision_point())
	return 2.0

func box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material(color)
	add_child(visual)
	return visual

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	return mat

func set_assembly(value: Array) -> void:
	assembly = value.duplicate(true)
	PartLibrary.populate(assembly_root, assembly)
	for visual in training_visuals:
		visual.visible = assembly.is_empty()
	for finger in fingers:
		finger.visible = assembly.is_empty()
	training_collider.disabled = not assembly.is_empty()
	for collider in part_colliders:
		remove_child(collider)
		collider.queue_free()
	part_colliders.clear()
	wheel_angles.clear()
	motor_encoders.clear()
	motor_commands.clear()
	actuators = Runtime.inspect(assembly)
	assembly_root.transform = Transform3D.IDENTITY
	if not assembly.is_empty():
		var bounds := AABB()
		var first := true
		for entry in assembly:
			var box: AABB = PartLibrary.Connections.transform(entry) * PartLibrary.meshes[entry.id].get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		assembly_root.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
		for entry in assembly:
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = PartLibrary.meshes[entry.id].get_aabb().size.max(Vector3.ONE*.0001)
			collider.shape = shape
			add_child(collider)
			part_colliders.append(collider)
	update_assembly_pose()

func update_assembly_pose() -> void:
	if assembly_root == null or assembly.is_empty():
		return
	var poses := Runtime.posed(assembly,actuators)
	for index in range(assembly.size()):
		var part: Node3D = assembly_root.get_child(index)
		part.transform = poses[index]
		if wheel_angles.has(index):
			part.rotate_object_local(Vector3.UP,wheel_angles[index])
		var center: Vector3 = PartLibrary.meshes[assembly[index].id].get_aabb().get_center()
		part_colliders[index].transform = assembly_root.transform * poses[index] * Transform3D(Basis.IDENTITY,center)

func set_servo_angle(index: int, angle: float) -> void:
	for servo in actuators.servos:
		if servo.index == index and not servo.locked:
			servo.angle = clampf(angle,0,180)
	update_assembly_pose()

func hardware_status() -> String:
	if assembly.is_empty():
		return "Учебный робот"
	if not actuators.can_drive:
		return "Для движения поставь 2 мотора, прикрути их и добавь 2 колеса Solarbotics. Серво можно проверить отдельно."
	return "Готов: 2 ведущих колеса · колея %.0f мм · серво: %d" % [actuators.wheel_base*1000,actuators.servos.size()]

func command_motor(port: float, power: float) -> String:
	if port != int(port) or port < 1 or port > (2 if assembly.is_empty() else actuators.motors.size()):
		return "нет мотора с номером %s" % port
	if absf(power) > 100:
		return "мощность мотора: от -100 до 100"
	if assembly.is_empty():
		if int(port) == 1:
			left_command = power/100.0
		else:
			right_command = power/100.0
	else:
		var motor: int = actuators.motors[int(port)-1]
		motor_commands[motor] = power/100.0
	return ""

func command_servo(port: float, angle: float) -> String:
	if port != int(port) or port < 1 or port > actuators.servos.size():
		return "нет серво с номером %s" % port
	if angle < 0 or angle > 180:
		return "угол серво: от 0 до 180°"
	var servo: Dictionary = actuators.servos[int(port)-1]
	if servo.locked:
		return "рычаг серво закреплён неподвижно: отсоедини лишнее крепление"
	set_servo_angle(servo.index,angle)
	return ""

func encoder_for_port(port: int) -> float:
	if assembly.is_empty():
		return left_encoder if port == 1 else right_encoder if port == 2 else 0.0
	if port < 1 or port > actuators.motors.size():
		return 0
	return motor_encoders.get(actuators.motors[port-1],0.0)

func command_drive(left: float, right: float) -> void:
	motor_commands.clear()
	left_command = left/100.0
	right_command = right/100.0
	if not assembly.is_empty() and not actuators.wheels.is_empty():
		var midpoint: float = (actuators.wheels.front().center.x+actuators.wheels.back().center.x)/2
		for wheel in actuators.wheels:
			motor_commands[wheel.motor] = left_command if wheel.center.x < midpoint else right_command
