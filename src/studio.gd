extends RefCounted
## Shared, inexpensive studio lighting for the compatibility renderer.
static func install(world: Node3D, closeup: bool = false) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	environment.environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("242a31")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e3e8ee")
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("7f93a7")
	sky.sky_horizon_color = Color("edf0f2")
	sky.ground_bottom_color = Color("30353b")
	sky.ground_horizon_color = Color("a9adb0")
	env.sky.sky_material = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -32, 0)
	key.light_color = Color("fff1df")
	key.light_energy = 0.85
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 2.0 if closeup else 9.0
	key.shadow_bias = 0.025
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 135, 0)
	fill.light_color = Color("c8def1")
	fill.light_energy = 0.20
	world.add_child(fill)

static func wood_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c1a27c")
	material.roughness = 0.72
	var noise := FastNoiseLite.new()
	noise.seed = 318
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color("6f5036"))
	ramp.set_color(1, Color("debd8f"))
	texture.color_ramp = ramp
	material.albedo_texture = texture
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.5, 8, 12)
	return material
