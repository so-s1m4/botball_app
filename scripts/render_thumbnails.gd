extends SceneTree
## Run with a display / software OpenGL, after importing the project.
const Library = preload("res://src/part_library.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	Library.ensure_loaded()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(280, 208)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1b2a3c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dbe7f3")
	environment.environment.ambient_light_energy = 0.55
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 1.3
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_color = Color("94b9df")
	fill.light_energy = 0.6
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .0001
	camera.current = true
	world.add_child(camera)
	DirAccess.make_dir_recursive_absolute("res://assets/parts/thumbnails")
	for part in Library.parts:
		if not part.usable_on_robot:
			continue
		var instance := Library.create_part(part.id)
		world.add_child(instance)
		var bounds: AABB = instance.get_child(0).mesh.get_aabb()
		var center := bounds.get_center()
		camera.position = center + Vector3(1, .85, 1.4).normalized() * maxf(bounds.size.length() * 2, .02)
		camera.look_at(center)
		# Fit all corners in camera space, including long narrow parts.
		var half_width := 0.0
		var half_height := 0.0
		for corner in range(8):
			var point := camera.global_transform.affine_inverse() * bounds.get_endpoint(corner)
			half_width = maxf(half_width, absf(point.x))
			half_height = maxf(half_height, absf(point.y))
		camera.size = maxf(half_height * 2, half_width * 2 / (280.0 / 208.0)) * 1.25
		await process_frame
		await RenderingServer.frame_post_draw
		var error := viewport.get_texture().get_image().save_png("res://assets/parts/thumbnails/%s.png" % part.id)
		if error != OK:
			push_error("Thumbnail failed: " + part.id)
			quit(1)
			return
		world.remove_child(instance)
		instance.free()
	print("THUMBNAILS: 156 rendered")
	quit()
