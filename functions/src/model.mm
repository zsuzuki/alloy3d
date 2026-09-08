//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <alloy3d/metal/model.h>
#include "shader_def.h"

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#include <algorithm>
#include <arm_neon.h>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <limits>
#include <memory>
#include <string>
#include <vector>

namespace
{
constexpr int NoIndex = -1;

struct SourceVertex
{
  simd_float3 position;
  simd_float3 normal;
  simd_float2 texcoord;
  simd_float4 color;
  uint32_t    joints[4];
  float       weights[4];
  bool        skinned;
};

struct GpuModelVertex
{
  simd_float3 position;
  simd_float3 normal;
  simd_float2 texcoord;
  simd_uint4  joints;
  simd_float4 weights;
  float16x4_t color;
};

// Per-frame pose contains only transform values, never names or hierarchy containers.
struct PoseData
{
  simd_float3             translation = simd_make_float3(0.0f, 0.0f, 0.0f);
  simd_float4             rotation    = simd_make_float4(0.0f, 0.0f, 0.0f, 1.0f);
  simd_float3             scale       = simd_make_float3(1.0f, 1.0f, 1.0f);
  simd_float4x4           matrix      = matrix_identity_float4x4;
  bool                    hasMatrix   = false;
};

struct NodeData
{
  std::string      name;
  int              parent = NoIndex;
  std::vector<int> children;
};

struct SkinData
{
  std::vector<int>           joints;
  std::vector<simd_float4x4> inverseBindMatrices;
};

enum class AnimationPath
{
  Translation,
  Rotation,
  Scale,
};

struct AnimationSamplerData
{
  std::vector<float>       times;
  std::vector<simd_float4> values;
  bool                     step = false;
};

struct AnimationChannelData
{
  int           samplerIndex = NoIndex;
  int           nodeIndex    = NoIndex;
  AnimationPath path         = AnimationPath::Translation;
};

struct AnimationClipData
{
  std::string                       name;
  float                             duration = 0.0f;
  std::vector<AnimationSamplerData> samplers;
  std::vector<AnimationChannelData> channels;
};

// Immutable after loading, shared by independently animated model instances.
struct ModelAssetData
{
  std::vector<NodeData>          nodes;
  std::vector<PoseData>          bindPose;
  std::vector<SkinData>          skins;
  std::vector<AnimationClipData> animations;
};

simd_float3 TransformPoint(const simd_float4x4 &m, simd_float3 p)
{
  auto v = simd_mul(m, simd_make_float4(p.x, p.y, p.z, 1.0f));
  return simd_make_float3(v.x, v.y, v.z);
}

simd_float3 TransformDirection(const simd_float4x4 &m, simd_float3 n)
{
  auto v = simd_mul(m, simd_make_float4(n.x, n.y, n.z, 0.0f));
  auto d = simd_make_float3(v.x, v.y, v.z);
  return simd_length_squared(d) > 0.000001f ? simd_normalize(d) : simd_make_float3(0.0f, 1.0f, 0.0f);
}

simd_float4 NormalizeQuat(simd_float4 q)
{
  auto len2 = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;
  if (len2 <= 0.000001f)
  {
    return simd_make_float4(0.0f, 0.0f, 0.0f, 1.0f);
  }
  return q / std::sqrt(len2);
}

simd_float4 LerpQuat(simd_float4 a, simd_float4 b, float t)
{
  auto dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
  if (dot < 0.0f)
  {
    b = -b;
  }
  return NormalizeQuat(a + (b - a) * t);
}

simd_float4x4 MatrixFromCgltf(const cgltf_float *m)
{
  return simd_matrix(simd_make_float4(m[0], m[1], m[2], m[3]),
                     simd_make_float4(m[4], m[5], m[6], m[7]),
                     simd_make_float4(m[8], m[9], m[10], m[11]),
                     simd_make_float4(m[12], m[13], m[14], m[15]));
}

simd_float4x4 MatrixFromTRS(simd_float3 translation, simd_float4 rotation, simd_float3 scale)
{
  auto q = NormalizeQuat(rotation);
  auto x = q.x;
  auto y = q.y;
  auto z = q.z;
  auto w = q.w;

  auto x2 = x + x;
  auto y2 = y + y;
  auto z2 = z + z;
  auto xx = x * x2;
  auto xy = x * y2;
  auto xz = x * z2;
  auto yy = y * y2;
  auto yz = y * z2;
  auto zz = z * z2;
  auto wx = w * x2;
  auto wy = w * y2;
  auto wz = w * z2;

  auto col0 = simd_make_float3(1.0f - yy - zz, xy + wz, xz - wy) * scale.x;
  auto col1 = simd_make_float3(xy - wz, 1.0f - xx - zz, yz + wx) * scale.y;
  auto col2 = simd_make_float3(xz + wy, yz - wx, 1.0f - xx - yy) * scale.z;

  return simd_matrix(simd_make_float4(col0, 0.0f),
                     simd_make_float4(col1, 0.0f),
                     simd_make_float4(col2, 0.0f),
                     simd_make_float4(translation.x, translation.y, translation.z, 1.0f));
}

int NodeIndex(const cgltf_data *data, const cgltf_node *node)
{
  if (data == nullptr || node == nullptr || node < data->nodes || node >= data->nodes + data->nodes_count)
  {
    return NoIndex;
  }
  return static_cast<int>(node - data->nodes);
}

int SkinIndex(const cgltf_data *data, const cgltf_skin *skin)
{
  if (data == nullptr || skin == nullptr || skin < data->skins || skin >= data->skins + data->skins_count)
  {
    return NoIndex;
  }
  return static_cast<int>(skin - data->skins);
}

const cgltf_accessor *FindAttribute(const cgltf_primitive &primitive, cgltf_attribute_type type)
{
  for (cgltf_size i = 0; i < primitive.attributes_count; i++)
  {
    const auto &attribute = primitive.attributes[i];
    if (attribute.type == type && attribute.index == 0)
    {
      return attribute.data;
    }
  }
  return nullptr;
}

simd_float4 MaterialBaseColor(const cgltf_material *material)
{
  if (material != nullptr && material->has_pbr_metallic_roughness)
  {
    const auto *factor = material->pbr_metallic_roughness.base_color_factor;
    return simd_make_float4(factor[0], factor[1], factor[2], factor[3]);
  }
  return simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f);
}

