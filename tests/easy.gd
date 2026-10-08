extends SceneTree
const Editor = preload("res://src/assembly_editor.gd")
const Easy = preload("res://src/easy_assembly.gd")
const Library = preload("res://src/part_library.gd")
const Connections = preload("res://src/assembly_connections.gd")
const Store = preload("res://src/project_store.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var editor := Editor.new()
	editor.visible = false
	root.add_child(editor)
	await process_frame
	check(not editor.advanced.visible, "Simple interface by default")
	editor.select_catalog(editor.catalog_ids.find("metal_007"))
	editor.add_part()
	check(editor.assembly.size() == 1 and editor.simple_group == 1, "Take a platform, then show motors")
	editor.flip_assembly()
	check(Library.validate(editor.assembly).is_empty(), "Flipped platform remains valid")
	for side in range(2):
		editor.choose_step(1)
		editor.select_catalog(editor.catalog_ids.find("electronics_010"))
		check(not editor.previewing and not editor.simple_targets.is_empty(), "Picking a motor preserves assembly and highlights places")
		check(editor.simple_targets.size() > 2-side, "Motor can mount on arbitrary holes as well as named slots")
		check(editor.target_buttons.get_child_count() == 2-side, "Named large mount buttons avoid precision clicks")
		editor.target_buttons.get_child(0).pressed.emit()
		var motor := editor.selected
		check(editor.assembly[motor].id == "electronics_010" and Connections.component(editor.assembly, motor).has(0), "Motor automatically aligns to platform")
		check(Easy.fastening_ports(editor.assembly,motor).is_empty(), "Placement automatically fastens motor")
		check(editor.target_buttons.get_child_count() == 0, "Named mount buttons disappear after placement")
		check(Easy.fastening_ports(editor.assembly, motor).is_empty(), "Motor fastening uses real inventory screws")
		check(editor.simple_group == 2, "Next step shows wheels")
		editor.select_catalog(editor.catalog_ids.find("electronics_018"))
		check(editor.simple_targets.size() == 1, "Only an unoccupied motor shaft accepts the wheel")
		var viewport_position := editor.camera.unproject_position(editor.simple_targets[0].position)
		var ui_position := viewport_position * editor.view.size / Vector2(editor.view.get_child(0).size)
		check(editor.nearest_simple_target(ui_position) == 0, "Green target can be clicked in the viewport")
		editor.preview_simple_target(ui_position)
		check(editor.ghost_root.get_child_count() == 1 and editor.assembly.size() == 4+side*4, "Hover ghost does not consume parts")
		editor.place_simple(0)
		check(Library.validate(editor.assembly).is_empty(), "Motor, screws and wheel connections remain valid")
	check(editor.assembly.size() == 9, "Platform, two motors, two wheels and four screws")
	check(Connections.component(editor.assembly,0).size() == 9, "Entire robot is connected")
	var snapshot := editor.assembly.duplicate(true)
	editor.flip_assembly()
	check(Library.validate(editor.assembly).is_empty(), "Flip whole assembled robot together")
	editor.undo_step()
	check(editor.assembly == snapshot, "Undo restores exact prior assembly")
	var filename := "user://easy-assembly-test.json"
	check(Store.write_project(filename,{"speed":.65,"wheel_base":.3,"noise":.02,"seed":42},editor.assembly) == OK, "Save simple robot")
	var saved := Store.read_project(filename)
	check(not saved.has("error") and saved.assembly.size() == 9, "Reload simple motor mount connections")
	DirAccess.remove_absolute(filename)
	var invalid := {"part":0,"port":-1,"own":0}
	check(not Easy.place(editor.assembly,"electronics_018",invalid).is_empty() and editor.assembly == snapshot, "Failed placement is atomic")
	editor.choose_step(2)
	editor.select_catalog(editor.catalog_ids.find("electronics_018"))
	check(editor.simple_targets.is_empty(), "Occupied shafts cannot accept a second wheel")
	editor.cancel_pending()
	check(editor.pending_id.is_empty(), "Cancel returns held part without inventory changes")
	editor.set_assembly([])
	var part := {"id":"electronics_010","position":[0,0,0],"rotation":[0,0,0]}
	var full: Array = [part,part.duplicate(true)]
	check(not Easy.place(full,"electronics_010",{}).is_empty() and full.size() == 2, "Simple mode cannot exceed inventory")
	var little := snapshot.slice(0,2)
	little[0].erase("links")
	little[1].erase("links")
	for i in range(Library.find_part("metal_015").quantity):
		little.append({"id":"metal_015","position":[0,0,0],"rotation":[0,0,0]})
	var before := little.duplicate(true)
	check(not Easy.fasten_motor(little,1).is_empty() and little == before, "No partial fastening when screws are exhausted")
	var current_ports := Connections.ports
	Connections.ports = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/legacy/connections_v1.json")).parts
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/parts/legacy/easy_mounts_v1.json")).parts
	for id in extra:
		Connections.ports[id].append_array(extra[id])
	# Build the old version with legacy points, not a new file lacking a version field.
	var legacy: Array = [{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}]
	for side in range(2):
		check(Easy.place(legacy,"electronics_010",Easy.candidates(legacy,"electronics_010")[0]).is_empty(), "Legacy motor placement")
		var old_motor := legacy.size()-1
		for hole in [2,3]:
			check(Easy.place(legacy,"metal_015",{"part":old_motor,"port":hole,"own":0}).is_empty(), "Legacy fastening fixture")
		check(Easy.place(legacy,"electronics_018",Easy.candidates(legacy,"electronics_018")[0]).is_empty(), "Legacy wheel placement")
	Connections.ports = current_ports
	var legacy_file := FileAccess.open(filename,FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"version":1,"table":"training_delivery","robot":{"speed":.65,"wheel_base":.3,"noise":.02,"seed":42},"assembly":legacy}))
	legacy_file.close()
	var upgraded := Store.read_project(filename)
	check(not upgraded.has("error") and upgraded.assembly.size()==9, "Open and realign a 0.5.0 saved robot")
	if not upgraded.has("error"):
		check(Library.validate(upgraded.assembly).is_empty(), "Migrated motor and wheel geometry aligns")
	DirAccess.remove_absolute(filename)
	# A single selected hole does not guarantee that both motor screws fit.
	var fitted := 0
	var rejected := 0
	for destination in range(Connections.for_part("metal_007").size()):
		if not Connections.is_hole(Connections.for_part("metal_007")[destination].kind):
			continue
		var custom: Array = [{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}]
		var original := custom.duplicate(true)
		var error := Easy.install_motor(custom,{"part":0,"port":destination,"own":0},0)
		if error.is_empty():
			fitted += 1
			check(custom.size() == 4 and Library.validate(custom).is_empty(), "Matched motor mount includes screws and valid links")
			for h in [2,3]:
				check(Easy.matching_screw(custom,1,h) >= 0, "Both screws pass through actual platform holes")
		else:
			rejected += 1
			check(custom == original, "Misaligned screw pair leaves assembly unchanged")
	check(fitted > 0 and rejected > 0, "Only geometrically matching motor placements succeed")
	editor.set_assembly([{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}])
	editor.choose_step(4)
	editor.select_catalog(editor.catalog_ids.find("metal_001"))
	check(editor.simple_source.visible and editor.simple_source.item_count > 2, "Choose own hole without advanced mode")
	editor.simple_source.select(3)
	editor.simple_source.item_selected.emit(3)
	check(not editor.simple_targets.is_empty() and editor.simple_targets[0].own == 2, "Simple targets respect selected source hole")
	check(editor.simple_destination.visible and editor.simple_destination.item_count == editor.simple_targets.size()+1, "Every destination has an explicit list entry")
	editor.simple_destination.select(1)
	editor.simple_destination.item_selected.emit(1)
	check(editor.hover_target == 0 and editor.ghost_root.get_child_count() == 1, "Destination selection previews exact selected hole")
	editor.show_ghost(0)
	check(editor.ghost_root.get_child_count() == 1, "Preview direct hole attachment")
	editor.place_simple(0)
	check(editor.assembly.size() == 2 and Library.validate(editor.assembly).is_empty(), "Attach sheet through selected holes in simple mode")
	check(Store.write_project(filename,{"speed":.65,"wheel_base":.3,"noise":.02,"seed":42},editor.assembly) == OK and not Store.read_project(filename).has("error"), "Arbitrary hole attachment survives saving")
	DirAccess.remove_absolute(filename)
	editor.undo_step()
	check(editor.assembly.size() == 1, "Undo arbitrary hole attachment")
	var sensor: Array = [{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}]
	check(not Easy.candidates(sensor,"electronics_001").is_empty(), "Previously unmarked sensor can attach by its body")
	check(Easy.place(sensor,"electronics_001",Easy.candidates(sensor,"electronics_001")[8]).is_empty() and Library.validate(sensor).is_empty(), "Sensor body attachment remains valid")
	for own in [2,3]:
		var fitted_hole := false
		var base: Array = [{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}]
		for candidate in Easy.candidates(base,"electronics_010",own):
			var motor_assembly := base.duplicate(true)
			if Easy.install_motor(motor_assembly,candidate).is_empty():
				var source := Connections.world_port(motor_assembly[1],own)
				var destination := Connections.world_port(motor_assembly[0],candidate.port)
				check(source.position.distance_to(destination.position) < .0001, "Selected motor hole aligns exactly to selected platform hole")
				check(Library.validate(motor_assembly).is_empty(), "Explicit motor hole mount remains valid")
				fitted_hole = true
				break
		check(fitted_hole, "Each motor bolt hole can be selected for mounting")
	var ready := Easy.default_robot()
	check(ready.size() == 9 and Library.validate(ready).is_empty(), "Working default robot contains actual parts and screws")
	check(preload("res://src/assembly_runtime.gd").inspect(ready).can_drive, "Default robot drives with assembled motors")
	editor.set_assembly(snapshot)
	editor.load_default_robot()
	check(editor.assembly == ready, "Restore default robot")
	editor.undo_step()
	check(editor.assembly == snapshot, "Restore template is undoable")
	editor.start_empty_robot()
	check(editor.assembly.is_empty() and editor.simple_group == 0, "Start building from scratch")
	var loose: Array = [{"id":"electronics_010","position":[0,0,0],"rotation":[0,0,0]}]
	check(not Easy.fasten_motor(loose,0).is_empty() and loose.size()==1, "Loose motor cannot pretend to be fastened")
	var shortage: Array = [{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}]
	for i in range(Library.find_part("metal_015").quantity-1):
		shortage.append({"id":"metal_015","position":[0,0,0],"rotation":[0,0,0]})
	before = shortage.duplicate(true)
	check(not Easy.install_motor(shortage,Easy.candidates(shortage,"electronics_010")[0]).is_empty() and shortage==before, "Motor plus screws placement rolls back as one transaction")
	editor.queue_free()
	await process_frame
	print("EASY: ","PASS" if failures == 0 else "FAIL"," (",failures," failures)")
	quit(0 if failures == 0 else 1)
