extends RefCounted
## Ideal constrained transmissions; metres/radians. Does not simulate tooth surfaces.
const Connections = preload("res://src/assembly_connections.gd")
const Library = preload("res://src/part_library.gd")
const TEETH := {"lego_3647":8, "lego_32270":12, "lego_6589":12, "lego_4019":16, "lego_32269":20, "lego_3648":24, "lego_32498":36, "lego_3649":40}
const MODULE := .001

static func rigid_branch(assembly: Array, start: int) -> Array[int]:
	var members: Array[int] = [start]
	var cursor := 0
	while cursor < members.size():
		var current := members[cursor]
		for link in assembly[current].get("links", []):
			if link.get("mode", "fixed") != "fixed":
				continue
			var kind: String = Connections.for_part(assembly[current].id)[int(link.port)].kind
			var other_kind: String = Connections.for_part(assembly[int(link.other)].id)[int(link.other_port)].kind
			if kind in ["servo_output"] or other_kind in ["servo_output"]:
				continue
			if not members.has(int(link.other)):
				members.append(int(link.other))
		cursor += 1
	return members

static func inspect(assembly: Array, servos: Array) -> Dictionary:
	var channels: Array = []
	for servo in servos:
		channels.append({"type":"servo", "locked":servo.locked, "root":servo.index, "parent":servo.index, "members":rigid_branch(assembly,int(servo.followers[0])) if not servo.followers.is_empty() else [], "pivot":servo.pivot, "axis":servo.axis, "value":0.0, "lower":-PI/2, "upper":PI/2})
	for i in range(assembly.size()):
		for link in assembly[i].get("links", []):
			if link.get("mode", "fixed") == "fixed" or link.moving != i:
				continue
			var point := Connections.world_port(assembly[i], int(link.port))
			var members := rigid_branch(assembly, i)
			channels.append({"type":link.mode, "root":i, "parent":int(link.other), "members":members, "pivot":point.position, "axis":Connections.transform(assembly[i]).basis.x if link.mode == "slider" else point.normal, "value":0.0, "lower":float(link.lower)/1000 if link.mode == "slider" else deg_to_rad(link.lower), "upper":float(link.upper)/1000 if link.mode == "slider" else deg_to_rad(link.upper), "locked":members.has(int(link.other))})
	# Moving supports carry their child hinges, guides and servo housings.
	var order: Array[int] = []
	for _pass in range(channels.size()+1):
		for c in range(channels.size()):
			if order.has(c):
				continue
			var waits := false
			for parent in range(channels.size()):
				if parent != c and channels[parent].members.has(channels[c].parent) and not order.has(parent):
					waits = true
			if not waits:
				order.append(c)
	for c in range(channels.size()):
		channels[c].descendants = channels[c].members.duplicate()
	for position in range(order.size()-1,-1,-1):
		var child := order[position]
		for parent in order:
			if parent != child and channels[parent].members.has(channels[child].parent):
				for member in channels[child].descendants:
					if not channels[parent].descendants.has(member):
						channels[parent].descendants.append(member)
	var gears: Array = []
	var racks: Array = []
	for i in range(assembly.size()):
		var id: String = assembly[i].id
		if not TEETH.has(id) and id != "lego_3743":
			continue
		var rest := Connections.transform(assembly[i])
		var size: Array = Library.models[id].size
		var center := rest * Vector3(0, float(size[1])/2, 0)
		var owner := -1
		for c in range(channels.size()):
			if channels[c].members.has(i):
				owner = c
		if TEETH.has(id):
			var axis := rest.basis.z.normalized()
			# Off-centre horn attachments orbit; they are not rotating pinions.
			if owner >= 0 and (channels[owner].type == "slider" or (center-channels[owner].pivot).cross(axis).length() > .0005 or absf(channels[owner].axis.dot(axis)) < .999):
				continue
			gears.append({"index":i,"owner":owner,"center":center,"axis":axis,"radius":float(TEETH[id])*MODULE/2})
		elif owner >= 0 and channels[owner].type == "slider":
			racks.append({"index":i,"owner":owner,"center":rest*Vector3(0,.004,0),"travel":rest.basis.x.normalized(),"normal":rest.basis.y.normalized(),"axis":rest.basis.z.normalized(),"length":float(size[0])})
	var edges: Array = []
	for a in range(gears.size()):
		var first: Dictionary = gears[a]
		for b in range(a+1,gears.size()):
			var second: Dictionary = gears[b]
			if first.owner == second.owner:
				continue
			var distance: Vector3 = second.center-first.center
			if absf(first.axis.dot(second.axis)) > .999 and absf(distance.dot(first.axis)) < .002 and absf(distance.slide(first.axis).length()-first.radius-second.radius) < .0006:
				var direction := 1.0
				if first.owner >= 0 and second.owner >= 0:
					direction = signf(channels[first.owner].axis.dot(channels[second.owner].axis))
				edges.append({"a":first.owner,"b":second.owner,"ratio":-first.radius/second.radius*direction})
		for rack in racks:
			if first.owner < 0 or first.owner == rack.owner:
				continue
			var distance: Vector3 = first.center-rack.center
			if absf(first.axis.dot(rack.axis)) > .999 and absf(distance.dot(rack.axis)) < .002 and absf(distance.dot(rack.normal)-first.radius) < .0006 and absf(distance.dot(rack.travel)) < rack.length/2:
				var sign_value: float = channels[first.owner].axis.cross(-rack.normal).dot(rack.travel)
				edges.append({"a":first.owner,"b":rack.owner,"ratio":first.radius*sign_value})
				# Stop at the last tooth rather than driving an infinitely long rack.
				channels[rack.owner].lower = maxf(channels[rack.owner].lower, distance.dot(rack.travel)-rack.length/2)
				channels[rack.owner].upper = minf(channels[rack.owner].upper, distance.dot(rack.travel)+rack.length/2)
	return {"channels":channels,"edges":edges,"order":order,"blocked":false,"message":""}