id<MTLTexture> LoadEmbeddedTexture(cgltf_material *material, id<MTLDevice> device)
{
  if (material == nullptr || !material->has_pbr_metallic_roughness)
  {
    return nil;
  }

  auto *texture = material->pbr_metallic_roughness.base_color_texture.texture;
  if (texture == nullptr || texture->image == nullptr)
  {
    return nil;
  }

  auto *image = texture->image;
  if (image->buffer_view == nullptr)
  {
    NSLog(@"glTF external image URI is not supported yet: %s", image->uri ? image->uri : "");
    return nil;
  }

  auto *view       = image->buffer_view;
  auto *bufferBase = view->buffer != nullptr ? static_cast<uint8_t *>(view->buffer->data) : nullptr;
  auto *bufferData = view->data != nullptr ? static_cast<uint8_t *>(view->data)
                                           : bufferBase != nullptr ? bufferBase + view->offset : nullptr;
  if (bufferData == nullptr || view->size == 0)
  {
    return nil;
  }

  NSData *data = [NSData dataWithBytes:bufferData length:view->size];
  auto    loader = [[MTKTextureLoader alloc] initWithDevice:device];
  NSError *error = nil;
  NSDictionary *options = @{
    MTKTextureLoaderOptionSRGB : @YES,
  };
  id<MTLTexture> tex = [loader newTextureWithData:data options:options error:&error];
  if (tex == nil && error != nil)
  {
    NSLog(@"Failed to load embedded glTF texture: %@", error);
  }
  [loader release];
  return tex;
}

simd_float4 SampleChannel(const AnimationSamplerData &sampler, float time)
{
  if (sampler.times.empty() || sampler.values.empty())
  {
    return simd_make_float4(0.0f, 0.0f, 0.0f, 0.0f);
  }
  if (time <= sampler.times.front())
  {
    return sampler.values.front();
  }
  if (time >= sampler.times.back())
  {
    return sampler.values.back();
  }

  auto hi = std::upper_bound(sampler.times.begin(), sampler.times.end(), time);
  auto i1 = static_cast<size_t>(hi - sampler.times.begin());
  auto i0 = i1 - 1;
  if (sampler.step)
  {
    return sampler.values[i0];
  }

  auto t0 = sampler.times[i0];
  auto t1 = sampler.times[i1];
  auto f  = t1 > t0 ? (time - t0) / (t1 - t0) : 0.0f;
  return sampler.values[i0] + (sampler.values[i1] - sampler.values[i0]) * f;
}

simd_float4 SampleRotationChannel(const AnimationSamplerData &sampler, float time)
{
  if (sampler.times.empty() || sampler.values.empty())
  {
    return simd_make_float4(0.0f, 0.0f, 0.0f, 1.0f);
  }
  if (time <= sampler.times.front())
  {
    return NormalizeQuat(sampler.values.front());
  }
  if (time >= sampler.times.back())
  {
    return NormalizeQuat(sampler.values.back());
  }

  auto hi = std::upper_bound(sampler.times.begin(), sampler.times.end(), time);
  auto i1 = static_cast<size_t>(hi - sampler.times.begin());
  auto i0 = i1 - 1;
  if (sampler.step)
  {
    return NormalizeQuat(sampler.values[i0]);
  }

  auto t0 = sampler.times[i0];
  auto t1 = sampler.times[i1];
  auto f  = t1 > t0 ? (time - t0) / (t1 - t0) : 0.0f;
  return LerpQuat(sampler.values[i0], sampler.values[i1], f);
}

std::vector<NodeData> BuildNodes(const cgltf_data *data, std::vector<PoseData> &bindPose)
{
  std::vector<NodeData> nodes(data->nodes_count);
  bindPose.resize(data->nodes_count);
  for (cgltf_size i = 0; i < data->nodes_count; i++)
  {
    const auto &src = data->nodes[i];
    auto       &dst = nodes[i];
    auto       &pose = bindPose[i];
    dst.name        = src.name != nullptr ? src.name : "";
    dst.parent      = NodeIndex(data, src.parent);
    if (src.has_translation)
    {
      pose.translation = simd_make_float3(src.translation[0], src.translation[1], src.translation[2]);
    }
    if (src.has_rotation)
    {
      pose.rotation = simd_make_float4(src.rotation[0], src.rotation[1], src.rotation[2], src.rotation[3]);
    }
    if (src.has_scale)
    {
      pose.scale = simd_make_float3(src.scale[0], src.scale[1], src.scale[2]);
    }
    if (src.has_matrix)
    {
      pose.matrix    = MatrixFromCgltf(src.matrix);
      pose.hasMatrix = true;
    }
    for (cgltf_size childIndex = 0; childIndex < src.children_count; childIndex++)
    {
      auto index = NodeIndex(data, src.children[childIndex]);
      if (index != NoIndex)
      {
        dst.children.push_back(index);
      }
    }
  }
  return nodes;
}

