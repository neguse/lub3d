// Simple triangle shader
// Compile with: sokol-shdc -i triangle.glsl -o triangle.h -l glsl410:glsl300es:hlsl5:metal_macos:wgsl -b

@vs vs
in vec2 pos;
in vec4 color0;
out vec4 color;

void main() {
    gl_Position = vec4(pos, 0.5, 1.0);
    color = color0;
}
@end

@fs fs
in vec4 color;
out vec4 frag_color;

void main() {
    frag_color = color;
}
@end

@program triangle vs fs
