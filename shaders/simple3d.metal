//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include "model_surface.h"
#include "shader_def.h"
#include "shadow.h"
#include "environment.h"

#include <metal_stdlib>
using namespace metal;

struct v2f
{
    float4 position [[position]];
    float3 normal;
    half4 color;
    float2 texcoord;
    float4 modelColor [[flat]];
    uint   mirrored [[flat]];
    float4 shadowPosition;
    float viewDepth;
    float3 viewPosition;
    float4 tangent;
    float2 meshTexcoord;
};

//
//
//
vertex v2f simpleVert3d(device const VertexData3D* vertexData [[buffer(0)]],
                       device const Uniforms& cameraData [[buffer(1)]],
                       uint vertexId [[vertex_id]])
{
  v2f o{};

  const device VertexData3D &vd = vertexData[vertexId];

  float4 pos = float4(vd.position, 1.0);
  o.position = cameraData.perspectiveTransform * cameraData.worldTransform * pos;
  o.viewDepth = cameraData.fogColorAndEnabled.w != 0 ? -(cameraData.worldTransform * pos).z : 0;
  o.normal   = cameraData.worldNormalTransform * vd.normal;
  o.texcoord = vd.texcoord.xy;
  o.color    = vd.color;

  return o;
}

// Inverse transpose of the actual blended deformation, including node scale.
float3 TransformModelNormal(float4x4 matrix, float3 normal)
{
  float3 a = matrix[0].xyz, b = matrix[1].xyz, c = matrix[2].xyz;
  float  scale =
      max(max(max(abs(a.x), abs(a.y)), abs(a.z)),
          max(max(max(abs(b.x), abs(b.y)), abs(b.z)), max(max(abs(c.x), abs(c.y)), abs(c.z))));
  if (!(scale > 0.0) || !isfinite(scale))
    return float3(0.0);
  a /= scale;
  b /= scale;
  c /= scale;
  float3 x = cross(b, c), y = cross(c, a), z = cross(a, b);
  float  det = dot(a, x);
  if (abs(det) < 1e-8)
    return float3(0.0);
  return float3x3(x / det, y / det, z / det) * normal;
}

void SkinVertex(const device VertexDataModel3D &vd, const device float4x4 *jointMatrices,
                thread float4 &position, thread float3 &normal, thread float &orientation, thread float3 &tangent)
{
  float4   weights = vd.weights;
  float    sum     = weights.x + weights.y + weights.z + weights.w;
  float4x4 transform;
  if (sum > 0.000001)
  {
    weights /= sum;
    transform = jointMatrices[vd.joints.x] * weights.x + jointMatrices[vd.joints.y] * weights.y +
                jointMatrices[vd.joints.z] * weights.z + jointMatrices[vd.joints.w] * weights.w;
  }
  else
    transform = jointMatrices[0];
  tangent = vd.tangent.w != 0 ? (transform * float4(vd.tangent.xyz, 0)).xyz : float3(0);
  position = transform * float4(vd.position, 1.0);
  normal   = TransformModelNormal(transform, vd.normal);
  orientation = determinant(float3x3(transform[0].xyz, transform[1].xyz, transform[2].xyz));
}

float3 UnitModelNormal(float3 normal)
{
  float magnitude = length(normal);
  return magnitude > 0.0 && isfinite(magnitude) ? normal / magnitude : float3(0.0);
}