std::vector<SkinData> BuildSkins(const cgltf_data *data)
{
  std::vector<SkinData> skins(data->skins_count);
  for (cgltf_size skinIndex = 0; skinIndex < data->skins_count; skinIndex++)
  {
    const auto &src = data->skins[skinIndex];
    auto       &dst = skins[skinIndex];
    dst.joints.resize(src.joints_count, NoIndex);
    dst.inverseBindMatrices.resize(src.joints_count, matrix_identity_float4x4);

    for (cgltf_size jointIndex = 0; jointIndex < src.joints_count; jointIndex++)
    {
      dst.joints[jointIndex] = NodeIndex(data, src.joints[jointIndex]);
    }

    if (src.inverse_bind_matrices != nullptr)
    {
      for (cgltf_size i = 0; i < src.joints_count && i < src.inverse_bind_matrices->count; i++)
      {
        cgltf_float matrix[16] = {};
        if (cgltf_accessor_read_float(src.inverse_bind_matrices, i, matrix, 16))
        {
          dst.inverseBindMatrices[i] = MatrixFromCgltf(matrix);
        }
      }
    }
  }
  return skins;
}

std::vector<AnimationClipData> BuildAnimations(const cgltf_data *data)
{
  std::vector<AnimationClipData> clips;
  clips.reserve(data->animations_count);

  for (cgltf_size animationIndex = 0; animationIndex < data->animations_count; animationIndex++)
  {
    const auto &src = data->animations[animationIndex];
    auto       &dst = clips.emplace_back();
    dst.name        = src.name != nullptr ? src.name : "";
    dst.samplers.resize(src.samplers_count);

    for (cgltf_size samplerIndex = 0; samplerIndex < src.samplers_count; samplerIndex++)
    {
      const auto &srcSampler = src.samplers[samplerIndex];
      auto       &dstSampler = dst.samplers[samplerIndex];
      dstSampler.step        = srcSampler.interpolation == cgltf_interpolation_type_step;

      if (srcSampler.input != nullptr)
      {
        dstSampler.times.resize(srcSampler.input->count);
        for (cgltf_size i = 0; i < srcSampler.input->count; i++)
        {
          cgltf_float value = 0.0f;
          cgltf_accessor_read_float(srcSampler.input, i, &value, 1);
          dstSampler.times[i] = value;
          dst.duration        = std::max(dst.duration, value);
        }
      }

      if (srcSampler.output != nullptr)
      {
        dstSampler.values.resize(srcSampler.output->count);
        for (cgltf_size i = 0; i < srcSampler.output->count; i++)
        {
          cgltf_float values[4] = {};
          cgltf_accessor_read_float(srcSampler.output, i, values, 4);
          dstSampler.values[i] = simd_make_float4(values[0], values[1], values[2], values[3]);
        }
      }
    }

    dst.channels.reserve(src.channels_count);
    for (cgltf_size channelIndex = 0; channelIndex < src.channels_count; channelIndex++)
    {
      const auto &srcChannel = src.channels[channelIndex];
      auto        nodeIndex  = NodeIndex(data, srcChannel.target_node);
      if (nodeIndex == NoIndex || srcChannel.sampler == nullptr)
      {
        continue;
      }

      AnimationChannelData channel;
      channel.nodeIndex    = nodeIndex;
      channel.samplerIndex = static_cast<int>(srcChannel.sampler - src.samplers);
      switch (srcChannel.target_path)
      {
      case cgltf_animation_path_type_translation:
        channel.path = AnimationPath::Translation;
        break;
      case cgltf_animation_path_type_rotation:
        channel.path = AnimationPath::Rotation;
        break;
      case cgltf_animation_path_type_scale:
        channel.path = AnimationPath::Scale;
        break;
      default:
        continue;
      }
      dst.channels.push_back(channel);
    }
  }

  return clips;
}
} // namespace

@interface ModelPart ()

- (BOOL)getBounds:(alloy3d::Bounds3D *)bounds;
- (void)configureMaterial:(const cgltf_material *)material
                 vertices:(const std::vector<SourceVertex> &)vertices
               jointCount:(NSUInteger)jointCount;

- (nonnull instancetype)initWithSourceVertices:(const std::vector<SourceVertex> &)vertices
                                       indices:(const std::vector<uint32_t> &)indices
                                       texture:(nullable id<MTLTexture>)texture
                                     baseColor:(simd_float4)baseColor
                                     nodeIndex:(int)nodeIndex
                                     skinIndex:(int)skinIndex
                                        device:(nonnull id<MTLDevice>)device;
- (void)updateWithNodeWorldMatrices:(const std::vector<simd_float4x4> &)nodeWorldMatrices
                               skins:(const std::vector<SkinData> &)skins;

@end

@implementation ModelPart
{
  id<MTLDevice>             device_;
  id<MTLBuffer>             vertexBuffer_;
  id<MTLBuffer>             indexBuffer_;
  id<MTLBuffer>             jointMatrixBuffers_[3];
  bool                      jointMatricesDirty_[3];
  id<MTLTexture>            texture_;
  NSUInteger                indexCount_;
  simd_float4               baseColor_;
  std::vector<simd_float4x4> jointMatrices_;
  int                       nodeIndex_;
  int                       skinIndex_;
  NSUInteger                                            alphaMode_;
  float                                                 alphaCutoff_;
  BOOL                                                  doubleSided_, unlit_;
  std::shared_ptr<const std::vector<alloy3d::Bounds3D>> influenceBounds_;
  simd_float3                                           sortCenter_;
  bool                                                  sortCenterDirty_;
}

@synthesize indexBuffer  = indexBuffer_;
@synthesize texture      = texture_;
@synthesize indexCount   = indexCount_;
@synthesize baseColor    = baseColor_;
@synthesize alphaMode    = alphaMode_;
@synthesize alphaCutoff  = alphaCutoff_;
@synthesize doubleSided  = doubleSided_;
@synthesize unlit        = unlit_;

- (nullable id<MTLBuffer>)vertexBuffer
{
  return vertexBuffer_;
}

