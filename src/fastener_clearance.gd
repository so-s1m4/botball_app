extends RefCounted
## Check the complete bolt against imported motor surfaces, in bolt coordinates.
static var motor_faces := PackedVector3Array()
static var motor_bounds := AABB()
static var triangle_bounds: Array[AABB] = []

static func intersects_motor(bolt: Transform3D, motor: Transform3D) -> bool:
	if motor_faces.is_empty():
		var mesh: Mesh = load("res://assets/parts/electronics_010.obj")
		motor_faces = mesh.get_faces()
		motor_bounds = mesh.get_aabb()
		for i in range(0,motor_faces.size(),3):
			triangle_bounds.append(AABB(motor_faces[i],Vector3.ZERO).expand(motor_faces[i+1]).expand(motor_faces[i+2]))
	var relative := bolt.affine_inverse() * motor
	var bounds: AABB = relative * motor_bounds
	if not bounds.intersects(AABB(Vector3(-.0035,0,-.0035),Vector3(.007,.00835,.007))):
		return false
	var search_bounds: AABB = relative.affine_inverse() * AABB(Vector3(-.0035,0,-.0035),Vector3(.007,.00835,.007))
	for i in range(0,motor_faces.size(),3):
		if not search_bounds.intersects(triangle_bounds[i/3]):
			continue
		var triangle: Array[Vector3] = [relative * motor_faces[i], relative * motor_faces[i+1], relative * motor_faces[i+2]]
		# 1/4-inch 8-32 shaft and head; allow contact at the seating plane.
		if cylinder_intersects(triangle,.00001,.00634,.0018) or cylinder_intersects(triangle,.00636,.00834,.0035):
			return true
	# A bolt entirely inside a closed case has no surface crossing.
	var inverse := relative.affine_inverse()
	return inside_motor(inverse * Vector3(0,.003175,0)) or inside_motor(inverse * Vector3(.002,.00735,0))

static func inside_motor(point: Vector3) -> bool:
	if not motor_bounds.has_point(point):
		return false
	var end := point + Vector3(.231,.137,.193)
	var hits: Array[float] = []
	for i in range(0,motor_faces.size(),3):
		var hit = Geometry3D.segment_intersects_triangle(point,end,motor_faces[i],motor_faces[i+1],motor_faces[i+2])
		if hit != null:
			hits.append(point.distance_to(hit))
	hits.sort()
	var count := 0
	var previous := -1.0
	for distance in hits:
		if distance - previous > .000001:
			count += 1
			previous = distance
	return count % 2 == 1

static func clip_y(polygon: Array[Vector3], plane: float, above: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var a_inside := a.y >= plane if above else a.y <= plane
		var b_inside := b.y >= plane if above else b.y <= plane
		if a_inside:
			result.append(a)
		if a_inside != b_inside:
			result.append(a.lerp(b,(plane-a.y)/(b.y-a.y)))
	return result

static func cylinder_intersects(triangle: Array[Vector3], low: float, high: float, radius: float) -> bool:
	var polygon := clip_y(clip_y(triangle,low,true),high,false)
	if polygon.is_empty():
		return false
	var projected := PackedVector2Array()
	for p in polygon:
		projected.append(Vector2(p.x,p.z))
	if projected.size() >= 3 and Geometry2D.is_point_in_polygon(Vector2.ZERO,projected):
		return true
	for i in range(projected.size()):
		var closest := Geometry2D.get_closest_point_to_segment(Vector2.ZERO,projected[i],projected[(i+1)%projected.size()])
		if closest.length_squared() < radius*radius - 0.0000000001:
			return true
	return false