vertex v2f modelVert3d(device const VertexDataModel3D *vertexData [[buffer(0)]],
                       device const Uniforms          &cameraData [[buffer(1)]],
                       device const float4x4          *jointMatrices [[buffer(3)]],
                       constant MaterialUniforms      &material [[buffer(5)]],
                       uint                            vertexId [[vertex_id]])
{
  v2f                             o{};
  const device VertexDataModel3D &vd = vertexData[vertexId];
  float4                          position;
  float3                          normal;
  float                           orientation;
  float3 tangent;
  SkinVertex(vd, jointMatrices, position, normal, orientation, tangent);
  o.position   = cameraData.perspectiveTransform * cameraData.worldTransform * position;
  o.viewDepth  = cameraData.fogColorAndEnabled.w != 0 ? -(cameraData.worldTransform * position).z : 0;
  // Custom surfaces need view position even with highlights disabled or unlit materials.
#ifndef ALLOY3D_CUSTOM_SURFACE
  if ((material.highlight.x > 0 && material.highlight.z != 0 && material.parameters.w == 0) ||
      material.normalMapping.x != 0 || material.transmission.w > 0)
#endif
    o.viewPosition = (cameraData.worldTransform * position).xyz;
  o.normal     = UnitModelNormal(cameraData.worldNormalTransform * normal);
  o.texcoord   = vd.texcoord * material.textureTransform.xy + material.textureTransform.zw;
  o.meshTexcoord = vd.texcoord;
  o.color      = vd.color;
  o.modelColor = cameraData.modelColor;
  o.shadowPosition = cameraData.shadowTransform * cameraData.worldTransform * position;
  o.mirrored   = orientation * determinant(float3x3(cameraData.worldTransform[0].xyz,
                                                    cameraData.worldTransform[1].xyz,
                                                    cameraData.worldTransform[2].xyz)) <
                 0;
  o.tangent = float4((cameraData.worldTransform * float4(tangent, 0)).xyz,
                     vd.tangent.w * (o.mirrored ? -1.f : 1.f));
  return o;
}

vertex v2f modelInstanceVert3d(device const VertexDataModel3D     *vertexData [[buffer(0)]],
                               device const Uniforms              &cameraData [[buffer(1)]],
                               device const float4x4              *jointMatrices [[buffer(3)]],
                               device const ModelInstanceUniforms *instances [[buffer(4)]],
                               constant MaterialUniforms          &material [[buffer(5)]],
                               uint vertexId [[vertex_id]], uint instanceId [[instance_id]])
{
  v2f                                 o{};
  const device VertexDataModel3D     &vd       = vertexData[vertexId];
  const device ModelInstanceUniforms &instance = instances[instanceId];
  float4                              position;
  float3                              normal;
  float                               orientation;
  float3 tangent;
  SkinVertex(vd, jointMatrices, position, normal, orientation, tangent);
  o.position   = cameraData.perspectiveTransform * instance.modelView * position;
  o.viewDepth  = cameraData.fogColorAndEnabled.w != 0 ? -(instance.modelView * position).z : 0;
  // Custom surfaces need view position even with highlights disabled or unlit materials.
#ifndef ALLOY3D_CUSTOM_SURFACE
  if ((material.highlight.x > 0 && material.highlight.z != 0 && material.parameters.w == 0) ||
      material.normalMapping.x != 0 || material.transmission.w > 0)
#endif
    o.viewPosition = (instance.modelView * position).xyz;
  o.normal     = UnitModelNormal(instance.normalTransform * normal);
  o.texcoord   = vd.texcoord * material.textureTransform.xy + material.textureTransform.zw;
  o.meshTexcoord = vd.texcoord;
  o.color      = vd.color;
  o.modelColor = instance.color;
  o.shadowPosition = cameraData.shadowTransform * instance.modelView * position;
  o.mirrored   = orientation * determinant(float3x3(instance.modelView[0].xyz,
                                                    instance.modelView[1].xyz,
                                                    instance.modelView[2].xyz)) <
                 0;
  o.tangent = float4((instance.modelView * float4(tangent, 0)).xyz,
                     vd.tangent.w * (o.mirrored ? -1.f : 1.f));
  return o;
}

fragment half4 simpleFrag3d( v2f in [[stage_in]], texture2d< half, access::sample > tex [[texture(0)]],
                            device const Uniforms &cameraData [[buffer(1)]] )
{
    constexpr sampler s( address::repeat, filter::linear );

    half4 texel = tex.sample( s, in.texcoord ).rgba;

    // assume light coming from (front-top-right)
    float3 l = normalize(float3( 1.0, 1.0, 0.8 ));
    float3 n = normalize( in.normal );

    half ndotl = half( saturate( dot( n, l ) ) );

    half3 illum = (in.color.rgb * texel.xyz * 0.1) + (in.color.rgb * texel.xyz * ndotl);

    return ApplyFog(half4(illum, in.color.a * texel.a), in.viewDepth, cameraData);
}

