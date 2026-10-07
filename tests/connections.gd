extends SceneTree
const Library = preload("res://src/part_library.gd")
const Connections = preload("res://src/assembly_connections.gd")
const Editor = preload("res://src/assembly_editor.gd")
const Store = preload("res://src/project_store.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func entry(id: String, x: float = 0) -> Dictionary:
	return {"id":id, "position":[x,0,0], "rotation":[0,0,0]}
func find_port(id: String, kind: String) -> int:
	var ports := Connections.for_part(id)
	for i in range(ports.size()):
		if ports[i].kind == kind:
			return i
	return -1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	Library.ensure_loaded()
	for id in Library.models:
		var size: Array = Library.models[id].size
		for port in Connections.for_part(id):
			var p := Connections.vector(port.position)
			check(absf(p.x) <= size[0]/2+.0001 and p.y >= -.0001 and p.y <= size[1]+.0001 and absf(p.z) <= size[2]/2+.0001, "Port must be inside model bounds: " + id)
			check(is_equal_approx(Connections.vector(port.normal).length(), 1), "Unit connector normal: " + id)
	var holes := Connections.for_part("lego_32524")
	check(holes.size() == 14, "Seven beam holes, two faces per hole")
	var pin := find_port("lego_2780", "pin")
	var assembly: Array = [entry("lego_32524"), entry("lego_2780", .1), entry("lego_32523", .2)]
	check(Connections.connect_parts(assembly,1,pin,0,0).is_empty(), "Insert friction pin into beam")
	check(Library.validate(assembly).is_empty(), "Connected assembly validates")
	check(not Connections.connect_parts(assembly,2,0,0,1).is_empty(), "Beam holes cannot connect without fastener")
	check(not Connections.connect_parts(assembly,1,pin,2,0).is_empty(), "Occupied pin end cannot be reused")
	check(Connections.connect_parts(assembly,2,0,1,1,90).is_empty(), "Second beam attaches to opposite end of pin")
	check(Library.validate(assembly).is_empty(), "Three-part connection validates")
	var before := Connections.transform(assembly[2])
	Connections.move_group(assembly,0,Transform3D(Basis(Vector3.UP, PI/2),Vector3(.1,.04,.1)))
	check(Connections.component(assembly,0).size() == 3 and not before.is_equal_approx(Connections.transform(assembly[2])), "Translate and rotate whole connected component")
	check(Library.validate(assembly).is_empty(), "Moving component preserves mating geometry")
	var filename := "user://connection-test.json"
	var settings := {"speed":.65, "wheel_base":.3, "noise":.02, "seed":42}
	check(Store.write_project(filename,settings,assembly) == OK, "Save connection graph")
	var restored := Store.read_project(filename)
	check(restored.has("assembly") and Connections.component(restored.assembly,0).size() == 3, "JSON reload preserves graph")
	DirAccess.remove_absolute(filename)
	var corrupt := assembly.duplicate(true)
	corrupt[1].links[0].other = 99
	check(not Library.validate(corrupt).is_empty(), "Reject missing linked instance")
	corrupt = assembly.duplicate(true)
	corrupt[1].links[0].port = 0.5
	check(not Library.validate(corrupt).is_empty(), "Reject fractional connection index")
	corrupt = assembly.duplicate(true)
	corrupt[1].position[0] += .01
	check(not Library.validate(corrupt).is_empty(), "Reject separated linked geometry")
	corrupt = assembly.duplicate(true)
	corrupt[0].links = "bad"
	check(not Library.validate(corrupt).is_empty(), "Reject malformed link list")
	Connections.detach(assembly,1)
	check(Connections.component(assembly,0).size() == 1 and Connections.component(assembly,2).size() == 1 and Library.validate(assembly).is_empty(), "Removing central fastener releases both beams")
	assembly = [entry("lego_32524"),entry("lego_2780"),entry("lego_32523")]
	Connections.connect_parts(assembly,2,0,1,0)
	Connections.remove(assembly,0)
	check(Library.validate(assembly).is_empty() and Connections.component(assembly,0).size() == 2, "Removing earlier instance reindexes retained links")
	var axles: Array = [entry("lego_32062"),entry("lego_32270",.1)]
	var shaft := find_port("lego_32062","axle")
	var bore := find_port("lego_32270","axle_hole")
	check(not Connections.connect_parts(axles,1,bore,0,shaft,45).is_empty(), "Reject 45-degree cross axle mating")
	check(Connections.connect_parts(axles,1,bore,0,shaft,90).is_empty() and Library.validate(axles).is_empty(), "Gear aligns cross profile onto axle")
	var occupied: Array = [entry("lego_32524"),entry("lego_2780"),entry("lego_2780",.1)]
	Connections.connect_parts(occupied,1,pin,0,0)
	check(Connections.occupied(occupied,0,1) and not Connections.connect_parts(occupied,2,pin,0,1).is_empty(), "Cannot insert another pin through opposite face of occupied hole")
	var loop: Array = [entry("lego_32524"),entry("lego_2780"),entry("lego_32524"),entry("lego_2780")]
	Connections.connect_parts(loop,1,pin,0,0)
	Connections.connect_parts(loop,2,0,1,1)
	Connections.connect_parts(loop,3,pin,0,3)
	var source := Connections.world_port(loop[3],1)
	var matching := -1
	for i in range(Connections.for_part(loop[2].id).size()):
		var candidate := Connections.world_port(loop[2],i)
		if source.position.distance_to(candidate.position) < .0001 and source.normal.dot(candidate.normal) < -.999:
			matching = i
	var loop_error := Connections.connect_parts(loop,3,1,2,matching)
	check(matching >= 0 and loop_error.is_empty(), "Second pin closes connection loop without moving existing assembly")
	check(Library.validate(loop).is_empty(), "Two beams with two pins validate")
	Connections.detach(loop,1)
	check(Connections.component(loop,0).size() == 3, "Removing one of two fasteners preserves connection through remaining pin")
	var plates: Array = [entry("lego_3023"),entry("lego_3710",.1)]
	check(Connections.connect_parts(plates,1,find_port("lego_3710","stud_socket"),0,find_port("lego_3023","stud"),90).is_empty() and Library.validate(plates).is_empty(), "LEGO plates snap socket to stud")
	check(is_equal_approx(plates[1].position[1],.0032), "Plate body height excludes protruding studs")
	var hardware: Array = [entry("metal_001"),entry("metal_015",.1),entry("metal_018",.2)]
	check(Connections.connect_parts(hardware,1,find_port("metal_015","bolt_8_32"),0,find_port("metal_001","hole_8_32")).is_empty(), "8-32 screw into sheet hole")
	check(Connections.connect_parts(hardware,2,find_port("metal_018","nut_8_32"),1,find_port("metal_015","thread_8_32")).is_empty(), "8-32 nut onto screw thread")
	check(Library.validate(hardware).is_empty(), "Fastener assembly validates")
	check(Connections.vector(Connections.for_part("metal_016")[0].normal).x > .999, "Imported screw inserts away from actual head")
	check(not Connections.compatible("thread_8_32","nut_m3"), "Reject wrong thread")
	var editor := Editor.new()
	editor.visible = false
	root.add_child(editor)
	await process_frame
	editor.set_assembly([entry("lego_32524"),entry("lego_2780",.1)])
	editor.select_installed(1)
	check(not editor.connect_button.disabled and not editor.picked_ports.is_empty(), "Editor presents compatible ports and markers")
	var selected_target := editor.target_part.get_selected_id()
	var selected_port := editor.target_port.get_selected_id()
	var point: Vector3 = Connections.world_port(editor.assembly[selected_target],selected_port).position
	var mouse := editor.camera.unproject_position(point) * editor.view.size / Vector2(editor.view.get_child(0).size)
	editor.pick_port(mouse)
	check(editor.target_part.get_selected_id() == selected_target and editor.target_port.get_selected_id() == selected_port, "Picking visible marker selects attachment")
	editor.attach_selected()
	check(Connections.component(editor.assembly,0).size() == 2, "Attach through actual editor controls")
	editor.fields[0].value += 24
	check(Library.validate(editor.assembly).is_empty(), "Editor coordinates move connected group")
	editor.detach_selected()
	check(Connections.component(editor.assembly,0).size() == 1, "Editor detach action")
	editor.set_assembly([entry("lego_32524")])
	editor.select_installed(0)
	editor.own_port.select(13)
	editor.select_catalog(editor.catalog_ids.find("lego_2780"))
	editor.add_part()
	check(editor.own_port.item_count == 2, "Adding a smaller connector resets previous port selection safely")
	editor.queue_free()
	await process_frame
	print("CONNECTIONS: ", "PASS" if failures == 0 else "FAIL", " (",failures," failures)")
	quit(0 if failures == 0 else 1)
