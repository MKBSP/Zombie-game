shader_type canvas_item;

uniform sampler2D visibility_tex : filter_linear, repeat_disable;
uniform float grid_w = 47.0;
uniform float grid_h = 47.0;
uniform float tile_size = 64.0;

// Camera info — set every frame from world.gd
uniform vec2 camera_top_left = vec2(0.0, 0.0);
uniform vec2 viewport_size = vec2(1280.0, 720.0);

void fragment() {
    // Convert screen UV to world pixel position
    vec2 world_pixel = camera_top_left + UV * viewport_size;

    // Convert world pixel to tile UV (0..1 across the grid)
    vec2 tile_uv = world_pixel / (vec2(grid_w, grid_h) * tile_size);

    // Sample visibility
    float vis = texture(visibility_tex, tile_uv).r;

    COLOR = vec4(0.0, 0.0, 0.0, 1.0 - vis);
}