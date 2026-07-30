struct PushConstants {
    float4x4 projection;
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
    return output;
}

Sampler2D depth_texture;

float get_linear_depth(float depth, float4x4 projection) {
    float depth_ndc = depth * 2.0 - 1.0;
    return projection[2][3] / (depth_ndc + projection[2][2]);
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float4 depth = depth_texture.Gather(input.tex_coord);

    float linear_depth = get_linear_depth(depth.x, push_constants.projection);

    depth.x = get_linear_depth(depth.x, push_constants.projection);
    depth.y = get_linear_depth(depth.y, push_constants.projection);
    depth.z = get_linear_depth(depth.z, push_constants.projection);
    depth.w = get_linear_depth(depth.w, push_constants.projection);

    float4 abs_delta_z = abs(float4(linear_depth) - depth);
    float abs_delta_z_max = max(
        max(abs_delta_z.x, abs_delta_z.y),
        max(abs_delta_z.z, abs_delta_z.w)
    );

    float threshold = 0.065 * linear_depth;

    if (abs_delta_z_max < threshold)
        discard;

    return float4(1.0, 0.0, 0.0, 1.0);
}
