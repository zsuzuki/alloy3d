//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include "shader_def.h"

#include <metal_stdlib>
using namespace metal;

struct p2f
{
    float4 pos [[position]];
    half4 color;
    float2 texcoord;
};

vertex p2f vert2d(const device VertexDataPrim2D* vertexArray [[buffer(0)]],const device Uniforms2D* screenData [[buffer(1)]], unsigned int vID [[vertex_id]])
{
    const device VertexDataPrim2D& vd2d = vertexArray[vID];

    float negy = screenData->size.y - vd2d.position.y;
    float2 pos = float2(vd2d.position.x, negy);

    p2f out;
    out.pos        = float4(pos / screenData->size * 2.0 - 1.0, 0.0, 1.0);
    out.color      = vd2d.color;
    // テクスチャUVは自動
    out.texcoord.x = vID & 1 ? 0 : 1;
    out.texcoord.y = vID & 2 ? 1 : 0;

    return out;
}

fragment half4 frag2d(p2f in [[stage_in]], texture2d<half, access::sample> tex [[texture(0)]] )
{
    constexpr sampler s( address::repeat, filter::linear );
    half4 texel = tex.sample( s, in.texcoord ).rgba;
    return in.color * texel;
}

//