- (nonnull instancetype)initWithVertexBuffer:(nonnull id<MTLBuffer>)vertexBuffer
                                 indexBuffer:(nonnull id<MTLBuffer>)indexBuffer
                                      texture:(nullable id<MTLTexture>)texture
                                   indexCount:(NSUInteger)indexCount
                                    baseColor:(simd_float4)baseColor
{
  self = [super init];
  if (self != nil)
  {
    device_       = [vertexBuffer.device retain];
    vertexBuffer_ = [vertexBuffer retain];
    indexBuffer_  = [indexBuffer retain];
    texture_      = [texture retain];
    indexCount_   = indexCount;
    baseColor_    = baseColor;
    nodeIndex_    = NoIndex;
    skinIndex_    = NoIndex;
    jointMatrices_.push_back(matrix_identity_float4x4);
    std::fill(std::begin(jointMatricesDirty_), std::end(jointMatricesDirty_), true);
  }
  return self;
}

- (nonnull instancetype)initWithSourceVertices:(const std::vector<SourceVertex> &)vertices
                                       indices:(const std::vector<uint32_t> &)indices
                                       texture:(nullable id<MTLTexture>)texture
                                     baseColor:(simd_float4)baseColor
                                     nodeIndex:(int)nodeIndex
                                     skinIndex:(int)skinIndex
                                        device:(nonnull id<MTLDevice>)device
{
  self = [super init];
  if (self != nil)
  {
    device_         = [device retain];
    texture_        = [texture retain];
    indexCount_     = indices.size();
    baseColor_      = baseColor;
    nodeIndex_      = nodeIndex;
    skinIndex_      = skinIndex;

    std::vector<GpuModelVertex> gpuVertices(vertices.size());
    for (size_t i = 0; i < vertices.size(); i++)
    {
      const auto &src = vertices[i];
      gpuVertices[i].position = src.position;
      gpuVertices[i].normal   = src.normal;
      gpuVertices[i].texcoord = src.texcoord;
      gpuVertices[i].joints   = simd_make_uint4(src.joints[0], src.joints[1], src.joints[2], src.joints[3]);
      gpuVertices[i].weights  = src.skinned ? simd_make_float4(src.weights[0], src.weights[1], src.weights[2], src.weights[3])
                                            : simd_make_float4(0.0f, 0.0f, 0.0f, 0.0f);
      gpuVertices[i].color    = vcvt_f16_f32(src.color);
    }

    vertexBuffer_ = [device newBufferWithBytes:gpuVertices.data()
                                        length:sizeof(GpuModelVertex) * gpuVertices.size()
                                       options:MTLResourceStorageModeShared];
    indexBuffer_    = [device newBufferWithBytes:indices.data()
                                          length:sizeof(uint32_t) * indices.size()
                                         options:MTLResourceStorageModeShared];
    jointMatrices_.push_back(matrix_identity_float4x4);
    std::fill(std::begin(jointMatricesDirty_), std::end(jointMatricesDirty_), true);
    for (auto &jointMatrixBuffer : jointMatrixBuffers_)
    {
      jointMatrixBuffer = [device newBufferWithLength:sizeof(simd_float4x4)
                                              options:MTLResourceStorageModeShared];
    }
  }
  return self;
}

// Bounds per influencing joint provide a conservative skinned bound without
// scanning vertices each frame. Immutable bounds are shared by model instances.
- (void)configureMaterial:(const cgltf_material *)material
                 vertices:(const std::vector<SourceVertex> &)vertices
               jointCount:(NSUInteger)jointCount
{
  alphaMode_   = material ? material->alpha_mode : cgltf_alpha_mode_opaque;
  alphaCutoff_ = material ? material->alpha_cutoff : .5f;
  doubleSided_ = material && material->double_sided;
  unlit_       = material && material->unlit;
  auto bounds =
      std::make_shared<std::vector<alloy3d::Bounds3D>>(std::max<NSUInteger>(1, jointCount));
  for (const auto &vertex : vertices)
  {
    float sum = vertex.weights[0] + vertex.weights[1] + vertex.weights[2] + vertex.weights[3];
    if (!vertex.skinned || sum <= .000001f)
      (*bounds)[0].include(vertex.position);
    else
      for (int i = 0; i < 4; ++i)
        if (vertex.weights[i] > 0 && vertex.joints[i] < bounds->size())
          (*bounds)[vertex.joints[i]].include(vertex.position);
  }
  influenceBounds_ = bounds;
  sortCenterDirty_ = true;
}

- (simd_float3)sortCenter
{
  if (sortCenterDirty_)
  {
    alloy3d::Bounds3D bounds;
    if (influenceBounds_)
      for (size_t i = 0; i < std::min(influenceBounds_->size(), jointMatrices_.size()); ++i)
        if ((*influenceBounds_)[i].isValid())
          bounds.include((*influenceBounds_)[i].transformed(jointMatrices_[i]));
    sortCenter_ =
        bounds.isValid() ? bounds.min * .5f + bounds.max * .5f : simd_make_float3(0, 0, 0);
    sortCenterDirty_ = false;
  }
  return sortCenter_;
}

// Shared vertex/index buffers are immutable after loading. Querying the current
// CPU pose needs neither a duplicate vertex array nor a GPU synchronization.
- (BOOL)getBounds:(alloy3d::Bounds3D *)bounds
{
  if (!bounds || !vertexBuffer_ || !indexBuffer_ || jointMatrices_.empty())
    return NO;
  if (indexCount_ == 0 || indexCount_ > indexBuffer_.length / sizeof(uint32_t))
    return NO;
  const auto *vertices = static_cast<const GpuModelVertex *>(vertexBuffer_.contents);
  const auto *indices  = static_cast<const uint32_t *>(indexBuffer_.contents);
  if (!vertices || !indices)
    return NO;
  const auto        vertexCount = vertexBuffer_.length / sizeof(GpuModelVertex);
  alloy3d::Bounds3D result;
  for (NSUInteger i = 0; i < indexCount_; ++i)
  {
    if (indices[i] >= vertexCount)
      return NO;
    const auto &vertex    = vertices[indices[i]];
    auto        weights   = vertex.weights;
    const float sum       = weights.x + weights.y + weights.z + weights.w;
    auto        transform = jointMatrices_[0];
    if (sum > 0.000001f)
    {
      weights /= sum;
      transform = simd_float4x4{};
      for (int joint = 0; joint < 4; ++joint)
      {
        if (vertex.joints[joint] >= jointMatrices_.size())
          return NO;
        for (int column = 0; column < 4; ++column)
          transform.columns[column] +=
              jointMatrices_[vertex.joints[joint]].columns[column] * weights[joint];
      }
    }
    const auto point = simd_mul(transform, simd_make_float4(vertex.position, 1));
    if (point.w == 0)
      return NO;
    auto position = point.xyz / point.w;
    if (!std::isfinite(position.x) || !std::isfinite(position.y) || !std::isfinite(position.z))
      return NO;
    result.include(position);
  }
  if (!result.isValid())
    return NO;
  *bounds = result;
  return YES;
}

