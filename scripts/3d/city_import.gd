@tool
extends EditorScenePostImport
## Post-import for the OSM city GLBs built by
## assets/blender/maps/build_small_city.py: swaps blosm's flat materials for
## the procedural city shaders, by material name. Wall materials arrive as
## "<base>__<side>" where <base> is "wall" or an OSM building:colour hex (tint).
## Set as import_script/path in the .glb's .import file.

const BUILDING := preload("res://shader/city_building.gdshader")
const GROUND := preload("res://shader/city_ground.gdshader")
const SIDES := {"back": 0, "alley": 1, "street": 2, "main": 3, "party": 4}
## material -> [ground shader mode, road/strip half width in m]
const GROUND_MODES := {
	"ground": [0, 0.0], "paths_footway": [1, 2.0], "paths_crossing": [2, 2.0],
	"roads_residential": [3, 4.5], "roads_unclassified": [3, 4.5], "roads_secondary": [4, 5.0],
	"roads_service": [5, 3.0], "paths_cycleway": [6, 2.1], "areas_pedestrian": [7, 0.0],
}


func _post_import(scene: Node) -> Object:
	var mask_path := get_source_file().get_basename() + "_mask.png"
	var mask: Texture2D = load(mask_path) if ResourceLoader.exists(mask_path) else null
	var extras := _mask_extras(scene)
	var made := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			if not made.has(src.resource_name):
				made[src.resource_name] = _material_for(src, mask, extras)
			if made[src.resource_name]:
				mi.mesh.surface_set_material(i, made[src.resource_name])
	return scene


func _material_for(src: Material, mask: Texture2D, extras: Dictionary) -> Material:
	var mat_name := src.resource_name
	var col: Color = src.albedo_color if src is BaseMaterial3D else Color(0.8, 0.8, 0.8)
	var m := ShaderMaterial.new()
	m.resource_name = mat_name
	var parts := mat_name.split("__")
	if parts.size() == 2 and SIDES.has(parts[1]):
		m.shader = BUILDING
		m.set_shader_parameter("side", SIDES[parts[1]])
		_tint(m, parts[0], col)
	elif mat_name == "roof" or _is_hex(mat_name):
		m.shader = BUILDING
		m.set_shader_parameter("is_roof", true)
		_tint(m, mat_name, col)
	elif GROUND_MODES.has(mat_name):
		m.shader = GROUND
		m.set_shader_parameter("mode", GROUND_MODES[mat_name][0])
		m.set_shader_parameter("half_width", GROUND_MODES[mat_name][1])
		if GROUND_MODES[mat_name][0] == 0 and mask and extras.has("street_mask_rect"):
			var r: Array = extras["street_mask_rect"]
			m.set_shader_parameter("street_mask", mask)
			m.set_shader_parameter("mask_rect", Vector4(r[0], r[1], r[2], r[3]))
			m.set_shader_parameter("mask_range", extras.get("street_mask_range", 16.0))
	else:
		return null  # border, vegetation, ...: keep the glTF material
	return m


func _tint(m: ShaderMaterial, base: String, col: Color) -> void:
	if _is_hex(base):
		m.set_shader_parameter("use_tint", true)
		m.set_shader_parameter("tint", col)


func _is_hex(s: String) -> bool:
	return s.length() == 6 and s.is_valid_hex_number()


## The Blender script stores the mask rect on Ground-col; glTF extras land as
## node metadata "extras" (on the mesh node or a parent, depending on suffixes).
func _mask_extras(scene: Node) -> Dictionary:
	for n in [scene] + scene.find_children("*", "", true, false):
		var holders: Array = [n]
		if n is MeshInstance3D and n.mesh:
			holders.append(n.mesh)
		for h: Object in holders:
			if h.has_meta("extras") and h.get_meta("extras") is Dictionary and h.get_meta("extras").has("street_mask_rect"):
				return h.get_meta("extras")
	return {}
