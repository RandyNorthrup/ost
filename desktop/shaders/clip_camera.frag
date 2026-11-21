#version 440
// The camera in the clip recorder's picture, as Stream's Foreground and
// Pixelate blocks draw it:
// - mode 0: the camera as it is;
// - mode 1 (an image or video backdrop): you cut out by the person mask,
//   a = smoothstep(0.3, 0.8, mask), drawn premultiplied as cam * a, which
//   Stream's composition lays over the backdrop as bg (1 - a) + cam a^2;
// - mode 2 (Blur): you over the blurred picture by the same mask.
// pixelate (Bricks, Pixelated): the camera in 32 px blocks of the
// 1280 x 720 clip, sampled at each block's corner plus 16 px, as Stream.
// `content` is where the camera's picture lies in the item (normalised),
// so the mask, which covers the whole camera frame, lines up with it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float mode;
    float pixelate;
    float blurLod;
    vec4 content;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D mask;

vec4 blurred(vec2 uv)
{
    // A soft, strong blur from the mipmaps (nine taps at a low level).
    vec2 d = vec2(1.0 / 80.0, 1.0 / 45.0);
    vec4 s = vec4(0.0);
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++)
            s += textureLod(source, uv + vec2(float(x), float(y)) * d, blurLod) * (x == 0 && y == 0 ? 0.25 : (x == 0 || y == 0 ? 0.125 : 0.0625));
    return s;
}

void main()
{
    vec2 uv = qt_TexCoord0;
    if (pixelate > 0.5) {
        vec2 n = vec2(40.0, 22.0);
        uv = floor(n * uv) / n + vec2(16.0 / 1280.0, 16.0 / 720.0);
    }
    vec4 cam = texture(source, uv);
    if (mode < 0.5) {
        fragColor = cam * qt_Opacity;
        return;
    }
    vec2 m = (qt_TexCoord0 - content.xy) / content.zw;
    float p = (m.x < 0.0 || m.y < 0.0 || m.x > 1.0 || m.y > 1.0) ? 0.0 : texture(mask, m).r;
    float a = smoothstep(0.3, 0.8, p);
    if (mode < 1.5)
        fragColor = vec4(cam.rgb * a * a, a * cam.a) * qt_Opacity;
    else
        fragColor = mix(blurred(qt_TexCoord0), cam, a) * qt_Opacity;
}