- (ModelPart *)newInstance
{
  auto part = [[ModelPart alloc] initWithVertexBuffer:vertexBuffer_
                                          indexBuffer:indexBuffer_
                                              texture:texture_
                                           indexCount:indexCount_
                                            baseColor:baseColor_];
  try
  {
    part->nodeIndex_     = nodeIndex_;
    part->skinIndex_     = skinIndex_;
    part->alphaMode_       = alphaMode_;
    part->alphaCutoff_     = alphaCutoff_;
    part->doubleSided_     = doubleSided_;
    part->unlit_           = unlit_;
    part->influenceBounds_ = influenceBounds_;
    part->sortCenter_      = sortCenter_;
    part->sortCenterDirty_ = sortCenterDirty_;
    part->jointMatrices_ = jointMatrices_;
    return part;
  }
  catch (...)
  {
    [part release];
    throw;
  }
}

- (void)dealloc
{
  [device_ release];
  [vertexBuffer_ release];
  for (auto &jointMatrixBuffer : jointMatrixBuffers_)
  {
    [jointMatrixBuffer release];
  }
  [indexBuffer_ release];
  [texture_ release];
  [super dealloc];
}

- (nullable id<MTLBuffer>)vertexBufferForPage:(NSUInteger)pageIndex
{
  return vertexBuffer_;
}

- (nullable id<MTLBuffer>)jointMatrixBufferForPage:(NSUInteger)pageIndex
{
  auto         buffer         = jointMatrixBuffers_[pageIndex % 3];
  const size_t jointCount     = std::max<size_t>(1, jointMatrices_.size());
  const size_t requiredLength = sizeof(simd_float4x4) * jointCount;
  if ((buffer == nil || buffer.length < requiredLength) && device_ != nil)
  {
    auto replacement = [device_ newBufferWithLength:requiredLength options:MTLResourceStorageModeShared];
    if (replacement == nil) throw std::bad_alloc();
    [buffer release];
    buffer = replacement;
    jointMatricesDirty_[pageIndex % 3] = true;
    jointMatrixBuffers_[pageIndex % 3] = buffer;
  }
  if (buffer != nil && jointMatricesDirty_[pageIndex % 3] && !jointMatrices_.empty())
  {
    std::memcpy(buffer.contents, jointMatrices_.data(), requiredLength);
    jointMatricesDirty_[pageIndex % 3] = false;
  }
  return buffer;
}

- (void)updateWithNodeWorldMatrices:(const std::vector<simd_float4x4> &)nodeWorldMatrices
                               skins:(const std::vector<SkinData> &)skins
{
  std::fill(std::begin(jointMatricesDirty_), std::end(jointMatricesDirty_), true);
  sortCenterDirty_          = true;
  auto nodeWorld = nodeIndex_ >= 0 && nodeIndex_ < nodeWorldMatrices.size()
                       ? nodeWorldMatrices[nodeIndex_]
                       : matrix_identity_float4x4;
  const SkinData *skin = skinIndex_ >= 0 && skinIndex_ < skins.size() ? &skins[skinIndex_] : nullptr;
  if (skin == nullptr)
  {
    jointMatrices_.resize(1);
    jointMatrices_[0] = nodeWorld;
    return;
  }

  jointMatrices_.resize(std::max<size_t>(1, skin->joints.size()));
  for (size_t i = 0; i < skin->joints.size(); i++)
  {
    auto jointNode = skin->joints[i];
    jointMatrices_[i] = jointNode >= 0 && jointNode < nodeWorldMatrices.size()
                            ? simd_mul(nodeWorldMatrices[jointNode], skin->inverseBindMatrices[i])
                            : matrix_identity_float4x4;
  }
}

@end

@interface MetalModel ()

- (void)samplePoseForAnimation:(NSUInteger)index time:(float)seconds into:(std::vector<PoseData> &)pose;
- (void)applyPose:(const std::vector<PoseData> &)pose;
- (void)updatePoseAtTime:(float)seconds;

@end

@implementation MetalModel
{
  BOOL                           loaded_;
  NSArray<ModelPart *>          *parts_;
  std::shared_ptr<const ModelAssetData> asset_;
  std::vector<PoseData>          poseScratch_[2];
  std::vector<simd_float4x4>     localMatrices_;
  std::vector<bool>              visited_;
  std::vector<simd_float4x4>     currentWorldMatrices_;

  NSUInteger                     animationIndex_;
  float                          currentTime_;
}

@synthesize loaded = loaded_;
@synthesize parts  = parts_;

