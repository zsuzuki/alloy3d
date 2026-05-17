//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include "shader_def.h"

#include <metal_stdlib>
using namespace metal;

struct v2f
{
    float4 position [[position]];
    float3 normal;
    half4 color;
    float2 texcoord;
};

//
//
//
vertex v2f simpleVert3d(device const VertexData3D* vertexData [[buffer(0)]],
                       device const Uniforms& cameraData [[buffer(1)]],
                       uint vertexId [[vertex_id]])
{
    v2f o;

    const device VertexData3D& vd = vertexData[ vertexId ];

    float4 pos = float4( vd.position, 1.0 );
    o.position = cameraData.perspectiveTransform * cameraData.worldTransform * pos;
    o.normal   = cameraData.worldNormalTransform * vd.normal;
    o.texcoord = vd.texcoord.xy;
    o.color    = vd.color;

    return o;
}

vertex v2f modelVert3d(device const VertexDataModel3D* vertexData [[buffer(0)]],
                       device const Uniforms& cameraData [[buffer(1)]],
                       device const float4x4* jointMatrices [[buffer(3)]],
                       uint vertexId [[vertex_id]])
{
    v2f o;

    const device VertexDataModel3D& vd = vertexData[vertexId];
    float4 weights = vd.weights;
    float weightSum = weights.x + weights.y + weights.z + weights.w;

    float4 localPosition = float4(vd.position, 1.0);
    float3 localNormal = vd.normal;
    float4 skinnedPosition = localPosition;
    float3 skinnedNormal = localNormal;

    if (weightSum > 0.000001)
    {
        weights /= weightSum;
        float4 p0 = jointMatrices[vd.joints.x] * localPosition;
        float4 p1 = jointMatrices[vd.joints.y] * localPosition;
        float4 p2 = jointMatrices[vd.joints.z] * localPosition;
        float4 p3 = jointMatrices[vd.joints.w] * localPosition;
        skinnedPosition = p0 * weights.x + p1 * weights.y + p2 * weights.z + p3 * weights.w;

        float3 n0 = (jointMatrices[vd.joints.x] * float4(localNormal, 0.0)).xyz;
        float3 n1 = (jointMatrices[vd.joints.y] * float4(localNormal, 0.0)).xyz;
        float3 n2 = (jointMatrices[vd.joints.z] * float4(localNormal, 0.0)).xyz;
        float3 n3 = (jointMatrices[vd.joints.w] * float4(localNormal, 0.0)).xyz;
        skinnedNormal = n0 * weights.x + n1 * weights.y + n2 * weights.z + n3 * weights.w;
    }
    else
    {
        skinnedPosition = jointMatrices[0] * localPosition;
        skinnedNormal = (jointMatrices[0] * float4(localNormal, 0.0)).xyz;
    }

    o.position = cameraData.perspectiveTransform * cameraData.worldTransform * skinnedPosition;
    o.normal   = cameraData.worldNormalTransform * skinnedNormal;
    o.texcoord = vd.texcoord.xy;
    o.color    = vd.color;

    return o;
}

fragment half4 simpleFrag3d( v2f in [[stage_in]], texture2d< half, access::sample > tex [[texture(0)]] )
{
    constexpr sampler s( address::repeat, filter::linear );

    half4 texel = tex.sample( s, in.texcoord ).rgba;

    // assume light coming from (front-top-right)
    float3 l = normalize(float3( 1.0, 1.0, 0.8 ));
    float3 n = normalize( in.normal );

    half ndotl = half( saturate( dot( n, l ) ) );

    half3 illum = (in.color.rgb * texel.xyz * 0.1) + (in.color.rgb * texel.xyz * ndotl);

    return half4( illum, in.color.a * texel.a );
}

fragment half4 modelFrag3d(v2f in [[stage_in]],
                           device const Uniforms& cameraData [[buffer(1)]],
                           texture2d<half, access::sample> tex [[texture(0)]])
{
    constexpr sampler s(address::repeat, filter::linear);
    half4 texel = tex.sample(s, in.texcoord).rgba;
    half4 baseColor = in.color * half4(cameraData.modelColor) * texel;

    float normalLength = length(in.normal);
    if (normalLength < 0.001)
    {
        return baseColor;
    }

    float3 n = in.normal / normalLength;
    float3 l = normalize(-cameraData.lightDirectionAndAmbient.xyz);
    half ambient = half(saturate(cameraData.lightDirectionAndAmbient.w));
    half diffuse = half(saturate(dot(n, l)) * saturate(cameraData.lightColorAndDiffuse.w));
    half3 lightColor = half3(cameraData.lightColorAndDiffuse.xyz);
    half3 illum = baseColor.rgb * (ambient + diffuse * lightColor);

    return half4(illum, baseColor.a);
}

vertex v2f textVert3d(device const VertexData3D* vertexData [[buffer(0)]],
                      device const Uniforms& cameraData [[buffer(1)]],
                      uint vertexId [[vertex_id]])
{
    v2f o;

    const device VertexData3D& vd = vertexData[ vertexId ];

    float4 pos = float4( vd.position, 1.0 );
    o.position = cameraData.perspectiveTransform * cameraData.worldTransform * pos;
    o.normal   = float3( 0.0, 0.0, 0.0 );
    o.texcoord = vd.texcoord.xy;
    o.color    = vd.color;

    return o;
}

fragment half4 textFrag3d(v2f in [[stage_in]], texture2d<half, access::sample> tex [[texture(0)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 texel = tex.sample(s, in.texcoord).rgba;
    return in.color * texel;
}
