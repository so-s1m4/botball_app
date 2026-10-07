extends RefCounted
## Runtime GLB import, independent of editor resource imports.
const MAP_DIRECTORY := "user://maps"
static func validate(config: Variant) -> String:
	if not config is Dictionary or not config.get("id", "training_delivery") in ["training_delivery", "obstacles", "custom"]:
		return "Неизвестная карта"
	if config.get("id", "training_delivery") != "custom":
		return ""
	if not config.get("path") is String or config.path.get_extension().to_lower() != "glb":
		return "Для своей карты нужен файл .glb"
	var scale_value = config.get("scale", 1.0)
	if not (scale_value is float or scale_value is int) or not is_finite(float(scale_value)) or scale_value <= 0 or scale_value > 10000:
		return "Неверный масштаб карты"
	if not config.get("fit", true) is bool or not config.get("name", "Своя карта") is String:
		return "Неверные настройки карты"
	return ""

static func import_glb(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "glb" or not FileAccess.file_exists(path):
		return {"error":"Выбери существующий файл .glb"}
	# Store a private copy so moving the original does not break saved projects.
	var digest := FileAccess.get_sha256(path)
	if digest.is_empty():
		return {"error":"Не удалось прочитать карту"}
	var stored := "%s/%s.glb" % [MAP_DIRECTORY,digest]
	var error := DirAccess.make_dir_recursive_absolute(MAP_DIRECTORY)
	if error != OK:
		return {"error":"Не удалось создать папку карт"}
	if not FileAccess.file_exists(stored):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		error = document.append_from_file(path,state)
		if error != OK:
			return {"error":"Не удалось открыть GLB: " + error_string(error)}
		# Re-export as a self-contained GLB, embedding any external textures/buffers.
		error = document.write_to_filesystem(state,stored)
		if error != OK:
			return {"error":"Не удалось сохранить копию карты"}
	return {"config":{"id":"custom","path":stored,"name":path.get_file().get_basename(),"fit":true,"scale":1.0}}

static func load_scene(config: Dictionary) -> Dictionary:
	var error := validate(config)
	if not error.is_empty():
		return {"error":error}
	if not FileAccess.file_exists(config.path):
		return {"error":"Файл карты не найден. Загрузи .glb снова."}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file(config.path, state)
	if result != OK:
		return {"error":"Не удалось открыть GLB: " + error_string(result)}
	var scene := document.generate_scene(state)
	if scene == null or not scene is Node3D:
		if scene != null:
			scene.free()
		return {"error":"В GLB нет 3D-сцены"}
	clean_scene(scene)
	var meshes: Array = []
	collect_meshes(scene, Transform3D.IDENTITY, meshes)
	if meshes.is_empty():
		scene.free()
		return {"error":"В GLB нет геометрии карты"}
	var bounds: AABB = meshes[0].bounds
	for item in meshes:
		bounds = bounds.merge(item.bounds)
	if not bounds.position.is_finite() or not bounds.size.is_finite() or maxf(bounds.size.x,bounds.size.z) < .00001:
		scene.free()
		return {"error":"Неверные размеры карты"}
	var factor: float = float(config.get("scale",1.0))
	if config.get("fit",true):
		factor *= minf(3.0 / maxf(bounds.size.x,.001), 2.4 / maxf(bounds.size.z,.001))
	var wrapper := Node3D.new()
	wrapper.name = "ImportedMap"
	wrapper.add_child(scene)
	# Keep the imported hierarchy unchanged inside a single placement transform.
	wrapper.scale = Vector3.ONE * factor
	wrapper.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z) * factor
	for item in meshes:
		var mesh: MeshInstance3D = item.node
		mesh.create_trimesh_collision()
	return {"scene":wrapper,"bounds":AABB(bounds.position*factor+wrapper.position,bounds.size*factor),"scale":factor}

static func clean_scene(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is Light3D or child is WorldEnvironment or child is AnimationPlayer:
			node.remove_child(child)
			child.free()
		else:
			clean_scene(child)

static func collect_meshes(node: Node, parent_pose: Transform3D, output: Array) -> void:
	var pose := parent_pose
	if node is Node3D:
		pose *= node.transform
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_surface_count() > 0:
		output.append({"node":node,"bounds":pose * node.mesh.get_aabb()})
	for child in node.get_children():
		collect_meshes(child,pose,output)
