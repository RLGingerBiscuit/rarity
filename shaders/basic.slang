struct Uniforms {
    float4x4 mvp;
};
ConstantBuffer<Uniforms> uniforms;

struct VertexInput {
    float2 position;
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
    output.position = mul(uniforms.mvp, float4(input.position, 0, 1));
    output.colour = input.colour;
    output.tex_coord = input.tex_coord;
    return output;
}

Sampler2D texture;

[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target {
    return input.colour * texture.Sample(input.tex_coord);
}
