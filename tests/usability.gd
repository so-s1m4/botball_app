extends SceneTree
const Editor = preload("res://src/assembly_editor.gd")
const Library = preload("res://src/part_library.gd")
const Easy = preload("res://src/easy_assembly.gd")
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
	var robot := Easy.default_robot()
	editor.set_assembly(robot)
	var originals := editor.model_root.get_children()
	var camera_position := editor.camera.position
	editor.select_installed(1)
	check(editor.camera.position.is_equal_approx(camera_position), "Selection preserves camera position")
	check(editor.model_root.get_children() == originals, "Selection reuses every existing model")
	editor.flip_assembly()
	var flipped := editor.assembly.duplicate(true)
	check_grid_clearance(editor)
	var saved_elevation := editor.elevation
	editor.elevation = -1.2
	editor.update_camera()
	check(not editor.grid_visual.visible, "Reference grid is hidden when inspecting the underside")
	editor.elevation = saved_elevation
	editor.update_camera()
	check(editor.grid_visual.visible, "Reference grid returns when inspecting from above")
	editor.undo_step()
	check(editor.assembly == robot and not editor.redo_button.disabled, "Undo enables redo")
	editor.redo_step()
	check(editor.assembly == flipped and editor.redo_button.disabled, "Redo restores exact transforms and connections")
	editor.undo_step()
	editor.remove_part()
	check(editor.redo_history.is_empty(), "New successful edit clears redo")
	editor.set_assembly(robot)
	editor.advanced_toggle.button_pressed = true
	editor.select_installed(1)
	editor.detach_selected()
	check(editor.assembly != robot, "Advanced detach changes connection graph")
	editor.undo_step()
	check(editor.assembly == robot, "Advanced detach can be undone")
	editor.redo_step()
	check(editor.assembly != robot, "Advanced detach can be redone")
	editor.undo_step()
	editor.select_installed(0)
	editor.fields[0].value += 8
	var moved := editor.assembly.duplicate(true)
	check(moved != robot, "Coordinate edit moves assembly")
	editor.fields[1].value -= 100
	check_grid_clearance(editor)
	editor.undo_step()
	editor.undo_step()
	check(editor.assembly == robot and is_equal_approx(editor.fields[0].value, robot[0].position[0]*1000), "Coordinate edit and displayed fields can be undone")
	editor.redo_step()
	check(editor.assembly == moved, "Coordinate edit can be redone")
	editor.advanced_toggle.button_pressed = false
	editor.set_assembly([{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}])
	editor.choose_step(1)
	editor.select_catalog(editor.catalog_ids.find("electronics_010"))
	check(editor.port_root.get_child_count() == 1 and editor.port_root.get_child(0) is MultiMeshInstance3D, "All simple target markers use one instanced draw")
	var valid := -1
	var invalid := -1
	for i in range(editor.simple_targets.size()):
		var preview := editor.assembly.duplicate(true)
		if Easy.install_motor(preview, editor.simple_targets[i]).is_empty():
			valid = i
		else:
			invalid = i
		if valid >= 0 and invalid >= 0:
			break
	check(valid >= 0 and invalid >= 0, "Fixture has both fitting and non-fitting motor holes")
	if invalid >= 0:
		editor.show_ghost(invalid)
		check(editor.place_button.disabled and not editor.placement_error.is_empty() and editor.ghost_root.get_child_count() == 0, "Invalid screw pair is explained before attachment")
	if valid >= 0:
		editor.show_ghost(valid)
		check(not editor.place_button.disabled and editor.ghost_root.get_child_count() == 3, "Motor preview includes the motor and both actual screws")
		check_grid_clearance(editor)
		check(editor.ghost_root.get_child(0).get_meta("part_id") == "electronics_010", "Motor preview shows the motor rather than the last screw")
		editor.turn_pending()
		# Rotation may invalidate a mount; resetting must reproduce the valid preview.
		editor.pending_twist = 0
		editor.show_ghost(valid)
		check(editor.assembly.size() == 1, "Preview never consumes inventory")
		editor.place_simple(valid)
		check(editor.assembly.size() == 4 and Library.validate(editor.assembly).is_empty(), "Confirmed preview matches a valid installed motor")
	var before := editor.target
	editor.pan_camera(Vector2(20, 10))
	check(not editor.target.is_equal_approx(before), "Camera can pan without moving robot")
	check(editor.view.get_child(0).render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "Hidden constructor does not continuously render")
	# Append and remove models without replacing the surviving instances.
	var parent := Node3D.new()
	root.add_child(parent)
	Library.populate(parent, robot.slice(0, 2))
	var first := parent.get_child(0)
	Library.populate(parent, robot)
	check(parent.get_child(0) == first and parent.get_child_count() == robot.size(), "Appending parts preserves existing model instances")
	Library.populate(parent, robot.slice(0, 1))
	check(parent.get_child_count() == 1 and parent.get_child(0) == first, "Removing trailing parts preserves surviving model")
	parent.queue_free()
	editor.queue_free()
	await process_frame
	print("USABILITY: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func check_grid_clearance(editor: Window) -> void:
	var grid_y: float = editor.grid_visual.position.y - .001
	for container in [editor.model_root, editor.ghost_root]:
		for part in container.get_children():
			var mesh: MeshInstance3D = part.get_child(0)
			var bounds: AABB = part.transform * mesh.transform * mesh.mesh.get_aabb()
			check(grid_y < bounds.position.y, "Reference grid lies below every displayed part")
