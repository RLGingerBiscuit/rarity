struct PushConstants {
    float4x4 mvp;
};
[[vk::push_constant]]
PushConstants push_constants;

struct VertexInput {
    float3 position;
    float4 colour;
    float2 tex_coord;
};

struct VertexOutput {
    float4 position : SV_Position;
    float4 colour;
    float2 tex_coord;
};

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    output.position = mul(push_constants.mvp, float4(input.position, 1));
    output.colour = input.colour;
    output.tex_coord = input.tex_coord;
    return output;
}

Sampler2D texture;

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    return float4(input.colour.xyz * texture.Sample(input.tex_coord).xyz, input.colour.w);
}
