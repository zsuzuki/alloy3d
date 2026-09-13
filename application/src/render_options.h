#pragma once
#include <cstdint>
#include <stdexcept>

namespace alloy3d::internal
{
template <class Supports> uint32_t SelectSampleCount(uint32_t requested, Supports supports)
{
  if (requested != 1 && requested != 2 && requested != 4 && requested != 8)
    throw std::invalid_argument("Alloy3D sample count must be 1, 2, 4 or 8");
  while (requested > 1 && !supports(requested))
    requested /= 2;
  return requested;
}
} // namespace alloy3d::internal
