extends SceneTree
const Connections = preload("res://src/assembly_connections.gd")
const Easy = preload("res://src/easy_assembly.gd")
const Library = preload("res://src/part_library.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func entry(id: String) -> Dictionary:
	return {"id":id,"position":[0,0,0],"rotation":[0,0,0]}
func _initialize() -> void:
	for pair in [["lego_56145","lego_55976"],["lego_56145","lego_44309"],["lego_4185","lego_70162"]]:
		for reverse in [false,true]:
			var fixed: String = pair[1] if reverse else pair[0]
			var moving: String = pair[0] if reverse else pair[1]
			var assembly: Array = [entry(fixed)]
			var choices := Easy.candidates(assembly,moving)
			check(choices.size() == 1,"One matching tyre seat")
			if choices.is_empty():
				continue
			check(Easy.place(assembly,moving,choices[0],45).is_empty(),"Fit tyre in either order")
			check(Library.validate(assembly).is_empty(),"Wheel assembly validates")
			var a := Connections.transform(assembly[0]) * Vector3(0,Library.models[fixed].size[1]/2,0)
			var b := Connections.transform(assembly[1]) * Vector3(0,Library.models[moving].size[1]/2,0)
			check(a.distance_to(b) < .0001,"Disc and tyre centres coincide")
			check(Library.validate(JSON.parse_string(JSON.stringify(assembly))).is_empty(),"Saved tyre joint round trips")
			check(Easy.candidates(assembly,pair[1]).is_empty(),"Cannot fit second tyre to occupied seat")
			var rim_index := 1 if reverse else 0
			check(not Connections.occupied(assembly,rim_index,0),"Axle hole remains available")
			check(not Easy.candidates(assembly,"lego_3705").is_empty(),"Axle can attach to assembled wheel")
			Connections.detach(assembly,1)
			check(not Easy.candidates([assembly[0]],moving).is_empty(),"Detach frees tyre seat")
	check(Easy.candidates([entry("lego_4185")],"lego_55976").is_empty(),"Reject incompatible tyre diameter")
	check(Easy.candidates([entry("lego_56145")],"lego_70162").is_empty(),"Reject incompatible belt tyre")
	print("TIRES: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
