struct PushConstants {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};
[[vk_push_constant]]
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
VertexOutput vertexMain(VertexInput input) {
    VertexOutput output;
    output.position = mul(push_constants.projection, mul(push_constants.view, mul(push_constants.model, float4(input.position, 1))));
    output.colour = input.colour;
    output.tex_coord = input.tex_coord;
    return output;
}

Sampler2D texture;

[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target {
    return float4(input.colour.xyz * texture.Sample(input.tex_coord).xyz, input.colour.w);
}
