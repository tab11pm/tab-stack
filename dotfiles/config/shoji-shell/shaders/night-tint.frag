#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec3 gains;
};
layout(binding = 1) uniform sampler2D source;

// Same per-channel gains as shojiwm/src/effect/night-color.frag.
void main() {
    vec4 color = texture(source, qt_TexCoord0);
    fragColor = vec4(color.rgb * gains, color.a) * qt_Opacity;
}
