extends RefCounted
## Small, repeatable transmission fixture with ideal bearing/guide supports.
const Connections = preload("res://src/assembly_connections.gd")
const Library = preload("res://src/part_library.gd")

static func port(id: String, kind: String, last: bool = false) -> int:
	var result := -1
	for i in range(Connections.for_part(id).size()):
		if Connections.for_part(id)[i].kind == kind:
			result = i
			if not last:
				break
	return result

static func part(id: String, center: Vector3 = Vector3.ZERO) -> Dictionary:
	Library.ensure_loaded()
	var size: Array = Library.models[id].size
	return {"id":id,"position":[center.x,center.y-float(size[1])/2,center.z],"rotation":[0,0,0]}

static func support(assembly: Array, moving: int, own: int, id: String, kind: String, mode: String, lower: float, upper: float) -> String:
	var target := port(id,kind)
	var point := Connections.world_port(assembly[moving],own)
	var fixed := part(id)
	var local: Dictionary = Connections.for_part(id)[target]
	var normal := Connections.vector(local.normal)
	var axis := normal.cross(-point.normal)
	var basis := Basis.IDENTITY
	if axis.length() > .00001:
		basis = Basis(axis.normalized(),acos(clampf(normal.dot(-point.normal),-1,1)))
	elif normal.dot(-point.normal) < 0:
		basis = Basis(Vector3.RIGHT if absf(normal.x) < .9 else Vector3.UP, PI)
	Connections.set_transform(fixed,Transform3D(basis,point.position-basis*Connections.vector(local.position)))
	assembly.append(fixed)
	return Connections.connect_parts(assembly,moving,own,assembly.size()-1,target,0,mode,lower,upper)

static func lift() -> Dictionary:
	var assembly: Array = [part("electronics_009"),part("metal_013"),part("lego_3648")]
	var error := Connections.connect_parts(assembly,1,port("metal_013","servo_socket",true),0,port("electronics_009","servo_output"))
	if not error.is_empty(): return {"error":error}
	# Last appended horn hole is the reverse face of its central fastening screw.
	error = Connections.connect_parts(assembly,2,port("lego_3648","axle_hole"),1,port("metal_013","hole_8_32",true))
	if not error.is_empty(): return {"error":error}
	var size: Array = Library.models.lego_3648.size
	var center := Connections.transform(assembly[2])*Vector3(0,float(size[1])/2,0)
	var gear_basis := Connections.transform(assembly[2]).basis
	var second := part("lego_4019")
	Connections.set_transform(second,Transform3D(gear_basis,center+gear_basis*Vector3(.020,-float(Library.models.lego_4019.size[1])/2,0)))
	assembly.append(second)
	error = support(assembly,3,port("lego_4019","axle_hole"),"lego_3700","pin_hole","hinge",-180,180)
	if not error.is_empty(): return {"error":error}
	# Rack pitch line lies 4 mm above its base; driven by the 16-tooth gear.
	var rack_part := part("lego_3743")
	Connections.set_transform(rack_part,Transform3D(gear_basis,center+gear_basis*Vector3(.020,-.008-.004,0)))
	assembly.append(rack_part)
	var rack := assembly.size()-1
	error = support(assembly,rack,port("lego_3743","stud_socket"),"lego_6587","stud","slider",-12,12)
	if not error.is_empty(): return {"error":error}
	# Turn the fixture into a vertical lift, place it above the table.
	var orientation := Transform3D(Basis(Vector3.BACK,PI/2)*gear_basis.inverse(),Vector3(0,.16,0))
	for entry in assembly:
		Connections.set_transform(entry,orientation*Connections.transform(entry))
	error = Library.validate(assembly)
	return {"assembly":assembly} if error.is_empty() else {"error":error}
