//
//  Shaders.metal
//  particles
//
//  Created by Naruki Chigira on 2020/06/12.
//  Copyright © 2020 Naruki Chigira. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

constant float POINT_SIZE = 150.0f;

struct Point {
    float4 position [[position]];
    float size [[point_size]];
};

vertex Point particle_vertex(const device packed_float2* positions [[ buffer(0) ]],
                                  constant vector_uint2 *viewportSizePointer  [[ buffer(1) ]],
                                  unsigned int vid [[ vertex_id ]])
{
    Point out;

    float2 position = positions[vid].xy;
    vector_float2 viewportSize = vector_float2(*viewportSizePointer);
    out.position = vector_float4(0.0f, 0.0f, 0.0f, 1.0f);
    out.position.xy = position / (viewportSize / 2.0f);

    out.size = POINT_SIZE;

    return out;
}

fragment float4 particle_fragment(float2 uv[[point_coord]], texture2d<float, access::sample> texture [[ texture(0) ]])
{
    constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
    float4 color = texture.sample(colorSampler, uv);
    return float4(0, 0, color[2], color[2]);
};

typedef struct {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} PlaneVertexIn;

typedef struct {
    float4 position [[position]];
    float2 texCoord;
} PlaneVertexOut;

vertex PlaneVertexOut threshold_vertex(PlaneVertexIn in [[stage_in]])
{
    PlaneVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 threshold_fragment(PlaneVertexOut in [[stage_in]], texture2d<float, access::sample> texture [[ texture(0) ]])
{
    constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
    float4 color = texture.sample(colorSampler, in.texCoord);
    float filled = color[2] > 0.3 ? 0.0 : 1.0;
    return float4(filled, filled, 1.0, 1.0);
}

