static const uint FLAG_MSDF    = 0x01;
static const uint FLAG_MTSDF   = 0x02;

struct PushConstants {
    float2 aemrange;
    float antialias_em;
    uint flags;
};
[[vk::push_constant]]
PushConstants push_constants;

struct VertexInput {
    float2 position;
    float2 tex_coord;
    float4 colour, outline_colour;
    float threshold_em;
    float outline_em;
    float roundness;
};

struct VertexOutput {
    float4 position : SV_Position;
    float2 tex_coord;
    float4 colour, outline_colour;
    float threshold_em;
    float outline_em;
    float roundness;
};

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    output.position = float4(input.position, 0, 1);
    output.colour = input.colour;
    output.outline_colour = input.outline_colour;
    output.threshold_em = input.threshold_em;
    output.outline_em = input.outline_em;
    output.roundness = input.roundness;
    output.tex_coord = input.tex_coord;
    return output;
}

Sampler2D msdf_texture;

float median(float3 v) {
    return max(min(v.x, v.y), min(max(v.x, v.y), v.z));
}

float screen_px_scale(float2 tex_coords) {
    uint width, height, levels;
    msdf_texture.GetDimensions(0, width, height, levels);
    float2 size = float2(width, height);
    float2 gradient = fwidth(tex_coords);
    float2 product = size * gradient;
    return max(0.5 * dot(size, gradient) / (product.x * product.y), 1);
}

float4 raw(VertexOutput input) {
    return msdf_texture.Sample(input.tex_coord);
}

// Adapted from: https://github.com/Chlumsky/msdfgen
float4 msdfgen(VertexOutput input) {
    float4 sample = msdf_texture.Sample(input.tex_coord);
    float d_msdf = median(sample.xyz);
    float d_screen_px = screen_px_scale(input.tex_coord) * (d_msdf - 0.5);
    // float d_screen_px = push_constants.screen_px_scale * (d_msdf - 0.5);
    float opacity = clamp(d_screen_px + 0.5, 0 ,1);
    float4 colour = input.colour * opacity;
    return colour;
}

float4 redblob_paint(float4 dst, float4 src, float threshold_em, float distance_em, float inverse_width) {
    float opacity = clamp(src.a * clamp((threshold_em - distance_em) * inverse_width + 0.5, 0, 1) - dst.a, 0, 1);
    return opacity * src + (1 - opacity) * dst;
}

// Adapted from: https://www.redblobgames.com/articles/sdf-fonts/
float4 redblob(VertexOutput input) {
    bool use_mtsdf = (push_constants.flags & FLAG_MTSDF) != 0;
    bool use_msdf = (push_constants.flags & FLAG_MSDF) != 0;

    float4 sample = msdf_texture.Sample(input.tex_coord);
    float d_msdf = median(sample.rgb);
    float d_sdf = lerp(d_msdf, sample.a, float(use_mtsdf));

    float sdf_distance_em = lerp(push_constants.aemrange.y, push_constants.aemrange.x, d_sdf);
    float msdf_distance_em = lerp(push_constants.aemrange.y, push_constants.aemrange.x, d_msdf);
    float distance_em = lerp(msdf_distance_em, sdf_distance_em, use_msdf ? clamp(input.roundness, 0, 1) : 0);

    float screen_px_scale = screen_px_scale(input.tex_coord);
    float inverse_width = screen_px_scale * push_constants.antialias_em;

    float4 frag_colour = float4(0, 0, 0, 0);
    frag_colour = redblob_paint(frag_colour, input.colour, input.threshold_em, distance_em, inverse_width);
    frag_colour = redblob_paint(frag_colour, input.outline_colour, input.threshold_em + input.outline_em, distance_em, inverse_width);
    return frag_colour;

   //  float opacity = clamp((input.threshold_em - distance_em) * inverse_width + 0.5, 0, 1);
   // return input.colour * opacity;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    return redblob(input);
}
