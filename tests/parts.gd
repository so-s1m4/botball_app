extends SceneTree
const Library = preload("res://src/part_library.gd")
const Editor = preload("res://src/assembly_editor.gd")
const Store = preload("res://src/project_store.gd")
const Simulation = preload("res://src/simulation.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	Library.ensure_loaded()
	check(Library.parts.size() == 158 and Library.models.size() == 156,"Every installable catalog entry needs a model")
	for part in Library.parts:
		if not part.usable_on_robot:
			continue
		var instance := Library.create_part(part.id)
		check(instance.get_child_count() == 1,"Model missing: " + part.id)
		var mesh: Mesh = instance.get_child(0).mesh
		check(mesh != null and mesh.get_surface_count() > 0,"Geometry missing: " + part.id)
		var bounds := mesh.get_aabb().size
		var sizes: Array = Library.models[part.id].size
		check(bounds.is_equal_approx(Vector3(sizes[0],sizes[1],sizes[2])),"Manifest dimensions must match mesh: " + part.id)
		instance.free()
	var entry := {"id":"lego_32524","position":[0.016,0.008,-0.032],"rotation":[0,90,0]}
	check(Library.validate([entry]).is_empty(),"Valid assembly")
	var overused: Array = []
	for i in range(Library.find_part(entry.id).quantity+1):
		overused.append(entry.duplicate(true))
	check(not Library.validate(overused).is_empty(),"Reject exceeding inventory")
	for id in ["metal_037","metal_038","unknown"]:
		var bad := entry.duplicate(true)
		bad.id = id
		check(not Library.validate([bad]).is_empty(),"Reject tool or unknown ID")
	var invalid := entry.duplicate(true)
	invalid.position[0] = INF
	check(not Library.validate([invalid]).is_empty(),"Reject infinite placement")
	invalid.position = [0,0,0.601]
	check(not Library.validate([invalid]).is_empty(),"Reject out of range placement")
	invalid.position = [0,"bad",0]
	check(not Library.validate([invalid]).is_empty(),"Reject invalid placement type")
	var settings := {"speed":0.65,"wheel_base":0.3,"noise":0.02,"seed":42}
	var filename := "user://assembly-test.json"
	check(Store.write_project(filename,settings,[entry]) == OK,"Save assembly")
	var restored := Store.read_project(filename)
	check(restored.has("assembly") and restored.assembly.size() == 1 and restored.assembly[0].id == entry.id,"Restore inventory IDs")
	for axis in range(3):
		check(is_equal_approx(restored.assembly[0].position[axis],entry.position[axis]) and is_equal_approx(restored.assembly[0].rotation[axis],entry.rotation[axis]),"Restore part transforms")
	var file := FileAccess.open(filename,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"table":"training_delivery","robot":settings,"assembly":overused}))
	file.close()
	check(Store.read_project(filename).has("error"),"Reject overused parts in saved project")
	check(Store.write_project(filename,settings) == OK and Store.read_project(filename).assembly.is_empty(),"Backward compatible settings project")
	DirAccess.remove_absolute(filename)
	var editor := Editor.new()
	editor.visible = false
	root.add_child(editor)
	await process_frame
	var index := editor.catalog_ids.find(entry.id)
	editor.select_catalog(index)
	check(editor.previewing and editor.model_root.get_child_count() == 1,"Catalog selection previews real model")
	editor.add_part()
	check(editor.assembly.size() == 1 and not editor.previewing,"Add actual mesh to assembly")
	editor.fields[0].value = 16
	editor.fields[4].value = 90
	check(is_equal_approx(editor.assembly[0].position[0],0.016) and editor.assembly[0].rotation[1] == 90,"Edit transform")
	var sim := Simulation.new()
	root.add_child(sim)
	await process_frame
	sim.robot.set_assembly(editor.assembly)
	check(sim.robot.assembly_root.get_child_count() == 1 and not sim.robot.training_visuals[0].visible,"Mount assembly on field robot")
	sim.reset_attempt()
	check(sim.robot.assembly.size() == 1,"Attempt reset preserves assembly")
	editor.set_assembly(overused.slice(0,overused.size()-1))
	editor.select_catalog(editor.catalog_ids.find(entry.id))
	check(editor.add_button.disabled,"Block adding exhausted part")
	editor.add_part()
	check(editor.assembly.size() == Library.find_part(entry.id).quantity,"Cannot exceed quantity through editor")
	editor.select_installed(0)
	editor.remove_part()
	check(not editor.add_button.disabled,"Removing returns part to inventory")
	editor.set_assembly([])
	sim.robot.set_assembly([])
	check(sim.robot.training_visuals[0].visible,"Empty assembly restores training robot")
	editor.queue_free()
	sim.queue_free()
	await process_frame
	print("PARTS: ","PASS" if failures == 0 else "FAIL"," (",failures," failures)")
	quit(0 if failures == 0 else 1)