- (nonnull instancetype)initWithFile:(nonnull NSString *)fname device:(nonnull id<MTLDevice>)device
{
  self = [super init];
  if (self != nil)
  {
    auto asset      = std::make_shared<ModelAssetData>();
    asset_          = asset;
    loaded_         = NO;
    animationIndex_ = 0;
    currentTime_    = 0.0f;
    auto *parts     = [[NSMutableArray<ModelPart *> alloc] init];

    std::filesystem::path path([fname UTF8String]);
    if (!path.is_absolute())
    {
      NSURL *resourceURL = [[NSBundle mainBundle] URLForResource:fname withExtension:nil];
      if (resourceURL != nil)
      {
        path = std::filesystem::path([[resourceURL path] UTF8String]);
      }
    }

    cgltf_options options = {};
    cgltf_data   *data    = nullptr;
    auto          result  = cgltf_parse_file(&options, path.string().c_str(), &data);
    if (result == cgltf_result_success)
    {
      result = cgltf_load_buffers(&options, data, path.string().c_str());
    }
    if (result == cgltf_result_success)
    {
      result = cgltf_validate(data);
    }

    if (result == cgltf_result_success)
    {
      asset->nodes = BuildNodes(data, asset->bindPose);
      // Allocate both blend poses and matrix workspace once at model load.
      for (auto &pose : poseScratch_)
        pose.resize(asset_->nodes.size());
      localMatrices_.resize(asset_->nodes.size());
      currentWorldMatrices_.resize(asset_->nodes.size());
      visited_.resize(asset_->nodes.size());
      asset->skins      = BuildSkins(data);
      asset->animations = BuildAnimations(data);

      auto buildNode = [&](auto &&selfRef, const cgltf_node *node) -> void
      {
        if (node == nullptr)
        {
          return;
        }

        auto nodeIndex = NodeIndex(data, node);
        if (node->mesh != nullptr)
        {
          for (cgltf_size primitiveIndex = 0; primitiveIndex < node->mesh->primitives_count; primitiveIndex++)
          {
            const auto &primitive = node->mesh->primitives[primitiveIndex];
            if (primitive.type != cgltf_primitive_type_triangles)
            {
              NSLog(@"Skipping non-triangle glTF primitive.");
              continue;
            }

            auto *positions = FindAttribute(primitive, cgltf_attribute_type_position);
            if (positions == nullptr || positions->count == 0)
            {
              NSLog(@"Skipping glTF primitive without POSITION.");
              continue;
            }

            auto *normals   = FindAttribute(primitive, cgltf_attribute_type_normal);
            auto *texcoords = FindAttribute(primitive, cgltf_attribute_type_texcoord);
            auto *colors    = FindAttribute(primitive, cgltf_attribute_type_color);
            auto *joints    = FindAttribute(primitive, cgltf_attribute_type_joints);
            auto *weights   = FindAttribute(primitive, cgltf_attribute_type_weights);
            auto  baseColor = MaterialBaseColor(primitive.material);
            auto  skinIndex = SkinIndex(data, node->skin);

            std::vector<SourceVertex> vertices(positions->count);
            for (cgltf_size vertexIndex = 0; vertexIndex < positions->count; vertexIndex++)
            {
              cgltf_float tmp[4] = {};
              cgltf_accessor_read_float(positions, vertexIndex, tmp, 3);
              vertices[vertexIndex].position = simd_make_float3(tmp[0], tmp[1], tmp[2]);

              if (normals != nullptr && cgltf_accessor_read_float(normals, vertexIndex, tmp, 3))
              {
                vertices[vertexIndex].normal = simd_make_float3(tmp[0], tmp[1], tmp[2]);
              }
              else
              {
                vertices[vertexIndex].normal = simd_make_float3(0.0f, 0.0f, 0.0f);
              }

              if (texcoords != nullptr && cgltf_accessor_read_float(texcoords, vertexIndex, tmp, 2))
              {
                vertices[vertexIndex].texcoord = simd_make_float2(tmp[0], tmp[1]);
              }
              else
              {
                vertices[vertexIndex].texcoord = simd_make_float2(0.0f, 0.0f);
              }

              simd_float4 vertexColor = simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f);
              if (colors != nullptr && cgltf_accessor_read_float(colors, vertexIndex, tmp, 4))
              {
                vertexColor = simd_make_float4(tmp[0], tmp[1], tmp[2], tmp[3]);
              }
              vertices[vertexIndex].color = baseColor * vertexColor;

              vertices[vertexIndex].skinned = false;
              std::fill(std::begin(vertices[vertexIndex].joints), std::end(vertices[vertexIndex].joints), 0);
              std::fill(std::begin(vertices[vertexIndex].weights), std::end(vertices[vertexIndex].weights), 0.0f);
              if (joints != nullptr && weights != nullptr && skinIndex != NoIndex)
              {
                cgltf_uint  jointValues[4]  = {};
                cgltf_float weightValues[4] = {};
                if (cgltf_accessor_read_uint(joints, vertexIndex, jointValues, 4) &&
                    cgltf_accessor_read_float(weights, vertexIndex, weightValues, 4))
                {
                  for (size_t influence = 0; influence < 4; influence++)
                  {
                    vertices[vertexIndex].joints[influence]  = jointValues[influence];
                    vertices[vertexIndex].weights[influence] = weightValues[influence];
                  }
                  vertices[vertexIndex].skinned = true;
                }
              }
            }

            std::vector<uint32_t> indices;
            if (primitive.indices != nullptr)
            {
              indices.resize(primitive.indices->count);
              for (cgltf_size i = 0; i < primitive.indices->count; i++)
              {
                indices[i] = static_cast<uint32_t>(cgltf_accessor_read_index(primitive.indices, i));
              }
            }
            else
            {
              indices.resize(positions->count);
              for (uint32_t i = 0; i < indices.size(); i++)
              {
                indices[i] = i;
              }
            }

            if (indices.size() < 3 || (indices.size() % 3) != 0)
            {
              NSLog(@"Skipping glTF primitive with invalid triangle index count.");
              continue;
            }
            if (std::any_of(indices.begin(), indices.end(), [&](uint32_t index) { return index >= vertices.size(); }))
            {
              NSLog(@"Skipping glTF primitive with out-of-range indices.");
              continue;
            }

            if (normals == nullptr)
            {
              for (size_t i = 0; i < indices.size(); i += 3)
              {
                auto i0 = indices[i + 0];
                auto i1 = indices[i + 1];
                auto i2 = indices[i + 2];
                auto normal = simd_cross(vertices[i1].position - vertices[i0].position,
                                         vertices[i2].position - vertices[i0].position);
                if (simd_length_squared(normal) > 0.000001f)
                {
                  normal = simd_normalize(normal);
                  vertices[i0].normal += normal;
                  vertices[i1].normal += normal;
                  vertices[i2].normal += normal;
                }
              }
              for (auto &vertex : vertices)
              {
                vertex.normal = simd_length_squared(vertex.normal) > 0.000001f
                                    ? simd_normalize(vertex.normal)
                                    : simd_make_float3(0.0f, 1.0f, 0.0f);
              }
            }

            auto texture = LoadEmbeddedTexture(primitive.material, device);
            auto part    = [[ModelPart alloc] initWithSourceVertices:vertices
                                                             indices:indices
                                                             texture:texture
                                                           baseColor:baseColor
                                                           nodeIndex:nodeIndex
                                                           skinIndex:skinIndex
                                                              device:device];
            [part configureMaterial:primitive.material
                           vertices:vertices
                         jointCount:skinIndex == NoIndex ? 1 : data->skins[skinIndex].joints_count];
            [parts addObject:part];
            [part release];
            [texture release];
          }
        }

        for (cgltf_size i = 0; i < node->children_count; i++)
        {
          selfRef(selfRef, node->children[i]);
        }
      };

      if (data->scene != nullptr)
      {
        for (cgltf_size i = 0; i < data->scene->nodes_count; i++)
        {
          buildNode(buildNode, data->scene->nodes[i]);
        }
      }
      else
      {
        for (cgltf_size i = 0; i < data->nodes_count; i++)
        {
          buildNode(buildNode, &data->nodes[i]);
        }
      }
      loaded_ = parts.count > 0;
    }
    else
    {
      NSLog(@"Failed to load glTF/GLB model: %@ (%d)", fname, result);
    }

    if (data != nullptr)
    {
      cgltf_free(data);
    }

    parts_ = [parts copy];
    [parts release];
    if (loaded_)
    {
      [self updatePoseAtTime:0.0f];
    }
  }
  return self;
}

