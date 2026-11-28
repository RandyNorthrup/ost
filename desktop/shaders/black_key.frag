#version 440
// A video drawn over black where its own picture is transparent (a WebM
// with an alpha channel, which the video decoder drops): the black
// becomes transparent again, near-black edges fade, so Teams' Communities
// animation sits on the page's background as Teams draws it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;

void main()
{
    vec4 c = texture(source, qt_TexCoord0);
    float a = smoothstep(0.01, 0.08, max(c.r, max(c.g, c.b)));
    // (premultiplied: the colour over black already carries its alpha)
    fragColor = vec4(c.rgb, a) * qt_Opacity;
}
