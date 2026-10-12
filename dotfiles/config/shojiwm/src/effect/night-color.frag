uniform vec3 night_gains;

vec4 shader_main(EffectContext effect) {
    vec4 color = texture2D(tex, effect.texture_uv);
    return vec4(color.rgb * night_gains, color.a);
}