- (MetalModel *)newInstance
{
  auto            instance = [[MetalModel alloc] init];
  NSMutableArray *parts    = nil;
  try
  {
    instance->asset_          = asset_;
    instance->loaded_         = loaded_;
    instance->animationIndex_ = animationIndex_;
    instance->currentTime_    = currentTime_;
    // Preserve blended poses exactly, not just the selected clip and time.
    instance->currentWorldMatrices_ = currentWorldMatrices_;
    instance->localMatrices_        = localMatrices_;
    instance->visited_              = visited_;
    for (int i = 0; i < 2; ++i)
      instance->poseScratch_[i] = asset_->bindPose;
    parts = [[NSMutableArray alloc] initWithCapacity:parts_.count];
    for (ModelPart *part in parts_)
    {
      auto copy = [part newInstance];
      [parts addObject:copy];
      [copy release];
    }
    instance->parts_ = [parts copy];
    [parts release];
    return instance;
  }
  catch (...)
  {
    [parts release];
    [instance release];
    throw;
  }
}

- (BOOL)getBounds:(alloy3d::Bounds3D *)bounds
{
  if (!loaded_ || !bounds)
    return NO;
  alloy3d::Bounds3D result;
  for (ModelPart *part in parts_)
  {
    alloy3d::Bounds3D partBounds;
    if (![part getBounds:&partBounds])
      return NO;
    result.include(partBounds);
  }
  if (!result.isValid())
    return NO;
  *bounds = result;
  return YES;
}

- (BOOL)sharesAssetWith:(MetalModel *)other
{
  return other != nil && asset_ == other->asset_;
}

- (void)dealloc
{
  [parts_ release];
  [super dealloc];
}

- (NSUInteger)animationCount
{
  return asset_->animations.size();
}

- (nonnull NSString *)animationNameAtIndex:(NSUInteger)index
{
  if (index >= asset_->animations.size())
  {
    return @"";
  }
  return [NSString stringWithUTF8String:asset_->animations[index].name.c_str()];
}

- (float)animationDurationAtIndex:(NSUInteger)index
{
  return index < asset_->animations.size() ? asset_->animations[index].duration : 0.0f;
}

- (NSUInteger)currentAnimationIndex
{
  return animationIndex_;
}

- (float)currentAnimationDuration
{
  return animationIndex_ < asset_->animations.size() ? asset_->animations[animationIndex_].duration
                                                     : 0.0f;
}

- (void)setAnimationIndex:(NSUInteger)index
{
  if (index < asset_->animations.size())
  {
    animationIndex_ = index;
    [self updatePoseAtTime:currentTime_];
  }
}

- (BOOL)setAnimationName:(nonnull NSString *)name
{
  auto targetName = std::string([name UTF8String]);
  for (size_t i = 0; i < asset_->animations.size(); i++)
  {
    if (asset_->animations[i].name == targetName)
    {
      [self setAnimationIndex:i];
      return YES;
    }
  }
  return NO;
}

- (void)setAnimationTime:(float)seconds
{
  currentTime_ = seconds;
  [self updatePoseAtTime:seconds];
}

