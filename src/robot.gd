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

func _ready() -> void:
	var collider := CollisionShape3D.new()
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
	sensor = RayCast3D.new()
	sensor.position = Vector3(0, 0.19, -0.23)
	sensor.target_position = Vector3(0, 0, -2.0)
	sensor.enabled = true
	add_child(sensor)
	rng.seed = 42

func step(delta: float) -> void:
	var left := left_command * max_speed * (1.0 + rng.randf_range(-motor_error, motor_error))
	var right := right_command * max_speed * (1.0 + rng.randf_range(-motor_error, motor_error))
	left_encoder += left * delta
	right_encoder += right * delta
	rotation.y += (right - left) / wheel_base * delta
	velocity = -global_transform.basis.z * (left + right) * 0.5
	velocity.y = -0.8
	move_and_slide()

func drive(forward: float, turn: float) -> void:
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