static func values(actuators: Dictionary) -> Dictionary:
	var state: Dictionary = actuators.get("mechanisms", {})
	if state.is_empty():
		return {}
	state.blocked = state.order.size() != state.channels.size()
	state.message = ""
	var result := {}
	var channels: Array = state.channels
	var queue: Array[int] = []
	for c in range(channels.size()):
		if channels[c].type == "servo":
			for servo in actuators.servos:
				if servo.index == channels[c].root:
					result[c] = deg_to_rad(servo.angle-90)
					queue.append(c)
	propagate(state, result, queue)
	state.driven = result.keys()
	state.free_roots = []
	for c in range(channels.size()):
		if result.has(c):
			continue
		state.free_roots.append(c)
		result[c] = channels[c].value
		propagate(state, result, [c])
	for c in result:
		if result[c] < channels[c].lower-.000001 or result[c] > channels[c].upper+.000001 or channels[c].get("locked", false) and absf(result[c]) > .00001:
			state.blocked = true
	if state.blocked:
		state.message = "Передача заблокирована: неподвижная шестерня, замкнутая связь или предел хода"
	return result

static func propagate(state: Dictionary, result: Dictionary, queue: Array) -> void:
	var cursor := 0
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		for edge in state.edges:
			if edge.a != current and edge.b != current:
				continue
			var other: int = edge.b if edge.a == current else edge.a
			var next_value: float = result[current]*edge.ratio if edge.a == current else result[current]/edge.ratio
			if other < 0:
				if absf(next_value) > .00001:
					state.blocked = true
			elif result.has(other):
				if absf(result[other]-next_value) > .00001:
					state.blocked = true
			else:
				result[other] = next_value
				queue.append(other)

static func posed(assembly: Array, actuators: Dictionary, poses: Array[Transform3D]) -> Array[Transform3D]:
	var state: Dictionary = actuators.get("mechanisms", {})
	if state.is_empty():
		return poses
	var coordinates := values(actuators)
	for c in state.order:
		var joint: Dictionary = state.channels[c]
		if joint.get("locked",false):
			continue
		var parent_delta: Transform3D = poses[joint.parent]*Connections.transform(assembly[joint.parent]).affine_inverse()
		var axis: Vector3 = (parent_delta.basis*joint.axis).normalized()
		var pivot: Vector3 = parent_delta*joint.pivot
		var delta := Transform3D.IDENTITY
		var coordinate: float = coordinates.get(c, joint.value)
		if joint.type == "slider":
			delta.origin = axis*coordinate
		else:
			delta.basis = Basis(axis,coordinate)
			delta.origin = pivot-delta.basis*pivot
		for member in joint.descendants:
			poses[member] = delta*poses[member]
	return poses
