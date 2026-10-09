extends SceneTree
const Shared = preload("res://src/shared_robot.gd")
const Editor = preload("res://src/assembly_editor.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func wait_until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(.03).timeout
	check(predicate.call(), message)
func client() -> Node:
	var editor := Editor.new()
	editor.visible = false
	root.add_child(editor)
	var shared := Shared.new()
	shared.service = "http://127.0.0.1:8094"
	root.add_child(shared)
	shared.editor = editor
	shared.remote_changed.connect(func(value): editor.set_assembly(value))
	editor.assembly_changed.connect(func(_value): shared.local_changed(editor.assembly))
	return shared
func run() -> void:
	var a = client()
	var b = client()
	var fixture: Array = [{"id":"metal_007","position":[0,0,0],"rotation":[0,0,0]}, {"id":"metal_001","position":[.1,0,0],"rotation":[0,0,0]}]
	a.editor.set_assembly(fixture)
	a.create_room()
	await wait_until(func(): return not a.busy and Shared.valid_room(a.room), "First client creates a room")
	b.join_room(a.room)
	await wait_until(func(): return not b.busy and b.revision == 1, "Second client joins")
	check(b.editor.assembly.size() == 2, "Joining loads the shared robot")
	check(Shared.to_wire(Shared.from_wire(Shared.to_wire(a.editor.assembly)).assembly) == Shared.to_wire(a.editor.assembly), "Wire preserves stable identities")
	a.editor.assembly[0].position[0] = .02
	a.editor.commit()
	b.editor.assembly[1].position[1] = .03
	b.editor.commit()
	await wait_until(func(): return a.revision >= 3 and b.revision >= 3 and not a.dirty and not b.dirty and not a.busy and not b.busy, "Both clients receive merged concurrent edits")
	check(is_equal_approx(a.editor.assembly[0].position[0],.02) and is_equal_approx(a.editor.assembly[1].position[1],.03), "First client preserves both changes")
	check(is_equal_approx(b.editor.assembly[0].position[0],.02) and is_equal_approx(b.editor.assembly[1].position[1],.03), "Second client preserves both changes")
	# Edits queued during a request retain their own base while remote edits merge.
	a.editor.assembly[0].position[0] = .025
	a.editor.commit()
	a._process(.2)
	check(a.busy, "A write is in flight")
	a.editor.assembly[0].position[0] = .026
	a.editor.commit()
	b.editor.assembly[1].position[1] = .035
	b.editor.commit()
	await wait_until(func(): return a.revision >= 6 and b.revision >= 6 and not a.dirty and not b.dirty and not a.busy and not b.busy, "Queued and concurrent edits reach both clients")
	check(is_equal_approx(a.editor.assembly[0].position[0],.026) and is_equal_approx(a.editor.assembly[1].position[1],.035), "Queued edit preserves the other participant's update")
	# Two proposals from the same base touching one part must not overwrite each other.
	a.editor.assembly[0].position[0] = .04
	a.editor.commit()
	b.editor.assembly[0].position[0] = .05
	b.editor.commit()
	await wait_until(func(): return a.room.is_empty() or b.room.is_empty(), "Conflicting edits are reported")
	var loser = a if a.room.is_empty() else b
	check(is_equal_approx(loser.editor.assembly[0].position[0], .04 if loser == a else .05), "Conflicting local model remains available for export")
	check(loser.panel.visible, "Conflict notice is visible")
	var preserved: Array = b.editor.assembly.duplicate(true)
	a.leave()
	b.leave()
	b.service = "http://127.0.0.1:9"
	b.join_room("a".repeat(48))
	await wait_until(func(): return not b.busy and b.room.is_empty(), "Connection failure exits sharing")
	check(b.editor.assembly == preserved, "Offline client preserves its model")
	a.editor.queue_free()
	b.editor.queue_free()
	a.queue_free()
	b.queue_free()
	await process_frame
	print("SHARED ROBOT: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
