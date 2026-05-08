shader_type canvas_item;

uniform sampler2D visibility_tex : filter_linear, repeat_disable;

void fragment() {
    float vis = texture(visibility_tex, UV).r;
    // vis = 0 → fully opaque (unexplored, black)
    // vis = 0.35 → mostly opaque (explored, dark grey overlay)
    // vis = 1.0 → fully transparent (currently visible)
    COLOR = vec4(0.0, 0.0, 0.0, 1.0 - vis);
}