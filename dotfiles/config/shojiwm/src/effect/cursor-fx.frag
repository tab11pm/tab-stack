uniform float cursor_mode;
uniform vec2 cursor_origin;
uniform vec2 cursor_extent;
uniform vec2 cursor_pos;
uniform vec2 cursor_raw;
uniform float cursor_hot;

vec4 shader_main(EffectContext effect) {
    vec4 base = texture2D(tex, effect.texture_uv);
    if (cursor_mode < 0.5) return base;
    vec2 p = cursor_origin + effect.texture_uv * cursor_extent;
    vec3 color;
    float fill;
    float glow;
    if (cursor_mode < 1.5) {
        // Liquid drop: the lagging body is pulled toward the real pointer.
        float a = length(p - cursor_pos) - 13.0;
        float b = length(p - cursor_raw) - 4.0;
        float k = 14.0;
        float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        float sd = mix(b, a, h) - k * h * (1.0 - h);
        fill = 1.0 - smoothstep(-1.0, 1.0, sd);
        glow = exp(-max(sd, 0.0) / 9.0) * 0.4;
        color = mix(vec3(1.0, 0.6, 0.84), vec3(0.48, 0.36, 1.0), clamp(length(p - cursor_raw) / 28.0, 0.0, 1.0));
        fill *= 0.85;
    } else {
        // Ring: widens and turns mint over windows and panels.
        // A dot on the real pointer keeps clicks precise inside the lagging ring.
        float sd = min(abs(length(p - cursor_pos) - mix(15.0, 30.0, cursor_hot)) - 1.2,
                       length(p - cursor_raw) - 3.0);
        fill = 1.0 - smoothstep(-0.8, 0.8, sd);
        glow = exp(-max(sd, 0.0) / 6.0) * 0.25;
        color = mix(vec3(1.0), vec3(0.49, 1.0, 0.77), cursor_hot);
    }
    float a = clamp(fill + glow * (1.0 - fill), 0.0, 1.0);
    return vec4(base.rgb * (1.0 - a) + color * a * base.a, base.a);
}
