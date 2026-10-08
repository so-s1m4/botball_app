extends RefCounted
## Compliant bilateral contact approximation. Objects remain dynamic and collidable.
var friction := 0.8
var squeeze_force := 3.0 # Estimated N per pad, not measured hardware data.
var closed := false
var opening := 0.225
var anchor := Vector3.ZERO
var engaged := false
var last_contacts := 0
var anchor_owner := -1
var previous_target := Vector3.ZERO

func reset() -> void:
	closed = false
	opening = .225
	engaged = false
	last_contacts = 0

func step(robot: RigidBody3D, object: RigidBody3D, delta: float) -> void:
	var contacts: Array = []
	if robot.assembly.is_empty():
		opening = move_toward(opening, .12 if closed else .225, .12*delta)
		for i in range(2):
			var sign_value := -1.0 if i == 0 else 1.0
			robot.fingers[i].position.x = sign_value*(opening/2+.0175)
			contacts.append({"pose":robot.global_transform*Transform3D(Basis.IDENTITY, robot.fingers[i].position),"size":Vector3(.035,.08,.26),"force":squeeze_force if closed else 0.0,"id":i})
	else:
		# Only servo-driven branches can actively clamp; a rigid chassis is not a gripper.
		for servo in robot.actuators.servos:
			if servo.locked or not robot.servo_targets.has(servo.index): continue
			for index in servo.followers:
				var collider: CollisionShape3D = robot.part_colliders[index]
				if not collider.shape is BoxShape3D: continue
				var lever: float = collider.position.distance_to(robot.assembly_root.position+servo.pivot)
				contacts.append({"pose":collider.global_transform,"size":collider.shape.size,"force":minf(10,robot.servo_torque/maxf(lever,.01)),"id":index})
		# Fixed surfaces provide the opposing jaw for a single-servo clamp.
		for index in range(robot.part_colliders.size()):
			var collider: CollisionShape3D = robot.part_colliders[index]
			if collider.shape is BoxShape3D:
				contacts.append({"pose":collider.global_transform,"size":collider.shape.size,"force":0.0,"id":index})
	var touching: Array = []
	for pad in contacts:
		var contact := contact_for(pad, object)
		if not contact.is_empty(): touching.append(contact)
	var pair: Array = []
	for a in range(touching.size()):
		for b in range(a+1,touching.size()):
			if touching[a].normal.dot(touching[b].normal)<-.9 and maxf(touching[a].force,touching[b].force)>0:
				pair = [touching[a],touching[b]]
				break
		if not pair.is_empty(): break
	last_contacts = pair.size()
	if robot.assembly.is_empty() and not pair.is_empty() and closed:
		# Rubber pads compress by at most 2 mm instead of passing through the cube.
		opening += maxf(0.0,minf(pair[0].depth,pair[1].depth)-.002)*2
	if pair.is_empty():
		# A first jaw pushes the object toward the opposing jaw; proximity alone cannot hold it.
		for contact in touching:
			if contact.depth <= 0 or contact.force <= 0: continue
			var speed: float = (object.linear_velocity-robot.linear_velocity).dot(contact.normal)
			var push: Vector3 = contact.normal*clampf(contact.depth*600-speed*3,0,contact.force)
			object.apply_central_force(push)
			robot.apply_force(-push,object.global_position-robot.global_position)
		engaged = false
		robot.carrying = false
		robot.gripped_body = null
		robot.gripped_part = -1
		return
	var support: Dictionary = pair[0] if pair[0].force>0 else pair[1]
	if not engaged or anchor_owner != support.id:
		anchor = support.pose.affine_inverse()*object.global_position
		previous_target = object.global_position
		anchor_owner = support.id
	engaged = true
	var target: Vector3 = support.pose*anchor
	var surface_velocity: Vector3 = (target-previous_target)/maxf(delta,.000001)
	previous_target = target
	var normal: Vector3 = pair[0].normal
	var relative: Vector3 = object.linear_velocity - surface_velocity
	var error: Vector3 = target-object.global_position
	var clamp_force: float = maxf(0.0,maxf(pair[0].force,pair[1].force))
	var limit: float = clamp_force*maxf(friction,0.0)*2
	var tangent: Vector3 = (error*180.0-relative*6.0-object.mass*Vector3(0,-9.8,0)).slide(normal).limit_length(limit)
	# Normal compliance centres the object between touching faces; friction is capped.
	var normal_force: Vector3 = normal*clampf((pair[0].depth-pair[1].depth)*600-relative.dot(normal)*3,-clamp_force,clamp_force)
	var force: Vector3 = tangent+normal_force
	object.apply_central_force(force)
	robot.apply_force(-force,object.global_position-robot.global_position)
	# Contact patches also resist rotation, with a finite torsional friction budget.
	var torque: Vector3 = (robot.angular_velocity-object.angular_velocity)*.02
	torque = torque.limit_length(limit*.04)
	object.apply_torque(torque)
	robot.apply_torque(-torque)
	robot.carrying = limit > object.mass*9.8 and error.length()<.04
	robot.gripped_body = object if robot.carrying else null
	robot.gripped_part = int(support.id) if robot.carrying and not robot.assembly.is_empty() else -1
	if robot.gripped_part >= 0:
		var bounds: AABB = robot.PartLibrary.meshes[robot.assembly[robot.gripped_part].id].get_aabb()
		robot.gripped_offset = bounds.get_center()+anchor

func contact_for(pad: Dictionary, object: RigidBody3D) -> Dictionary:
	var pose: Transform3D = pad.pose
	var local := pose.affine_inverse()*object.global_position
	var half: Vector3 = pad.size/2
	var gap := -INF
	var normal := Vector3.ZERO
	for axis in range(3):
		var direction: Vector3 = pose.basis[axis].normalized()
		var radius := .08*(absf(object.global_basis.x.dot(direction))+absf(object.global_basis.y.dot(direction))+absf(object.global_basis.z.dot(direction)))
		var separation: float = absf(local[axis])-half[axis]-radius
		if separation > gap:
			gap = separation
			normal = direction*signf(local[axis])
	if gap>.003 or gap<-.06: return {}
	return {"normal":normal,"depth":-gap,"force":pad.force,"pose":pose,"id":pad.id}
