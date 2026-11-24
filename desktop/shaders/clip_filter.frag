#version 440
// The clip recorder's Filter, as Stream's smart-filter graph applies it to
// the whole picture (camera, backdrop, board, screen) in this order: LUT,
// animated sprite overlay, two-tone, exposure, contrast boost, image
// overlay. Text, drawings, stickers and the frame lie above, unfiltered.
// Texture coordinates have their origin at the top left.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float lutMode;      // 0 none, 16 (a 256 x 16 strip, green up) or 64 (8 x 8 tiles)
    float lutIntensity;
    float spriteOn;
    float spriteIndex;
    float spriteCols;
    float spriteRows;
    float blendMode;    // 0 ADD, 1 SCREEN, 2 MULTIPLY
    float spriteOpacity;
    float twoToneOn;
    vec4 colorA;
    vec4 colorB;
    float exposure;     // 1: off
    float contrastAmt;  // contrast - 1; 0: off
    float overlayMode;  // 0 none, 1 multiply, 2 overlay by the texel's alpha
    vec2 overlayRepeat;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D lut;
layout(binding = 3) uniform sampler2D sprite;
layout(binding = 4) uniform sampler2D overlay;

vec3 lut16(vec3 c)
{
    // Stream's own factors (15.5/256 for red), kept to match it.
    float rU = c.r * (15.5 / 256.0);
    float v = 1.0 - (c.g * 15.0 + 0.5) / 16.0;
    float b1 = floor(c.b * 15.0);
    float b2 = min(b1 + 1.0, 15.0);
    vec3 s1 = texture(lut, vec2(rU + b1 / 16.0, v)).rgb;
    vec3 s2 = texture(lut, vec2(rU + b2 / 16.0, v)).rgb;
    return mix(s1, s2, fract(c.b * 15.0));
}

vec3 lut64(vec3 c)
{
    float bc = c.b * 63.0;
    vec2 q1 = vec2(mod(floor(bc), 8.0), floor(floor(bc) / 8.0));
    vec2 q2 = vec2(mod(ceil(bc), 8.0), floor(ceil(bc) / 8.0));
    vec2 p1 = q1 * 0.125 + 0.0009765625 + 0.123046875 * c.rg;
    vec2 p2 = q2 * 0.125 + 0.0009765625 + 0.123046875 * c.rg;
    return mix(texture(lut, p1).rgb, texture(lut, p2).rgb, fract(bc));
}

void main()
{
    vec2 uv = qt_TexCoord0;
    vec4 src = texture(source, uv);
    vec3 c = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
    if (lutMode == 16.0)
        c = mix(c, lut16(c), lutIntensity);
    else if (lutMode == 64.0)
        c = mix(c, lut64(c), lutIntensity);
    if (spriteOn > 0.5) {
        vec2 cell = vec2(1.0 / spriteCols, 1.0 / spriteRows);
        vec2 org = vec2(mod(spriteIndex, spriteCols), floor(spriteIndex / spriteCols)) * cell;
        vec3 s = texture(sprite, org + uv * cell).rgb;
        vec3 b = blendMode == 0.0 ? min(c + s, 1.0) : blendMode == 1.0 ? 1.0 - (1.0 - c) * (1.0 - s) : c * s;
        c = b * spriteOpacity + c * (1.0 - spriteOpacity);
    }
    if (twoToneOn > 0.5) {
        float L = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
        c = mix(colorA.rgb, colorB.rgb, L);
    }
    c *= exposure;
    if (contrastAmt != 0.0)
        c = mix(c, clamp(c * c * (3.0 - 2.0 * contrastAmt), 0.0, 1.0), contrastAmt);
    if (overlayMode == 1.0) {
        c *= texture(overlay, fract(uv * overlayRepeat)).rgb;
    } else if (overlayMode == 2.0) {
        vec4 o = texture(overlay, fract(uv * overlayRepeat));
        // (Qt's textures are premultiplied.)
        o.rgb = o.a > 0.0 ? o.rgb / o.a : vec3(0.0);
        vec3 ov = mix(2.0 * c * o.rgb, 1.0 - 2.0 * (1.0 - c) * (1.0 - o.rgb), step(0.5, c));
        c = ov * o.a + c * (1.0 - o.a);
    }
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0) * qt_Opacity;
}
