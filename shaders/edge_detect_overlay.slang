struct PushConstants {
    float4 colour;
};
[[vk::push_constant]]
PushConstants push_constants;

struct VertexOutput {
    float4 position : SV_Position;
    float4 colour;
    float2 tex_coord;
};

[shader("vertex")]
VertexOutput vertex_main(uint vertex_id : SV_VertexID) {
    VertexOutput output;
    float x = -1 + float((vertex_id & 1) << 2);
    float y = -1 + float((vertex_id & 2) << 1);
    output.position = float4(x, y, 0, 1);
    output.colour = push_constants.colour;
    output.tex_coord = float2((x + 1) * 0.5, (y + 1) * 0.5);
    return output;
}

Sampler2D texture;

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float edge = texture.Sample(input.tex_coord).r;

    if (!(edge > 0))
        discard;

    return input.colour;
}