fragment half4 modelFrag3d(v2f in [[stage_in]], bool frontFacing [[front_facing]],
                           device const Uniforms          &cameraData [[buffer(1)]],
                           constant MaterialUniforms      &material [[buffer(5)]],
                           texture2d<half, access::sample> tex [[texture(0)]],
                           depth2d<float>                  shadowMap [[texture(1)]],
                           sampler colorSampler [[sampler(0)]],
                           texture2d<half> normalMap [[texture(2)]],
                           texture2d<half> roughnessMap [[texture(3)]],
                           texture2d<half> occlusionMap [[texture(4)]]
#ifdef ALLOY3D_CUSTOM_SURFACE
                           ,
                           constant float4 &parameters [[buffer(6)]]
#endif
)
{
  // Fragment culling allows mixed mirrored placements in one instance batch.
  const bool front = frontFacing != bool(in.mirrored);
  if (!front && material.parameters.z == 0)
    discard_fragment();
  half4             baseColor = in.color * tex.sample(colorSampler, in.texcoord).rgba;
  if (material.parameters.x == 1 && float(baseColor.a) < material.parameters.y)
    discard_fragment();
  if (material.parameters.x != 2)
    baseColor.a = 1;
  // Placement alpha is an explicit application fade, applied after glTF alpha rules.
  baseColor *= half4(in.modelColor);
  float normalLength = length(in.normal);
  bool  unlit        = material.parameters.w != 0 || normalLength < 0.001;
#ifndef ALLOY3D_CUSTOM_SURFACE
  if (unlit)
    return ApplyFog(baseColor, in.viewDepth, cameraData);
#endif
  float3 n = normalLength >= 0.001 ? in.normal / normalLength : float3(0);
  if (material.normalMapping.x != 0 && !unlit)
  {
    float3 t = in.tangent.xyz;
    float handedness = in.tangent.w;
    if (handedness == 0)
    {
      float3 dx = dfdx(in.viewPosition), dy = dfdy(in.viewPosition);
      float2 ux = dfdx(in.meshTexcoord), uy = dfdy(in.meshTexcoord);
      float det = ux.x * uy.y - ux.y * uy.x;
      if (abs(det) > 1e-12)
      {
        t = (dx * uy.y - dy * ux.y) / det;
        float3 b = (dy * ux.x - dx * uy.x) / det;
        handedness = dot(cross(n, t), b) < 0 ? -1.f : 1.f;
      }
    }
    t = UnitModelNormal(t - n * dot(n, t));
    if (handedness != 0 && dot(t, t) > .5f)
    {
      float3 mapped = float3(normalMap.sample(colorSampler, in.texcoord).xyz) * 2 - 1;
      mapped.xy *= material.normalMapping.y;
      float3 result = UnitModelNormal(t * mapped.x + cross(n, t) * handedness * mapped.y + n * mapped.z);
      if (dot(result, result) > .5f) n = result;
    }
  }
  if (!front)
    n = -n;
  float3 l       = normalize(-cameraData.lightDirectionAndAmbient.xyz);
  half3 ambientColor = EnvironmentAmbient(n, cameraData);
  float roughness = 1, occlusion = 1;
  if (material.surfaceDetail.x != 0 && !unlit)
  {
    uint flags = uint(material.surfaceDetail.w);
    roughness = saturate(material.surfaceDetail.y * ((flags & 1) ? float(roughnessMap.sample(colorSampler, in.texcoord).g) : 1.f));
    if (flags & 2) occlusion = mix(1.f, float(occlusionMap.sample(colorSampler, in.texcoord).r), material.surfaceDetail.z);
    ambientColor *= half(occlusion);
  }
  half   diffuse = half(saturate(dot(n, l)) * saturate(cameraData.lightColorAndDiffuse.w));
  half   shadow =
      unlit ? half(1) : ShadowVisibility(in.shadowPosition, cameraData.shadowParameters, shadowMap);
  half3 lightColor = half3(cameraData.lightColorAndDiffuse.xyz);
  half3 litColor =
      unlit ? baseColor.rgb : baseColor.rgb * (ambientColor + diffuse * shadow * lightColor);
  half3 specularColor = half3(0);
  half3 transmissionColor = half3(0);
  if (!unlit && material.transmission.w > 0)
  {
    float3 v = material.highlight.z != 0 ? UnitModelNormal(-in.viewPosition) : float3(0,0,1);
    float forward = saturate(dot(-l, v));
    float back = saturate(-dot(n,l));
    transmissionColor = baseColor.rgb * lightColor * half3(material.transmission.rgb) *
        half(material.transmission.w * back * (.35f + .65f * forward * forward) *
             saturate(cameraData.lightColorAndDiffuse.w) * float(shadow));
    litColor += transmissionColor;
  }
  if (!unlit && material.highlight.x > 0 && diffuse > 0 && shadow > 0)
  {
    // Orthographic rays are parallel. Perspective rays point toward the camera origin.
    float3 v = material.highlight.z != 0 ? UnitModelNormal(-in.viewPosition) : float3(0, 0, 1);
    float3 sum = l + v;
    float h2 = dot(sum, sum);
    if (dot(n, v) > 0 && h2 > 1e-8f)
    {
      float nh = saturate(dot(n, sum * rsqrt(h2)));
      float exponent = material.surfaceDetail.x != 0 ? clamp(2.f / max(roughness * roughness, .015f) - 2.f, 1.f, 128.f)
                                                     : material.highlight.y;
      float specular = material.highlight.x * pow(nh, exponent) *
                       saturate(cameraData.lightColorAndDiffuse.w) * float(shadow);
      specularColor = half3(specular) * lightColor;
      litColor += specularColor;
    }
  }
#ifdef ALLOY3D_CUSTOM_SURFACE
  half ambient = half(saturate(cameraData.lightDirectionAndAmbient.w));
  ModelSurface surface{float3(baseColor.rgb),
                       float3(litColor),
                       n,
                       in.texcoord,
                       float3(lightColor),
                       float(ambient),
                       float(diffuse),
                       float(shadow),
                       unlit,
                       float3(ambientColor),
                       float3(specularColor),
                       in.viewPosition,
                       material.highlight.z != 0 ? UnitModelNormal(-in.viewPosition) : float3(0, 0, 1),
                       l,
                       saturate(cameraData.lightColorAndDiffuse.w), roughness, occlusion, float3(transmissionColor)};
  litColor = half3(alloy3dShade(surface, parameters));
#endif
  return ApplyFog(half4(litColor, baseColor.a), in.viewDepth, cameraData);
}

