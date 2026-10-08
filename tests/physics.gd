extends SceneTree
const Simulation = preload("res://src/simulation.gd")
const Easy = preload("res://src/easy_assembly.gd")
const Connections = preload("res://src/assembly_connections.gd")
const Library = preload("res://src/part_library.gd")
const MassModel = preload("res://src/assembly_physics.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func run() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	await frames(3)
	var build := Easy.default_robot()
	sim.robot.set_assembly(build)
	var expected := 0.0
	for entry in build: expected += MassModel.part_mass(entry.id)
	check(is_equal_approx(sim.robot.mass,expected),"Mass sums the installed parts")
	check(absf(sim.robot.center_of_mass.x)<.002,"Symmetric robot has balanced lateral COM")
	sim.start(false)
	sim.manual_forward = 1
	await frames(120)
	print("DRIVE position=",sim.robot.position," tilt=",sim.robot.tilt_degrees," contact=",sim.robot.ground_contacts," mass=",sim.robot.mass)
	check(sim.robot.position.z<.72,"Default assembled robot drives with forces")
	check(sim.robot.tilt_degrees<45,"Default assembly stays usable on level ground")
	sim.toggle_pause()
	var at: Vector3 = sim.robot.position
	var angle: Vector3 = sim.robot.rotation
	await frames(30)
	check(sim.robot.position.is_equal_approx(at) and sim.robot.rotation.is_equal_approx(angle),"Pause freezes translation and rotation")
	sim.toggle_pause()
	await frames(20)
	check(sim.robot.position.distance_to(at)>.001,"Resume restores motion")
	sim.reset_attempt()
	sim.robot.position.y = .8
	sim.running = true
	sim.manual_forward = 1
	await frames(20)
	check(sim.robot.position.y<.79 and sim.robot.ground_contacts==0,"Airborne robot falls and wheels lose grip")
	check(absf(sim.robot.linear_velocity.z)<.02,"Spinning wheels cannot propel robot in air")
	sim.reset_attempt()
	var heavy := build.duplicate(true)
	# A diagnostic overhanging payload; placement here deliberately bypasses connectors.
	heavy.append({"id":"electronics_010","position":[.30,.20,0],"rotation":[0,0,0]})
	heavy.append({"id":"electronics_010","position":[.30,.25,0],"rotation":[0,0,0]})
	sim.robot.set_assembly(heavy)
	check(sim.robot.mass>expected and sim.robot.center_of_mass.y>.06,"Overhanging parts increase mass and COM height")
	sim.start(false)
	await frames(240)
	print("OVERWEIGHT tilt=",sim.robot.tilt_degrees," rotation=",sim.robot.rotation)
	check(sim.robot.tilt_degrees>25,"Overhanging weight physically tips the robot")
	sim.reset_attempt()
	check(sim.robot.linear_velocity==Vector3.ZERO and sim.robot.angular_velocity==Vector3.ZERO and sim.robot.rotation==Vector3.ZERO,"Reset clears momentum and tipping")
	sim.robot.set_assembly(build)
	sim.start(false)
	sim.robot.position = Vector3(0,.015,-.8)
	sim.manual_forward = 1
	await frames(240)
	check(sim.robot.position.z>-1.24,"Body cannot drive through the table wall")
	sim.reset_attempt()
	var servo_build := build.duplicate(true)
	check(Easy.place(servo_build,"electronics_009",Easy.candidates(servo_build,"electronics_009")[0]).is_empty(),"Attach servo")
	check(Easy.place(servo_build,"metal_013",Easy.candidates(servo_build,"metal_013")[0]).is_empty(),"Attach moving horn")
	var horn_index := servo_build.size()-1
	var payload_index := servo_build.size()
	servo_build.append({"id":"metal_007","position":[.12,.18,0],"rotation":[0,0,0]})
	check(Connections.connect_parts(servo_build,payload_index,0,horn_index,1).is_empty(),"Attach payload through real marked holes")
	check(Library.validate(servo_build).is_empty(),"Loaded servo fixture has valid reciprocal connections")
	sim.robot.set_assembly(servo_build)
	var rest_com: Vector3 = sim.robot.center_of_mass
	sim.robot.command_servo(1,180)
	check(not sim.robot.center_of_mass.is_equal_approx(rest_com),"Moving servo payload updates COM")
	# Running servo commands move over time, never teleport their payload.
	sim.start(false)
	var servo: Dictionary = sim.robot.actuators.servos[0]
	var initial_angle: float = servo.angle
	sim.robot.command_servo(1, 150)
	check(servo.angle == initial_angle, "Running servo command only sets a target")
	await frames(12)
	check(servo.angle > initial_angle and servo.angle < 150, "Servo moves at a finite rate under payload load")
	sim.toggle_pause()
	var paused_angle: float = servo.angle
	await frames(12)
	check(servo.angle == paused_angle, "Pause freezes servo motion")
	sim.reset_attempt()
	sim.robot.set_assembly(build)
	sim.robot.friction = 0.0
	sim.start(false)
	sim.manual_forward = 1
	await frames(90)
	check(absf(sim.robot.position.z - .82) < .03, "Spinning tyres without friction cannot propel the body")
	check(sim.robot.encoder_for_port(1) > .2 and sim.robot.slip > .3, "Encoders measure wheel rotation even while slipping")
	sim.robot.friction = .85
	sim.reset_attempt()
	sim.start(false)
	sim.manual_forward = 1
	await frames(45)
	var driving_speed: float = absf(sim.robot.linear_velocity.z)
	check(driving_speed > .15, "Grip converts motor torque into body movement")
	sim.manual_forward = 0
	await frames(90)
	check(absf(sim.robot.linear_velocity.z) < driving_speed * .3, "Zero motor command brakes without teleporting the body")
	sim.reset_attempt()
	sim.robot.set_assembly([])
	sim.start(false)
	sim.cube.position = sim.robot.grip_position()
	sim.toggle_grip()
	await frames(90)
	check(sim.robot.carrying, "Pads hold the cube before release")
	sim.robot.linear_velocity = Vector3(.2, 0, -.3)
	sim.robot.angular_velocity = Vector3(0, 1, 0)
	sim.cube.linear_velocity = Vector3(.15, 0, -.25)
	sim.cube.angular_velocity = Vector3(0, .7, 0)
	var expected_release: Vector3 = sim.cube.linear_velocity
	var expected_spin: Vector3 = sim.cube.angular_velocity
	sim.toggle_grip()
	check(sim.cube.linear_velocity.is_equal_approx(expected_release) and sim.cube.angular_velocity == expected_spin, "Released dynamic payload preserves its own translation and rotation")
	sim.queue_free()
	await process_frame
	print("PHYSICS: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
