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

constant float POINT_SIZE = 100.0f;

struct ColorInOut {
    float4 position [[position]];
    float point_size [[point_size]];
};

vertex ColorInOut particle_vertex(const device packed_float2* positions [[ buffer(0) ]],
                                  constant vector_uint2 *viewportSizePointer  [[ buffer(1) ]],
                                  unsigned int vid [[ vertex_id ]])
{
    ColorInOut out;

    float2 position = positions[vid].xy;
    vector_float2 viewportSize = vector_float2(*viewportSizePointer);
    out.position = vector_float4(0.0f, 0.0f, 0.0f, 1.0f);
    out.position.xy = position / (viewportSize / 2.0f);

    out.point_size = POINT_SIZE;

    return out;
}

fragment half4 particle_fragment(ColorInOut in [[stage_in]], float2 uv[[point_coord]])
{
    float2 uvPos = uv;
    uvPos.x -= 0.5f;
    uvPos.y -= 0.5f;
    uvPos *= 2.0f;

    float dist = sqrt(uvPos.x*uvPos.x + uvPos.y*uvPos.y);
    float alpha = saturate(1.0f - dist);

    return half4(0.0f, 0.0f, alpha, alpha);
};


