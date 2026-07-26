extends Node
class_name ZombieLighting

## Builds the zombie commander's shooter-style fog: ambient darkness +
## a soft radial vision light per zombie with LOS shadows. Reuses
## ShooterLighting's textures and occluder helpers. ZOMBIE-role view only;
## purely cosmetic (never replicated).
##
## Vision lights use shadow_item_cull_mask = 2: static occluders
## (occluder_light_mask = 3) cast vision shadows, entity occluders (mask 1)
## don't — so zombies never blot out their own or each other's vision.

const LIGHT_NAME := "ZCVisionLight"


## Ambient darkness + static occluders. Call once when the ZC view activates.
static func setup(
	world: Node2D,
	ground_layer: TileMapLayer,
	building_layer: TileMapLayer,
	props: Array[Node2D]
) -> void:
	var b: Dictionary = Balance.FOG_ZC
	var modulate := CanvasModulate.new()
	modulate.color = b.ambient_darkness
	world.add_child(modulate)
	var tile_size: float = ground_layer.tile_set.tile_size.x
	var positions := ShooterLighting.collect_static_occluder_positions(
		ground_layer, building_layer, props)
	ShooterLighting.build_static_occluders(world, positions, tile_size)


## Attach a vision light to any zombie that lacks one. Poll every frame on
## the ZC view — covers spawns, merges and NPC conversions. Lights are
## children, so they die with their zombie.
static func refresh_lights(tree: SceneTree, radial_tex: Texture2D) -> void:
	var b: Dictionary = Balance.FOG_ZC
	for z in tree.get_nodes_in_group("zombies"):
		if not (z is Node2D) or not is_instance_valid(z):
			continue
		if z.get_node_or_null(LIGHT_NAME) != null:
			continue
		var light := PointLight2D.new()
		light.name = LIGHT_NAME
		light.texture = radial_tex
		var vision: int = z.vision_range if "vision_range" in z else 2
		var radius_px := float(vision) * 64.0
		# Child of a scaled node (fat 1.5x, master 1.8x): divide the scale out.
		light.texture_scale = radius_px / (float(b.light_tex_size) / 2.0) / maxf(z.scale.x, 0.01)
		light.energy = b.light_energy
		light.blend_mode = Light2D.BLEND_MODE_MIX
		light.shadow_enabled = b.shadows_enabled
		light.shadow_item_cull_mask = 2  # statics only — entities never block vision
		z.add_child(light)
