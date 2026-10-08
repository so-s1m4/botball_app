extends SceneTree
const Simulation = preload("res://src/simulation.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func fixture(sim) -> void:
	sim.start(false)
	sim.cube.freeze = false
	sim.cube.position = sim.robot.grip_position()
	sim.cube.linear_velocity = Vector3.ZERO
	sim.cube.angular_velocity = Vector3.ZERO
func run() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	await frames(3)
	fixture(sim)
	sim.toggle_grip()
	check(not sim.robot.carrying,"Closing must take time")
	await frames(90)
	print("HOLD ",sim.robot.carrying," contacts=",sim.gripper.last_contacts," pos=",sim.cube.position)
	check(sim.robot.carrying,"Two opposed pads hold a light cube")
	check(not sim.cube.freeze and sim.cube.collision_layer==1 and sim.cube.collision_mask==1,"Held cube remains a collidable rigid body")
	sim.toggle_pause()
	var opening: float = sim.gripper.opening
	var pos: Vector3 = sim.cube.position
	await frames(20)
	check(sim.cube.position==pos and sim.gripper.opening==opening,"Pause freezes jaws and payload")
	sim.toggle_pause()
	var velocity := Vector3(.2,0,-.3)
	sim.cube.linear_velocity = velocity
	sim.toggle_grip()
	check(sim.cube.linear_velocity==velocity,"Release preserves the object's own velocity")
	await frames(90)
	check(not sim.robot.carrying and sim.gripper.opening>.22,"Opening releases the cube gradually")
	fixture(sim)
	sim.gripper.friction = 0
	sim.toggle_grip()
	await frames(90)
	check(not sim.robot.carrying,"Frictionless pads cannot support a payload")
	sim.gripper.friction = .8
	fixture(sim)
	sim.cube.mass = 2
	sim.toggle_grip()
	await frames(90)
	check(not sim.robot.carrying,"Limited squeeze cannot hold excessive mass")
	sim.cube.mass = .05
	fixture(sim)
	sim.cube.position = sim.robot.to_global(Vector3(.17,.14,-.32))
	sim.toggle_grip()
	await frames(90)
	check(not sim.robot.carrying,"One-sided proximity does not attach the object")
	fixture(sim)
	sim.cube.position = sim.robot.to_global(Vector3(0,.14,-.7))
	sim.toggle_grip()
	await frames(90)
	check(not sim.robot.carrying,"Distant objects do not snap into jaws")
	sim.reset_attempt()
	check(not sim.gripper.engaged and not sim.gripper.closed and not sim.robot.carrying,"Reset clears contact state")
	# Isolated contact fixture: two real plate colliders, one assigned to an active servo branch.
	# The fixture drives collider poses directly to test moving contact anchors independently of gears.
	sim.robot.set_assembly([
		{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]},
		{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}])
	sim.robot.actuators.servos = [{"index":0,"followers":[0],"pivot":Vector3(0,.15,-.32),"locked":false}]
	sim.robot.servo_targets[0] = 90.0
	for i in range(2):
		sim.robot.part_colliders[i].transform = Transform3D(Basis(Vector3.BACK,PI/2),Vector3(-.094 if i==0 else .094,.15,-.32))
	sim.cube.position = sim.robot.to_global(Vector3(0,.15,-.32))
	sim.cube.linear_velocity = Vector3.ZERO
	sim.cube.angular_velocity = Vector3.ZERO
	sim.cube.freeze = false
	for i in range(45):
		sim.gripper.step(sim.robot,sim.cube,1.0/120)
		await physics_frame
	check(sim.robot.carrying and sim.robot.gripped_part==0,"Custom opposing plate contacts retain a dynamic payload")
	var height: float = sim.cube.position.y
	for i in range(120):
		for collider in sim.robot.part_colliders: collider.position.y += .0005
		sim.gripper.step(sim.robot,sim.cube,1.0/120)
		await physics_frame
	check(sim.cube.position.y>height+.045,"Friction anchor follows the moving custom jaw")
	sim.robot.part_colliders[0].position.x -= .10
	sim.gripper.step(sim.robot,sim.cube,1.0/120)
	check(not sim.robot.carrying and sim.robot.gripped_body==null,"Separated custom jaw releases without attaching the payload")
	sim.queue_free()
	await process_frame
	print("GRIPPER: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