vertex v2f textVert3d(device const VertexData3D* vertexData [[buffer(0)]],
                      device const Uniforms& cameraData [[buffer(1)]],
                      uint vertexId [[vertex_id]])
{
  v2f o{};

  const device VertexData3D &vd = vertexData[vertexId];

  float4 pos = float4(vd.position, 1.0);
  o.position = cameraData.perspectiveTransform * cameraData.worldTransform * pos;
  o.viewDepth = cameraData.fogColorAndEnabled.w != 0 ? -(cameraData.worldTransform * pos).z : 0;
  o.normal   = float3(0.0, 0.0, 0.0);
  o.texcoord = vd.texcoord.xy;
  o.color    = vd.color;

  return o;
}

fragment half4 textFrag3d(v2f in [[stage_in]], texture2d<half, access::sample> tex [[texture(0)]],
                          device const Uniforms &cameraData [[buffer(1)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 texel = tex.sample(s, in.texcoord).rgba;
    return ApplyFog(in.color * texel, in.viewDepth, cameraData);
}

// Same skinning, winding and MASK coverage as the color pass. No color attachment.
fragment void shadowModelFrag3d(v2f in [[stage_in]], bool frontFacing [[front_facing]],
                                constant MaterialUniforms      &material [[buffer(5)]],
                                texture2d<half, access::sample> tex [[texture(0)]],
                                sampler colorSampler [[sampler(0)]],
                           texture2d<half> normalMap [[texture(2)]])
{
  if ((frontFacing == bool(in.mirrored)) && material.parameters.z == 0)
    discard_fragment();
  if (material.parameters.x == 1)
  {
    if (float(in.color.a * tex.sample(colorSampler, in.texcoord).a) < material.parameters.y)
      discard_fragment();
  }
}