- (void)setAnimationBlendFrom:(NSUInteger)animationA
                        timeA:(float)timeASeconds
                           to:(NSUInteger)animationB
                        timeB:(float)timeBSeconds
                       weight:(float)weight
{
  if (asset_->nodes.empty())
  {
    return;
  }
  if (animationA >= asset_->animations.size() || animationB >= asset_->animations.size())
  {
    return;
  }

  auto blendWeight = std::clamp(weight, 0.0f, 1.0f);
  if (blendWeight <= 0.0f)
  {
    animationIndex_ = animationA;
    currentTime_    = timeASeconds;
    [self updatePoseAtTime:timeASeconds];
    return;
  }
  if (blendWeight >= 1.0f)
  {
    animationIndex_ = animationB;
    currentTime_    = timeBSeconds;
    [self updatePoseAtTime:timeBSeconds];
    return;
  }
  auto &pose = poseScratch_[0];
  const auto &poseB = poseScratch_[1];
  [self samplePoseForAnimation:animationA time:timeASeconds into:pose];
  [self samplePoseForAnimation:animationB time:timeBSeconds into:poseScratch_[1]];
  for (size_t i = 0; i < pose.size() && i < poseB.size(); i++)
  {
    // Each output element depends only on the two corresponding input elements.
    const auto &a = pose[i];
    const auto &b = poseB[i];
    auto       &p = pose[i];

    if (a.hasMatrix && b.hasMatrix)
    {
      p.matrix    = blendWeight < 0.5f ? a.matrix : b.matrix;
      p.hasMatrix = true;
      continue;
    }

    p.translation = a.translation + (b.translation - a.translation) * blendWeight;
    p.rotation    = LerpQuat(a.rotation, b.rotation, blendWeight);
    p.scale       = a.scale + (b.scale - a.scale) * blendWeight;
    p.hasMatrix   = false;
  }

  animationIndex_ = animationB;
  currentTime_    = timeBSeconds;
  [self applyPose:pose];
}

- (NSUInteger)rigCount
{
  return asset_->nodes.size();
}

- (nonnull NSString *)rigNameAtIndex:(NSUInteger)index
{
  if (index >= asset_->nodes.size())
  {
    return @"";
  }
  return [NSString stringWithUTF8String:asset_->nodes[index].name.c_str()];
}

- (NSInteger)rigIndexForName:(nonnull NSString *)name
{
  auto targetName = std::string([name UTF8String]);
  for (size_t i = 0; i < asset_->nodes.size(); i++)
  {
    if (asset_->nodes[i].name == targetName)
    {
      return static_cast<NSInteger>(i);
    }
  }
  return -1;
}

- (BOOL)rigTransformAtIndex:(NSUInteger)index transform:(nonnull simd_float4x4 *)transform
{
  if (transform == nullptr || index >= currentWorldMatrices_.size())
  {
    return NO;
  }
  *transform = currentWorldMatrices_[index];
  return YES;
}

- (void)computeWorldMatricesFromLocal:(const std::vector<simd_float4x4> &)localMatrices
                                index:(int)index
                                world:(std::vector<simd_float4x4> &)worldMatrices
                              visited:(std::vector<bool> &)visited
{
  if (index < 0 || index >= asset_->nodes.size() || visited[index])
  {
    return;
  }

  auto parent = asset_->nodes[index].parent;
  if (parent != NoIndex)
  {
    [self computeWorldMatricesFromLocal:localMatrices index:parent world:worldMatrices visited:visited];
    worldMatrices[index] = simd_mul(worldMatrices[parent], localMatrices[index]);
  }
  else
  {
    worldMatrices[index] = localMatrices[index];
  }
  visited[index] = true;
}

- (void)samplePoseForAnimation:(NSUInteger)index time:(float)seconds into:(std::vector<PoseData> &)pose
{
  // Reset every component: channels omitted by a new clip must use the bind pose.
  pose = asset_->bindPose;
  if (index < asset_->animations.size())
  {
    const auto &clip = asset_->animations[index];
    auto        time = clip.duration > 0.0f ? std::fmod(std::max(0.0f, seconds), clip.duration) : seconds;
    for (const auto &channel : clip.channels)
    {
      if (channel.nodeIndex < 0 || channel.nodeIndex >= pose.size() || channel.samplerIndex < 0 ||
          channel.samplerIndex >= clip.samplers.size())
      {
        continue;
      }

      const auto &sampler = clip.samplers[channel.samplerIndex];
      auto       &node    = pose[channel.nodeIndex];
      switch (channel.path)
      {
      case AnimationPath::Translation:
      {
        auto value       = SampleChannel(sampler, time);
        node.translation = simd_make_float3(value.x, value.y, value.z);
        node.hasMatrix   = false;
        break;
      }
      case AnimationPath::Rotation:
      {
        node.rotation  = SampleRotationChannel(sampler, time);
        node.hasMatrix = false;
        break;
      }
      case AnimationPath::Scale:
      {
        auto value   = SampleChannel(sampler, time);
        node.scale   = simd_make_float3(value.x, value.y, value.z);
        node.hasMatrix = false;
        break;
      }
      }
    }
  }
}

- (void)applyPose:(const std::vector<PoseData> &)pose
{
  if (pose.empty())
  {
    return;
  }

  auto &localMatrices = localMatrices_;
  for (size_t i = 0; i < pose.size(); i++)
  {
    localMatrices[i] = pose[i].hasMatrix ? pose[i].matrix
                                         : MatrixFromTRS(pose[i].translation, pose[i].rotation, pose[i].scale);
  }

  auto &worldMatrices = currentWorldMatrices_;
  auto &visited = visited_;
  std::fill(worldMatrices.begin(), worldMatrices.end(), matrix_identity_float4x4);
  std::fill(visited.begin(), visited.end(), false);
  for (size_t i = 0; i < pose.size(); i++)
  {
    [self computeWorldMatricesFromLocal:localMatrices index:static_cast<int>(i) world:worldMatrices visited:visited];
  }

  for (ModelPart *part in parts_)
  {
    [part updateWithNodeWorldMatrices:worldMatrices skins:asset_->skins];
  }
}

- (void)updatePoseAtTime:(float)seconds
{
  if (asset_->nodes.empty())
  {
    return;
  }

  [self samplePoseForAnimation:animationIndex_ time:seconds into:poseScratch_[0]];
  [self applyPose:poseScratch_[0]];
}

@end
