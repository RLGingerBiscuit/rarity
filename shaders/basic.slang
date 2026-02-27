struct Uniforms {
    float4x4 mvp;
};
ConstantBuffer<Uniforms> uniforms;

struct VertexInput {
    float2 position;
    float3 colour;
};

struct VertexOutput {
    float4 position : SV_Position;
    float3 colour;
};

[shader("vertex")]
VertexOutput vertexMain(VertexInput input) {
    VertexOutput output;
    output.position = mul(uniforms.mvp, float4(input.position, 0, 1));
    output.colour = input.colour;
    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target {
    return float4(input.colour, 1);
}
