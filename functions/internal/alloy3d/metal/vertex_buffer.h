#pragma once

#import <Metal/Metal.h>
#include <algorithm>
#include <cstring>
#include <new>
#include <stdexcept>
#include <type_traits>

namespace alloy3d::metal
{
// One reusable frame page. The caller must wait for the GPU before reusing it,
// and hold its submission lock until all writes through the returned pointer end.
template <class Vertex> class VertexBuffer
{
  static_assert(std::is_trivially_copyable_v<Vertex>);
  id<MTLBuffer> buffer_   = nil;
  NSUInteger    capacity_ = 0;

public:
  VertexBuffer()                                = default;
  VertexBuffer(const VertexBuffer &)            = delete;
  VertexBuffer &operator=(const VertexBuffer &) = delete;
  ~VertexBuffer() { [buffer_ release]; }

  id<MTLBuffer> buffer() const { return buffer_; }
  NSUInteger    capacity() const { return capacity_; }

  // Preserve only the current frame's used vertices. Allocation failure leaves
  // the old buffer intact; callers advance their count only after success.
  Vertex *append(id<MTLDevice> device, NSUInteger used, NSUInteger count)
  {
    if (used <= capacity_ && count <= capacity_ - used)
      return buffer_ == nil ? nullptr : static_cast<Vertex *>(buffer_.contents) + used;
    const NSUInteger limit = device.maxBufferLength / sizeof(Vertex);
    if (used > capacity_ || used > limit || count > limit - used)
      throw std::length_error("Alloy3D vertex buffer exceeds device capacity");
    const NSUInteger required = used + count;
    if (required > capacity_)
    {
      NSUInteger capacity = std::min(limit, std::max<NSUInteger>(256, capacity_));
      while (capacity < required)
        capacity = capacity > limit / 2 ? limit : capacity * 2;
      auto replacement = [device newBufferWithLength:capacity * sizeof(Vertex)
                                             options:MTLResourceStorageModeShared];
      if (replacement == nil)
        throw std::bad_alloc();
      if (used != 0)
        std::memcpy(replacement.contents, buffer_.contents, used * sizeof(Vertex));
      [buffer_ release];
      buffer_   = replacement;
      capacity_ = capacity;
    }
    return buffer_ == nil ? nullptr : static_cast<Vertex *>(buffer_.contents) + used;
  }
};
} // namespace alloy3d::metal
