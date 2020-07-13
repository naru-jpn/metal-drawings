//
//  Kernels.metal
//  particles_meta_compute
//
//  Created by Naruki Chigira on 2020/07/14.
//  Copyright © 2020 Naruki Chigira. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

kernel void simulation(device particle_t* currentParticles [[ buffer(0) ]],
                       device particle_t* newParticles [[ buffer(1) ]],
                       constant uint* numParticles [[ buffer(2) ]],
                       const uint gid [[ thread_position_in_grid ]])
{
    float2 position = currentParticles[gid].position;
    float2 velocity = currentParticles[gid].velocity;

    for (uint i=0; i < *numParticles; i++) {
        if (i == gid) {
            continue;
        }
        float dx = position.x - currentParticles[i].position.x;
        float dy = position.y - currentParticles[i].position.y;
        float l = distance(float2(dx, 0), float2(0, dy));
        if (l < 10000 && l > 500) {
            float l2 = pow(l, 2.0);
            velocity.x -= 1.0E4 * (dx / abs(dx)) / l2;
            velocity.y -= 1.0E4 * (dy / abs(dy)) / l2;
        }
    }

    if (position.x < -500) {
        position.x = -500;
        velocity.x = -velocity.x;
    }
    if (position.x > 500) {
        position.x = 500;
        velocity.x = -velocity.x;
    }
    if (position.y > 500) {
        position.y = 500;
        velocity.y = -velocity.y;
    }
    if (position.y < -500) {
        position.y = -500;
        velocity.y = -velocity.y;
    }

    newParticles[gid].position = position + velocity;
    newParticles[gid].velocity = velocity;
}
