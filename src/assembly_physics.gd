extends RefCounted
## Estimated kilograms, not measured kit specifications. SI units throughout.
const Library = preload("res://src/part_library.gd")
const MASS_KG := {"electronics_010":0.045,"electronics_009":0.055,"electronics_011":0.012,"electronics_018":0.018,"metal_007":0.038,"metal_015":0.0015}

static func part_mass(id: String) -> float:
	if MASS_KG.has(id):
		return MASS_KG[id]
	var part := Library.find_part(id)
	var size: Array = Library.models[id].size
	var volume := float(size[0])*float(size[1])*float(size[2])
	var name: String = part.name.to_lower()
	if part.group == "metal":
		return clampf(volume * (1500.0 if "screw" in name or "nut" in name else 350.0),0.0005,0.25)
	if part.group == "lego":
		return clampf(volume*220.0,0.0003,0.05)
	if "battery" in name: return 0.15
	if "controller" in name or "wombat" in name: return 0.18
	return clampf(volume*600.0,0.003,0.20)

static func properties(assembly: Array, poses: Array[Transform3D], offset: Vector3) -> Dictionary:
	var total := 0.0
	var weighted := Vector3.ZERO
	var centers: Array[Vector3] = []
	var masses: Array[float] = []
	for i in range(assembly.size()):
		var m := part_mass(assembly[i].id)
		var center: Vector3 = offset + poses[i]*Library.meshes[assembly[i].id].get_aabb().get_center()
		centers.append(center)
		masses.append(m)
		total += m
		weighted += center*m
	var com := weighted/maxf(total,0.001)
	var inertia_value := Vector3.ZERO
	for i in range(assembly.size()):
		# Rotate each part's local inertia rather than using its enlarged world AABB.
		var size: Vector3 = Library.meshes[assembly[i].id].get_aabb().size
		var local_inertia := masses[i] * Vector3(size.y * size.y + size.z * size.z, size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y) / 12.0
		var basis := poses[i].basis.orthonormalized()
		var rotated := basis.x * basis.x * local_inertia.x + basis.y * basis.y * local_inertia.y + basis.z * basis.z * local_inertia.z
		var r := centers[i] - com
		inertia_value += rotated + masses[i] * Vector3(r.y * r.y + r.z * r.z, r.x * r.x + r.z * r.z, r.x * r.x + r.y * r.y)

	return {"mass":maxf(total,0.001),"center":com,"inertia":inertia_value.max(Vector3.ONE*0.00001)}
