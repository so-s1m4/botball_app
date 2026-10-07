extends SceneTree
const MapLoader = preload("res://src/map_loader.gd")
const Simulation = preload("res://src/simulation.gd")
const Store = preload("res://src/project_store.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := Node3D.new()
	scene.position = Vector3(15,0,-30)
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3,.1,2.4)
	base.mesh = box
	base.position.y = .05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a45725")
	base.material_override = material
	scene.add_child(base)
	var pillar := MeshInstance3D.new()
	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(.3,.4,.3)
	pillar.mesh = pillar_mesh
	pillar.position = Vector3(.4,.3,-.7)
	scene.add_child(pillar)
	var camera := Camera3D.new()
	scene.add_child(camera)
	root.add_child(scene)
	var source := "user://map-runtime-fixture.glb"
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_scene(scene,state) == OK and document.write_to_filesystem(state,source) == OK, "Produce an external GLB fixture")
	scene.queue_free()
	var imported := MapLoader.import_glb(source)
	check(imported.has("config"), "Copy imported GLB into persistent storage")
	var config: Dictionary = imported.config
	DirAccess.remove_absolute(source)
	check(FileAccess.file_exists(config.path), "Moving original GLB does not break map")
	var loaded := MapLoader.load_scene(config)
	check(not loaded.has("error"), "Load GLB directly without editor import")
	if loaded.has("error"):
		quit(1)
		return
	var bounds: AABB = loaded.bounds
	check(is_equal_approx(bounds.size.x,3) and is_equal_approx(bounds.size.z,2.4) and is_zero_approx(bounds.position.y), "Fit and centre translated GLB")
	var meshes: Array = []
	MapLoader.collect_meshes(loaded.scene,Transform3D.IDENTITY,meshes)
	check(meshes.size() == 2 and meshes[0].node.get_child_count() == 1, "Every imported mesh has static collision")
	check(not loaded.scene.find_children("*","Camera3D",true,false).size(), "Imported camera cannot replace simulator camera")
	check(meshes[0].node.mesh.surface_get_material(0).albedo_color.is_equal_approx(material.albedo_color), "Imported GLB retains materials")
	loaded.scene.free()
	var sim := Simulation.new()
	root.add_child(sim)
	await process_frame
	check(sim.set_map({"id":"obstacles"}).is_empty() and sim.map_config.id == "obstacles", "Switch built-in maps")
	var obstacles_count := sim.field_root.get_child_count()
	check(sim.set_map({"id":"training_delivery"}).is_empty() and sim.field_root.get_child_count() == obstacles_count-2, "Switch back removes obstacle collisions")
	check(sim.set_map(config).is_empty() and sim.imported_root != null, "Install custom map in simulation")
	await physics_frame
	await physics_frame
	await process_frame
	check(is_equal_approx(sim.robot_spawn_y,.115) and is_equal_approx(sim.cube_spawn_y,.20), "Spawn robot and cube on imported floor")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(.4,2,-.7),Vector3(.4,-1,-.7))
	var hit := sim.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and is_equal_approx(hit.position.y,.5), "GLB obstacle participates in physical collision")
	sim.reset_attempt()
	check(is_equal_approx(sim.robot.position.y,.115), "Attempt resets preserve custom floor height")
	var map_root := sim.imported_root
	check(not sim.set_map({"id":"custom","path":"user://missing-map.glb"}).is_empty() and sim.imported_root == map_root, "Failed import preserves active map")
	var project := "user://map-project-test.json"
	var settings := {"speed":.65,"wheel_base":.3,"noise":.02,"seed":42}
	check(Store.write_project(project,settings,[],config) == OK, "Save custom map selection")
	var restored := Store.read_project(project)
	check(not restored.has("error") and restored.map.path == config.path, "Saved project restores cached GLB reference")
	check(not MapLoader.validate({"id":"custom","path":config.path,"scale":INF}).is_empty(), "Reject nonfinite map scale")
	check(Store.write_project(project,settings) == OK and Store.read_project(project).map.id == "training_delivery", "Old projects default to training map")
	var doubled := config.duplicate(true)
	doubled.scale = 2
	loaded = MapLoader.load_scene(doubled)
	check(is_equal_approx(loaded.bounds.size.x,6), "Manual scale can adjust fitted map")
	loaded.scene.free()
	check(sim.set_map({"id":"training_delivery"}).is_empty() and sim.imported_root == null, "Return to built-in map removes custom scene")
	DirAccess.remove_absolute(config.path)
	DirAccess.remove_absolute(project)
	sim.queue_free()
	await process_frame
	print("MAPS: ","PASS" if failures == 0 else "FAIL"," (",failures," failures)")
	quit(0 if failures == 0 else 1)
