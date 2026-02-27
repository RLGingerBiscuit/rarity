struct Uniforms {
    float4x4 mvp;
};

struct VertexInput {
    float2 position;
    float3 colour;
};

struct VertexOutput {
    float4 position : SV_Position;
    float3 colour;
};

struct FragmentInput {
    float3 colour;
}

struct FragmentOutput {
    float4 colour : SV_Target;
};

uniform Uniforms uniforms;

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
    VertexOutput output;
    output.position = mul(uniforms.mvp, float4(input.position, 0, 1));
    output.colour = input.colour;
    return output;
}

[shader("fragment")]
FragmentOutput fragmentMain(FragmentInput input) {
    FragmentOutput output;
    output.colour = float4(input.colour, 1);
    return output;
}
