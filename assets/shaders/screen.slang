struct PushConstants {
    uint flip;
};
[[vk::push_constant]]
PushConstants push_constants;

struct VertexOutput {
    float4 position : SV_Position;
    float2 tex_coord;
};

[shader("vertex")]
VertexOutput vertex_main(uint vertex_id : SV_VertexID) {
    VertexOutput output;
    float x = -1 + float((vertex_id & 1) << 2);
    float y = -1 + float((vertex_id & 2) << 1);
    output.position = float4(x, y, 0, 1);
    output.tex_coord = float2((x + 1) * 0.5, (y + 1) * 0.5);
    if (push_constants.flip != 0) {
        output.tex_coord.y = 1 - output.tex_coord.y;
    }
    return output;
}

Sampler2D texture;

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    return texture.Sample(input.tex_coord);
}
