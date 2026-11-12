extends SceneTree

## Headless check that the small city GLB imports dressed: every road, path,
## ground, wall and roof surface sits on a procedural city shader, and walls
## carry the facade data the shader lays windows/doors out from. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_city_dressing.gd
## (Rebuild the GLB first with assets/blender/maps/build_small_city.py.)

const CITY := "res://assets/city/westvillage_small.glb"
var _failures := 0


func _init() -> void:
	var building_sh: Shader = load("res://shader/city_building.gdshader")
	var ground_sh: Shader = load("res://shader/city_ground.gdshader")
	var scene: Node = load(CITY).instantiate()
	var sides := {}
	var modes := {}
	var undressed: Array[String] = []
	var bad_walls := 0
	var marker := -1.0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var nm := String(m.resource_name) if m else "<none>"
			var sm := m as ShaderMaterial
			if mi.name.begins_with("Building"):
				if sm == null or sm.shader != building_sh:
					undressed.append("%s/%s" % [mi.name, nm])
				elif not sm.get_shader_parameter("is_roof"):
					var s: int = sm.get_shader_parameter("side")
					sides[s] = sides.get(s, 0) + 1
					var a := mi.mesh.surface_get_arrays(i)
					if a[Mesh.ARRAY_TEX_UV2] == null or a[Mesh.ARRAY_COLOR] == null:
						bad_walls += 1
					elif marker < 0.0:
						marker = (a[Mesh.ARRAY_COLOR] as PackedColorArray)[0].b
			elif nm.begins_with("roads_") or nm.begins_with("paths_") or nm == "ground":
				if sm == null or sm.shader != ground_sh:
					undressed.append("%s/%s" % [mi.name, nm])
				else:
					var md: int = sm.get_shader_parameter("mode")
					modes[md] = modes.get(md, 0) + 1
					if md == 0:
						_check("ground has street mask", sm.get_shader_parameter("street_mask") != null)
						_check("ground has mask rect", (sm.get_shader_parameter("mask_rect") as Vector4).z > 100.0)
	_check("every city surface dressed (undressed: %s)" % [undressed.slice(0, 5)], undressed.is_empty())
	_check("walls carry UV2 + colour (%d bad)" % bad_walls, bad_walls == 0)
	_check("vertex colour arrives raw (B marker %.3f, want 0.5)" % marker, absf(marker - 0.5) < 0.01)
	for s in [0, 2, 3, 4]:  # back, street, main, party all occur in this crop
		_check("wall side %d present (%d surfaces)" % [s, sides.get(s, 0)], sides.get(s, 0) > 0)
	for md in [0, 1, 2, 3, 4]:  # ground, sidewalk, crossing, street, main street
		_check("ground mode %d present" % md, modes.has(md))
	scene.free()
	print("sides=%s modes=%s" % [sides, modes])
	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
