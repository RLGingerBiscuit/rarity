static float2 positions[] = {
    float2(-0.5, -0.5),
    float2( 0  ,  0.5),
    float2( 0.5, -0.5)
};

static float3 colours[] = {
    float3(1, 0, 0),
    float3(0, 1, 0),
    float3(0, 0, 1)
};

struct VertexOutput {
    float3 colour;
    float4 position : SV_Position;
};

struct PixelInput {
    float3 colour;
}

struct PixelOutput {
    float4 colour : SV_Target;
};

[shader("vertex")]
VertexOutput vertexMain(uint vertex_id : SV_VertexID) {
    VertexOutput output;
    output.colour =   colours[vertex_id];
    output.position = float4(positions[vertex_id], 0, 1);
    return output;
}

[shader("pixel")]
PixelOutput pixelMain(PixelInput input : PixelInput) {
    PixelOutput output;
    output.colour = float4(input.colour, 1);
    return output;
}
