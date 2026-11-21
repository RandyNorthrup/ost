#version 440
// The clip recorder's Board, as Stream's board block splits the picture:
// left of `ratio` the picture's middle strip (not squeezed), right of it
// the board's left part. ratio 0: the board fills the picture; 1: no board.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float ratio;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D board;

void main()
{
    vec2 uv = qt_TexCoord0;
    vec4 c = uv.x < ratio ? texture(source, vec2(uv.x + (1.0 - ratio) / 2.0, uv.y)) : texture(board, vec2(uv.x - ratio, uv.y));
    fragColor = c * qt_Opacity;
}
