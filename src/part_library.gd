extends RefCounted
## Meshes and inventory share stable IDs; dimensions are metres.
const Connections = preload("res://src/assembly_connections.gd")
static var parts: Array = []
static var models: Dictionary = {}
static var meshes: Dictionary = {}
static var materials: Dictionary = {}
static var thumbnails: Dictionary = {}
static var surface_textures: Dictionary = {}

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
	# Keep imported multi-material colours while adding the same surface finish
	# used by generated models. Triplanar mapping also works on OBJ files without UVs.
	if not materials.has(id):
		var finishes: Array[StandardMaterial3D] = []
		for surface in range(visual.mesh.get_surface_count()):
			var original := visual.mesh.surface_get_material(surface)
			var mat: StandardMaterial3D = original.duplicate() if original is StandardMaterial3D and models[id].quality == "kipr" else StandardMaterial3D.new()
			apply_finish(mat, part, original is StandardMaterial3D and models[id].quality == "kipr")
			finishes.append(mat)
		materials[id] = finishes
	for surface in range(visual.mesh.get_surface_count()):
		visual.set_surface_override_material(surface, materials[id][surface])
	root.add_child(visual)
	return root

static func surface_texture(kind: String) -> NoiseTexture2D:
	if surface_textures.has(kind):
		return surface_textures[kind]
	var noise := FastNoiseLite.new()
	noise.seed = 2026
	noise.frequency = 0.18 if kind == "metal" else 0.45
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.as_normal_map = true
	texture.bump_strength = 0.45 if kind == "rubber" else 0.12 if kind == "metal" else 0.06
	surface_textures[kind] = texture
	return texture

static func apply_finish(mat: StandardMaterial3D, part: Dictionary, keep_color: bool) -> void:
	var name_lower: String = part.name.to_lower()
	var rubber: bool = "tire" in name_lower or "rubber" in name_lower or part.id == "electronics_018"
	var metal: bool = part.group == "metal" and not "servo horn" in name_lower and part.id != "metal_036"
	var kind := "rubber" if rubber else "metal" if metal else "plastic"
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not keep_color:
		mat.albedo_color = Color("b8c5d1") if metal else Color("273e56") if part.group == "electronics" else Color("efb541")
		if rubber or "pin" in name_lower or "axle" in name_lower:
			mat.albedo_color = Color("303b48")
		if "(black)" in name_lower:
			mat.albedo_color = Color("34383e")
		if "brass" in name_lower:
			mat.albedo_color = Color("b99a50")
	mat.metallic = 0.8 if metal else 0.0
	mat.roughness = 0.92 if rubber else 0.32 if metal else 0.28
	mat.normal_enabled = true
	mat.normal_texture = surface_texture(kind)
	mat.normal_scale = 0.65 if rubber else 0.3
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * (280.0 if rubber else 140.0)
	mat.clearcoat_enabled = not metal and not rubber
	mat.clearcoat = 0.18
	mat.clearcoat_roughness = 0.3

static func thumbnail(id: String) -> Texture2D:
	if not thumbnails.has(id):
		var path := "res://assets/parts/thumbnails/%s.png" % id
		if ResourceLoader.exists(path):
			thumbnails[id] = load(path)
	return thumbnails.get(id)

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
