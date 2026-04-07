shader_type canvas_item;

// The 47x47 visibility texture (red channel = visibility level)
uniform sampler2D visibility_tex : filter_linear, repeat_disable;

// Grid dimensions in tiles
uniform float grid_w = 47.0;
uniform float grid_h = 47.0;

// Tile size in pixels
uniform float tile_size = 64.0;

void fragment() {
    // Convert screen UV to tile-space UV
    // The TextureRect covers the full map (grid_w * tile_size x grid_h * tile_size)
    // UV goes 0..1 across the TextureRect, which maps to 0..grid_w tiles
    vec2 tile_uv = UV;

    // Sample the visibility texture with linear filtering (smooth between tiles)
    float vis = texture(visibility_tex, tile_uv).r;

    // Black fog with alpha based on inverse visibility
    // vis = 0 → fully opaque black (fog)
    // vis = 0.5 → 50% opaque black (dim)
    // vis = 1.0 → fully transparent (lit)
    COLOR = vec4(0.0, 0.0, 0.0, 1.0 - vis);
}