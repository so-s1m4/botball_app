extends RefCounted
## Meshes and inventory share stable IDs; dimensions are metres.
const Connections = preload("res://src/assembly_connections.gd")
static var parts: Array = []
static var models: Dictionary = {}
static var meshes: Dictionary = {}

static func ensure_loaded() -> void:
	if not parts.is_empty():
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts/botball_2026.json"))
	parts = catalog.parts
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/models.json"))
	models = manifest.models

static func find_part(id: String) -> Dictionary:
	ensure_loaded()
	for part in parts:
		if part.id == id:
			return part
	return {}

static func create_part(id: String) -> Node3D:
	ensure_loaded()
	var root := Node3D.new()
	root.name = id
	var part := find_part(id)
	if part.is_empty() or not models.has(id):
		return root
	if not meshes.has(id):
		meshes[id] = load(models[id].path)
	var visual := MeshInstance3D.new()
	visual.mesh = meshes[id]
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color("b8c5d1") if part.group == "metal" else Color("273e56") if part.group == "electronics" else Color("efb541")
	if "Tire" in part.name or "Wheel" in part.name or "Pin" in part.name:
		mat.albedo_color = Color("344457")
	mat.metallic = 0.65 if part.group == "metal" else 0.0
	mat.roughness = 0.55
	if models[id].quality != "kipr":
		visual.material_override = mat
	root.add_child(visual)
	return root

static func populate(parent: Node3D, assembly: Array) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	for entry in assembly:
		var part := create_part(entry.id)
		part.position = Vector3(entry.position[0], entry.position[1], entry.position[2])
		part.rotation_degrees = Vector3(entry.rotation[0], entry.rotation[1], entry.rotation[2])
		parent.add_child(part)

static func validate(assembly: Variant) -> String:
	ensure_loaded()
	if not assembly is Array or assembly.size() > 2048:
		return "Неверный формат сборки"
	var counts := {}
	for entry in assembly:
		if not entry is Dictionary or not entry.get("id") is String:
			return "Неверная деталь в сборке"
		var part := find_part(entry.id)
		if part.is_empty() or not part.usable_on_robot or not models.has(entry.id):
			return "Деталь недоступна: " + entry.id
		counts[entry.id] = counts.get(entry.id, 0) + 1
		if counts[entry.id] > part.quantity:
			return "Превышено количество: " + part.name
		for key in ["position", "rotation"]:
			var values = entry.get(key)
			if not values is Array or values.size() != 3:
				return "Неверное положение детали"
			for value in values:
				if not (value is int or value is float):
					return "Неверные координаты детали"
				if not is_finite(float(value)) or absf(float(value)) > (0.6 if key == "position" else 360.0):
					return "Координаты детали вне диапазона"
	return Connections.validate(assembly)
